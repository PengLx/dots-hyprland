#!/usr/bin/env python3
"""Add a Google Calendar event to the user's primary calendar.

Reads a JSON event body from the GCAL_ADD_BODY env var (preferred — the
QML caller uses this) or stdin, POSTs it to /calendars/primary/events,
and prints the API response (so the caller can confirm + grab the id).

Reuses sync.py's credentials/access-token logic — the access token cached
at ~/.config/quickshell-gcal/.access_token.json is shared.

Examples
--------

All-day event on a date:

    echo '{"summary":"Buy groceries","start":{"date":"2026-04-28"},"end":{"date":"2026-04-29"}}' \\
      | python3 add.py

Timed event:

    echo '{"summary":"Dentist","start":{"dateTime":"2026-04-28T10:00:00+08:00"},"end":{"dateTime":"2026-04-28T11:00:00+08:00"}}' \\
      | python3 add.py
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "quickshell-gcal"
CREDS_FILE = CONFIG_DIR / "credentials.json"
TOKEN_CACHE = CONFIG_DIR / ".access_token.json"

API = "https://www.googleapis.com/calendar/v3"


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
    return resp["access_token"]


def main():
    if not CREDS_FILE.exists():
        sys.exit(f"Missing {CREDS_FILE}. Run login.py first.")
    creds = json.loads(CREDS_FILE.read_text())
    token = get_access_token(creds)

    raw = os.environ.get("GCAL_ADD_BODY", "")
    if not raw:
        raw = sys.stdin.read()
    if not raw.strip():
        sys.exit("Empty input. Set GCAL_ADD_BODY or pipe JSON via stdin.")
    body = json.loads(raw)

    if "summary" not in body or "start" not in body or "end" not in body:
        sys.exit("Event JSON must have at least summary, start, end")

    req = urllib.request.Request(
        f"{API}/calendars/primary/events",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        created = json.loads(resp.read())

    print(json.dumps({"ok": True, "id": created.get("id"), "htmlLink": created.get("htmlLink")}))


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        msg = ""
        try:
            msg = e.read().decode("utf-8", "replace")[:400]
        except Exception:
            pass
        sys.exit(f"[gcal-add] HTTP {e.code} {e.reason}: {msg}")
    except Exception as e:
        sys.exit(f"[gcal-add] {e}")
