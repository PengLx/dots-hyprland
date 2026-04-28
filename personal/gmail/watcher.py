#!/usr/bin/env python3
"""Gmail watcher — polls for new unread emails and dispatches each one to
`claude -p` with the gmail-triage MCP server. Claude reads the email,
consults notify-rules.md, and decides whether to call the notify_user
tool.

Run as a long-lived process (started by Hyprland exec-once via
gmail-watcher.sh). Tracks seen IDs in a state file so it doesn't re-notify
across restarts.

Auth: ~/.config/quickshell-gmail/credentials.json (run login.py first).
"""
import datetime as dt
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "quickshell-gmail"
CREDS_FILE = CONFIG_DIR / "credentials.json"
TOKEN_CACHE = CONFIG_DIR / ".access_token.json"

STATE_DIR = Path.home() / ".local" / "state" / "quickshell" / "user"
SEEN_FILE = STATE_DIR / "gmail_seen_ids.json"

SCRIPT_DIR = Path(__file__).resolve().parent
MCP_CONFIG = SCRIPT_DIR / "triage-mcp.json"

API = "https://gmail.googleapis.com/gmail/v1"
POLL_INTERVAL_SEC = 30
WINDOW_QUERY = "is:unread newer_than:10m"
MAX_PER_POLL = 10
SEEN_RETENTION = 500  # cap the seen-ID set size so it doesn't grow forever
TRIAGE_TIMEOUT_SEC = 60

CLAUDE_BIN = shutil.which("claude") or "claude"


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


def get_access_token() -> str:
    if not CREDS_FILE.exists():
        sys.exit(f"Missing {CREDS_FILE}. Run login.py first.")
    creds = json.loads(CREDS_FILE.read_text())
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


def load_seen() -> set[str]:
    if SEEN_FILE.exists():
        try:
            return set(json.loads(SEEN_FILE.read_text()))
        except Exception:
            return set()
    return set()


def save_seen(seen: set[str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    # Cap retention to avoid unbounded growth — keep most recent N (set order
    # isn't guaranteed but this is fine since we re-fetch within a 10m window).
    if len(seen) > SEEN_RETENTION:
        # Keep the last SEEN_RETENTION items in iteration order
        seen = set(list(seen)[-SEEN_RETENTION:])
    SEEN_FILE.write_text(json.dumps(sorted(seen)))


def list_message_ids(token: str) -> list[str]:
    """Fetch IDs of recent unread messages."""
    params = urllib.parse.urlencode({
        "q": WINDOW_QUERY,
        "maxResults": str(MAX_PER_POLL),
    })
    url = f"{API}/users/me/messages?{params}"
    resp = http_get(url, token)
    return [m["id"] for m in resp.get("messages", [])]


def fetch_message_metadata(token: str, msg_id: str) -> dict:
    """Fetch a message's headers + snippet (no full body — saves quota and
    keeps the prompt small)."""
    # metadataHeaders is a repeated query param in Gmail's API, not
    # comma-separated. Pass tuples so urlencode emits one entry each.
    params = urllib.parse.urlencode(
        [
            ("format", "metadata"),
            ("metadataHeaders", "From"),
            ("metadataHeaders", "To"),
            ("metadataHeaders", "Subject"),
            ("metadataHeaders", "Date"),
        ]
    )
    url = f"{API}/users/me/messages/{msg_id}?{params}"
    return http_get(url, token)


def parse_message(raw: dict) -> dict:
    """Reduce Gmail's payload to just the bits the triage prompt needs."""
    headers = {h["name"].lower(): h["value"]
               for h in raw.get("payload", {}).get("headers", [])}
    return {
        "id": raw.get("id"),
        "thread_id": raw.get("threadId"),
        "from": headers.get("from", ""),
        "to": headers.get("to", ""),
        "subject": headers.get("subject", ""),
        "date": headers.get("date", ""),
        "snippet": raw.get("snippet", ""),
        "label_ids": raw.get("labelIds", []),
    }


def triage_one(email: dict) -> None:
    """Hand the email to Claude Code (headless) with the triage MCP and
    let it decide whether to notify."""
    email_json = json.dumps(email, ensure_ascii=False)
    # Slash-invoke the MCP prompt via stdin so we don't fight option/positional
    # parsing (--allowedTools is variadic and was eating the positional).
    # Claude expands the prompt, reads the rules, and (optionally) calls the
    # notify_user tool.
    escaped = email_json.replace("'", "\\'")
    slash_prompt = f"/mcp__gmail-triage__triage_email email='{escaped}'"

    cmd = [
        CLAUDE_BIN, "-p",
        "--mcp-config", str(MCP_CONFIG),
        "--model", "claude-haiku-4-5",
        "--allowedTools", "mcp__gmail-triage__notify_user",
    ]

    try:
        result = subprocess.run(
            cmd,
            input=slash_prompt,
            timeout=TRIAGE_TIMEOUT_SEC,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(
                f"[gmail-watcher] triage exit {result.returncode} on {email['id']}:\n"
                f"  stderr: {result.stderr[:300]}\n"
                f"  stdout: {result.stdout[:300]}",
                file=sys.stderr,
            )
        else:
            # Log a compact summary so we can debug whether the AI decided
            # to notify or not. (notify_user output goes through the tool;
            # stdout here is just Claude's optional explanation.)
            sender = email.get("from", "")[:60]
            subj = email.get("subject", "")[:60]
            decision = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else "(no output)"
            print(f"[gmail-watcher] triaged {email['id']}: {sender} | {subj}\n  → {decision[:200]}")
    except subprocess.TimeoutExpired:
        print(f"[gmail-watcher] triage timeout on {email['id']}", file=sys.stderr)


def poll_once(seen: set[str]) -> int:
    """One pass: list new IDs, triage each, return count of newly triaged."""
    token = get_access_token()
    ids = list_message_ids(token)
    new_count = 0
    for msg_id in ids:
        if msg_id in seen:
            continue
        try:
            raw = fetch_message_metadata(token, msg_id)
        except Exception as e:
            print(f"[gmail-watcher] fetch {msg_id} failed: {e}", file=sys.stderr)
            continue
        email = parse_message(raw)
        triage_one(email)
        seen.add(msg_id)
        new_count += 1
    if new_count:
        save_seen(seen)
    return new_count


running = True


def _stop(*_):
    global running
    running = False


def main():
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    if not CREDS_FILE.exists():
        sys.exit(f"Missing {CREDS_FILE}. Run login.py first.")
    if not MCP_CONFIG.exists():
        sys.exit(f"Missing MCP config {MCP_CONFIG}.")

    seen = load_seen()
    print(f"[gmail-watcher] start; {len(seen)} ids remembered, polling every {POLL_INTERVAL_SEC}s")

    # On startup, prime the seen set with whatever's currently in the
    # WINDOW_QUERY — we don't want to spam-notify for emails that arrived
    # while the watcher wasn't running.
    if not seen:
        try:
            token = get_access_token()
            ids = list_message_ids(token)
            seen.update(ids)
            save_seen(seen)
            print(f"[gmail-watcher] cold-start primed with {len(ids)} existing unread ids")
        except Exception as e:
            print(f"[gmail-watcher] cold-start prime failed: {e}", file=sys.stderr)

    while running:
        try:
            n = poll_once(seen)
            if n:
                print(f"[gmail-watcher] triaged {n} new email(s)")
        except urllib.error.HTTPError as e:
            try:
                body = e.read().decode("utf-8", "replace")[:300]
            except Exception:
                body = ""
            print(f"[gmail-watcher] HTTP {e.code} {e.reason}: {body}", file=sys.stderr)
        except Exception as e:
            print(f"[gmail-watcher] error: {e}", file=sys.stderr)

        # Sleep with cooperative interrupt
        for _ in range(POLL_INTERVAL_SEC):
            if not running:
                break
            time.sleep(1)

    print("[gmail-watcher] shutdown")


if __name__ == "__main__":
    main()
