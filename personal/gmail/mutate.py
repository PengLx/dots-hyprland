#!/usr/bin/env python3
"""Gmail side-effects helper, env-var driven so QML's Process can call us
without quoting headaches.

Operations
----------
GMAIL_OP=fetch_body
    GMAIL_MSG_ID  — message id
    Lazy-loads the full message body, extracts plain text (preferring
    text/plain MIME parts; falls back to a stripped-down text/html
    rendering), caches it at ~/.cache/quickshell-gmail/bodies/<id>.txt,
    and prints the path on stdout.

GMAIL_OP=mark_read
    GMAIL_MSG_ID
    POSTs messages/<id>/modify with removeLabelIds=["UNREAD"].

GMAIL_OP=mark_unread
    GMAIL_MSG_ID
    addLabelIds=["UNREAD"].

GMAIL_OP=archive
    GMAIL_MSG_ID
    removeLabelIds=["INBOX"]. (Gmail's idea of "archive" — message stays
    in All Mail.)

Auth: ~/.config/quickshell-gmail/credentials.json. Requires
gmail.modify scope (re-run login.py if you previously logged in with
gmail.readonly).
"""
import base64
import html as html_mod
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "quickshell-gmail"
CREDS_FILE = CONFIG_DIR / "credentials.json"
TOKEN_CACHE = CONFIG_DIR / ".access_token.json"

CACHE_DIR = Path.home() / ".cache" / "quickshell-gmail" / "bodies"

API = "https://gmail.googleapis.com/gmail/v1"


def http_get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def http_post_json(url: str, token: str, data: dict) -> dict:
    body = json.dumps(data).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
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


# ---------- body extraction ----------

class _HTMLToText(HTMLParser):
    """Strip HTML to a plain-text approximation. Not a full renderer —
    just enough for newsletter / OTP body legibility."""

    def __init__(self):
        super().__init__()
        self._chunks: list[str] = []
        self._skip_depth = 0
        self._skip_tags = {"style", "script", "head"}

    def handle_starttag(self, tag, attrs):
        if tag in self._skip_tags:
            self._skip_depth += 1
        # Only <br> emits a newline on start. For block-level tags we wait
        # until the close tag, otherwise consecutive <p>...</p><p>...</p>
        # produces "\nA\n\nB\n" (a blank line between every short paragraph,
        # which is what newsletter HTML looks like → very sparse output).
        if tag == "br":
            self._chunks.append("\n")
        # Skip <img> entirely — alt text on newsletter images is mostly
        # icon names ("tiktok", "facebook", "play store") and adds noise.

    def handle_endtag(self, tag):
        if tag in self._skip_tags and self._skip_depth > 0:
            self._skip_depth -= 1
        if tag in {"p", "tr", "li", "div"}:
            self._chunks.append("\n")

    def handle_data(self, data):
        if self._skip_depth == 0:
            self._chunks.append(data)

    def text(self) -> str:
        joined = "".join(self._chunks)
        # html.unescape catches anything HTMLParser missed (it handles
        # named/numeric refs in handle_data when convert_charrefs=True,
        # but some emails come with double-escaped entities like
        # `&amp;#39;` which need a second pass).
        joined = html_mod.unescape(joined)
        # Collapse 3+ blank lines to 2; trim trailing whitespace per line.
        lines = [ln.rstrip() for ln in joined.splitlines()]
        collapsed: list[str] = []
        blanks = 0
        for ln in lines:
            if not ln.strip():
                blanks += 1
                if blanks <= 1:
                    collapsed.append("")
            else:
                blanks = 0
                collapsed.append(ln)
        return "\n".join(collapsed).strip()


def _decode_b64url(data: str) -> bytes:
    # Gmail uses base64url without padding; tolerate either form.
    pad = -len(data) % 4
    return base64.urlsafe_b64decode(data + ("=" * pad))


def _walk_parts(part: dict, *, prefer_text: bool):
    """Yield (mime_type, decoded_str_or_None) tuples for every leaf MIME
    part."""
    parts = part.get("parts")
    if parts:
        for p in parts:
            yield from _walk_parts(p, prefer_text=prefer_text)
        return
    body = part.get("body") or {}
    data = body.get("data")
    if not data:
        return
    mime = part.get("mimeType", "")
    try:
        raw = _decode_b64url(data)
        decoded = raw.decode("utf-8", errors="replace")
    except Exception:
        decoded = ""
    yield mime, decoded


def extract_body(msg: dict) -> str:
    """Best-effort plain-text body. Prefers text/plain; falls back to
    stripped HTML."""
    payload = msg.get("payload") or {}
    text_plain = []
    text_html = []
    for mime, body in _walk_parts(payload, prefer_text=True):
        if mime == "text/plain" and body:
            text_plain.append(body)
        elif mime == "text/html" and body:
            text_html.append(body)
    if text_plain:
        return "\n\n".join(s.strip() for s in text_plain).strip()
    if text_html:
        parser = _HTMLToText()
        for h in text_html:
            parser.feed(h)
        return parser.text()
    return msg.get("snippet", "")


def op_fetch_body(token: str) -> None:
    msg_id = os.environ.get("GMAIL_MSG_ID")
    if not msg_id:
        sys.exit("GMAIL_OP=fetch_body needs GMAIL_MSG_ID env var.")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIR / f"{msg_id}.txt"
    # If cached and non-empty, just emit the path and bail.
    if cache_path.exists() and cache_path.stat().st_size > 0:
        print(str(cache_path))
        return

    url = f"{API}/users/me/messages/{urllib.parse.quote(msg_id)}?format=full"
    raw = http_get(url, token)
    body = extract_body(raw)
    cache_path.write_text(body, encoding="utf-8")
    print(str(cache_path))


def op_modify_labels(token: str, *, add: list[str] | None = None,
                     remove: list[str] | None = None) -> None:
    msg_id = os.environ.get("GMAIL_MSG_ID")
    if not msg_id:
        sys.exit("This op needs GMAIL_MSG_ID env var.")
    body: dict = {}
    if add:
        body["addLabelIds"] = add
    if remove:
        body["removeLabelIds"] = remove
    url = f"{API}/users/me/messages/{urllib.parse.quote(msg_id)}/modify"
    http_post_json(url, token, body)
    print(f"[gmail-mutate] {msg_id}: add={add or []} remove={remove or []}")


def main():
    op = os.environ.get("GMAIL_OP", "")
    token = get_access_token()
    if op == "fetch_body":
        op_fetch_body(token)
    elif op == "mark_read":
        op_modify_labels(token, remove=["UNREAD"])
    elif op == "mark_unread":
        op_modify_labels(token, add=["UNREAD"])
    elif op == "archive":
        op_modify_labels(token, remove=["INBOX"])
    else:
        sys.exit(f"Unknown GMAIL_OP={op!r}. Use fetch_body / mark_read / mark_unread / archive.")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:300]
        except Exception:
            pass
        sys.exit(f"[gmail-mutate] HTTP {e.code} {e.reason}: {body}")
    except Exception as e:
        sys.exit(f"[gmail-mutate] {e}")
