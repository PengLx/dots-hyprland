#!/usr/bin/env python3
"""Periodic Gmail inbox sync for the quickshell sidebar.

Pulls the 50 most recent messages in the user's inbox (q="in:inbox"),
fetches each one's metadata + snippet (no body — that's lazy-loaded by
mutate.py on click), and atomically writes the result to
~/.local/state/quickshell/user/gmail_data.json. The QML Gmail singleton
watches that file.

Designed to be re-run on a 5-minute timer (matches gcal/sync.py
cadence). Cheap — one list call + N metadata calls, but we skip
metadata for IDs we already have cached unless their labelIds may have
changed (we always re-fetch labels anyway).

Auth: ~/.config/quickshell-gmail/credentials.json (run login.py first).
"""
import datetime as dt
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "quickshell-gmail"
CREDS_FILE = CONFIG_DIR / "credentials.json"
TOKEN_CACHE = CONFIG_DIR / ".access_token.json"

STATE_DIR = Path.home() / ".local" / "state" / "quickshell" / "user"
OUT_FILE = STATE_DIR / "gmail_data.json"

API = "https://gmail.googleapis.com/gmail/v1"
LIST_QUERY = "in:inbox"
LIST_LIMIT = 50


def http_get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def post_form(url: str, fields: dict) -> dict:
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def get_access_token(creds: dict) -> str:
    now = time.time()
    if TOKEN_CACHE.exists():
        try:
            cached = json.loads(TOKEN_CACHE.read_text())
            if cached.get("expires_at", 0) - 60 > now:
                return cached["access_token"]
        except Exception:
            pass
    resp = post_form(creds["token_uri"], {
        "client_id": creds["client_id"],
        "client_secret": creds["client_secret"],
        "refresh_token": creds["refresh_token"],
        "grant_type": "refresh_token",
    })
    token = resp["access_token"]
    expires_at = now + int(resp.get("expires_in", 3600))
    TOKEN_CACHE.write_text(json.dumps({"access_token": token, "expires_at": expires_at}))
    os.chmod(TOKEN_CACHE, 0o600)
    return token


def list_message_ids(token: str) -> list[dict]:
    """List messages matching LIST_QUERY. Returns minimal {id, threadId}."""
    out = []
    page_token = None
    while len(out) < LIST_LIMIT:
        params = {
            "q": LIST_QUERY,
            "maxResults": str(min(LIST_LIMIT - len(out), 100)),
        }
        if page_token:
            params["pageToken"] = page_token
        url = f"{API}/users/me/messages?{urllib.parse.urlencode(params)}"
        resp = http_get(url, token)
        out.extend(resp.get("messages", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return out[:LIST_LIMIT]


def fetch_metadata(token: str, msg_id: str) -> dict:
    # Gmail's API expects metadataHeaders as a *repeated* query param, not
    # comma-separated. doseq=True makes urlencode emit one ?metadataHeaders=
    # per list entry.
    params = urllib.parse.urlencode(
        [
            ("format", "metadata"),
            ("metadataHeaders", "From"),
            ("metadataHeaders", "To"),
            ("metadataHeaders", "Cc"),
            ("metadataHeaders", "Subject"),
            ("metadataHeaders", "Date"),
        ]
    )
    url = f"{API}/users/me/messages/{msg_id}?{params}"
    return http_get(url, token)


def parse_addr(raw: str) -> dict:
    """Split "Name <addr@example.com>" → {name, email}. Falls back to bare
    addr or empty fields when the input is malformed."""
    raw = (raw or "").strip()
    if "<" in raw and raw.endswith(">"):
        name = raw[: raw.rfind("<")].strip().strip('"').strip()
        email = raw[raw.rfind("<") + 1 : -1].strip()
        return {"name": name or email, "email": email}
    if "@" in raw:
        return {"name": raw, "email": raw}
    return {"name": raw, "email": ""}


def normalize(raw: dict) -> dict:
    headers = {h["name"].lower(): h["value"]
               for h in (raw.get("payload") or {}).get("headers", [])}
    label_ids = raw.get("labelIds", [])
    return {
        "id": raw.get("id"),
        "thread_id": raw.get("threadId"),
        "snippet": raw.get("snippet", ""),
        "internal_date": raw.get("internalDate"),  # ms since epoch (string)
        "size_estimate": raw.get("sizeEstimate"),
        "from": parse_addr(headers.get("from", "")),
        "to": parse_addr(headers.get("to", "")),
        "subject": headers.get("subject", "(无主题)"),
        "date_header": headers.get("date", ""),
        "label_ids": label_ids,
        "is_unread": "UNREAD" in label_ids,
        "is_starred": "STARRED" in label_ids,
        "is_important": "IMPORTANT" in label_ids,
        "categories": [l for l in label_ids if l.startswith("CATEGORY_")],
    }


def main():
    if not CREDS_FILE.exists():
        sys.exit(f"Missing {CREDS_FILE}. Run login.py first.")
    creds = json.loads(CREDS_FILE.read_text())
    token = get_access_token(creds)

    msgs = list_message_ids(token)
    if not msgs:
        print("[gmail-sync] no messages in inbox", file=sys.stderr)

    out = []
    for m in msgs:
        try:
            raw = fetch_metadata(token, m["id"])
        except Exception as e:
            print(f"[gmail-sync] fetch {m['id']} failed: {e}", file=sys.stderr)
            continue
        out.append(normalize(raw))

    payload = {
        "synced_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "query": LIST_QUERY,
        "messages": out,
    }

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False))
    tmp.replace(OUT_FILE)

    n_unread = sum(1 for m in out if m["is_unread"])
    print(f"[gmail-sync] wrote {len(out)} messages ({n_unread} unread) to {OUT_FILE}")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:400]
        except Exception:
            pass
        sys.exit(f"[gmail-sync] HTTP {e.code} {e.reason}: {body}")
    except Exception as e:
        sys.exit(f"[gmail-sync] {e}")
