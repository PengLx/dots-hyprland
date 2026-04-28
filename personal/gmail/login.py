#!/usr/bin/env python3
"""One-time OAuth login for Gmail (read-only).

Reuses the OAuth client from ~/.config/quickshell-gcal/oauth_client.json
(same GCP project — just enable Gmail API on it). Stores Gmail's own
credentials separately at ~/.config/quickshell-gmail/credentials.json so
it can be revoked / re-issued without affecting Calendar.

Re-run if the refresh token gets revoked or you want to add scopes.
"""
import http.server
import json
import os
import secrets
import socket
import socketserver
import sys
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "quickshell-gmail"
GCAL_DIR = Path.home() / ".config" / "quickshell-gcal"

# Look for the OAuth client in our own dir first; fall back to gcal's.
CLIENT_FILE_CANDIDATES = [
    CONFIG_DIR / "oauth_client.json",
    GCAL_DIR / "oauth_client.json",
]
CREDS_FILE = CONFIG_DIR / "credentials.json"

# gmail.modify covers the watcher's read-only needs PLUS the sidebar's
# write actions (mark-as-read, archive). It does NOT permit sending
# email — that requires gmail.compose / gmail.send, which we don't want.
# If you previously logged in with gmail.readonly, re-run this script
# to upgrade the scope (Google revokes the readonly token automatically
# when consent for the new scope set is granted).
SCOPES = [
    "https://www.googleapis.com/auth/gmail.modify",
]


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def load_client():
    for path in CLIENT_FILE_CANDIDATES:
        if path.exists():
            data = json.loads(path.read_text())
            inner = data.get("installed") or data.get("web") or data
            return inner["client_id"], inner["client_secret"], path
    sys.exit(
        "Missing oauth_client.json.\n"
        "Either:\n"
        "  - Reuse calendar's:  ln -s ~/.config/quickshell-gcal/oauth_client.json "
        f"{CLIENT_FILE_CANDIDATES[0]}\n"
        "  - Or download a Desktop OAuth Client from "
        "https://console.cloud.google.com/apis/credentials\n"
        f"    and save it as {CLIENT_FILE_CANDIDATES[0]}\n"
        "\n"
        "Also make sure the Gmail API is enabled on the same GCP project.\n"
    )


def build_auth_url(client_id: str, redirect_uri: str, state: str) -> str:
    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    }
    return "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(params)


def exchange_code(client_id: str, client_secret: str, code: str, redirect_uri: str) -> dict:
    body = urllib.parse.urlencode({
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }).encode()
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    captured = {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/":
            self.send_error(404)
            return
        params = urllib.parse.parse_qs(parsed.query)
        CallbackHandler.captured["params"] = {k: v[0] for k, v in params.items()}
        body = (
            "<!doctype html><meta charset='utf-8'><body style='font-family:sans-serif;"
            "max-width:480px;margin:80px auto;text-align:center'>"
            "<h2>授权完成</h2><p>可以关闭此页面回到终端。</p></body>"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(CONFIG_DIR, 0o700)
    cid, cs, src = load_client()
    print(f"Using OAuth client from {src}")

    port = pick_free_port()
    redirect = f"http://127.0.0.1:{port}/"
    state = secrets.token_urlsafe(16)
    url = build_auth_url(cid, redirect, state)

    print("Opening browser for Google sign-in...")
    print(f"If it doesn't open automatically, visit:\n  {url}\n")

    with socketserver.TCPServer(("127.0.0.1", port), CallbackHandler) as srv:
        srv.timeout = 300
        webbrowser.open(url)
        srv.handle_request()

    captured = CallbackHandler.captured.get("params", {})
    if captured.get("state") != state:
        sys.exit("State mismatch — possible CSRF, aborting.")
    if "error" in captured:
        sys.exit(f"OAuth error: {captured['error']} — {captured.get('error_description', '')}")
    code = captured.get("code")
    if not code:
        sys.exit("No auth code returned. Did you cancel?")

    print("Exchanging code for tokens...")
    tokens = exchange_code(cid, cs, code, redirect)
    if "refresh_token" not in tokens:
        sys.exit(
            "No refresh_token returned. Google only issues a refresh_token on the\n"
            "FIRST consent. Revoke this app at https://myaccount.google.com/permissions\n"
            "and re-run login.py."
        )

    creds = {
        "client_id": cid,
        "client_secret": cs,
        "refresh_token": tokens["refresh_token"],
        "scope": tokens.get("scope", " ".join(SCOPES)),
        "token_uri": "https://oauth2.googleapis.com/token",
    }
    CREDS_FILE.write_text(json.dumps(creds, indent=2))
    os.chmod(CREDS_FILE, 0o600)
    print(f"Saved credentials to {CREDS_FILE} (mode 600).")

    cache = CONFIG_DIR / ".access_token.json"
    if cache.exists():
        cache.unlink()

    print("Now run watcher.py to start monitoring incoming emails.")


if __name__ == "__main__":
    main()
