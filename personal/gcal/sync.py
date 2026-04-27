#!/usr/bin/env python3
"""Fetch Google Calendar events for all visible calendars and dump JSON.

Reads ~/.config/quickshell-gcal/credentials.json (created by login.py),
silently exchanges the refresh_token for an access_token (cached on disk
until expiry), then queries every calendar in the user's calendarList for
events in [now-30d, now+90d]. Output goes to
~/.local/state/quickshell/user/gcal_events.json (atomic replace), the file
the QML GoogleCalendar singleton watches.

Designed to be re-run on a timer (every few minutes); does nothing
expensive when nothing has changed.
"""
import datetime as dt
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "quickshell-gcal"
CREDS_FILE = CONFIG_DIR / "credentials.json"
TOKEN_CACHE = CONFIG_DIR / ".access_token.json"

STATE_DIR = Path.home() / ".local" / "state" / "quickshell" / "user"
OUT_FILE = STATE_DIR / "gcal_events.json"

API = "https://www.googleapis.com/calendar/v3"
WINDOW_PAST_DAYS = 30
WINDOW_FUTURE_DAYS = 90


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


def list_calendars(token: str) -> list:
    out = []
    page_token = None
    while True:
        url = f"{API}/users/me/calendarList?maxResults=250"
        if page_token:
            url += f"&pageToken={urllib.parse.quote(page_token)}"
        resp = http_get(url, token)
        out.extend(resp.get("items", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            return out


def list_events(token: str, calendar_id: str, time_min: str, time_max: str) -> list:
    out = []
    page_token = None
    while True:
        params = {
            "timeMin": time_min,
            "timeMax": time_max,
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": "2500",
        }
        if page_token:
            params["pageToken"] = page_token
        url = f"{API}/calendars/{urllib.parse.quote(calendar_id)}/events?{urllib.parse.urlencode(params)}"
        resp = http_get(url, token)
        out.extend(resp.get("items", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            return out


def is_holiday_calendar(cal: dict) -> bool:
    cid = cal.get("id", "")
    summary = (cal.get("summaryOverride") or cal.get("summary") or "").lower()
    return ("#holiday@" in cid) or ("holidays" in summary) or ("假日" in summary) or ("节假日" in summary)


def normalize_event(ev: dict, cal: dict, holiday: bool) -> dict:
    start = ev.get("start", {})
    end = ev.get("end", {})
    all_day = "date" in start and "dateTime" not in start
    return {
        "id": ev.get("id"),
        "calendar_id": cal.get("id"),
        "calendar_summary": cal.get("summaryOverride") or cal.get("summary"),
        "calendar_color": cal.get("backgroundColor"),
        "is_holiday": holiday,
        "summary": ev.get("summary", "(无标题)"),
        "description": ev.get("description"),
        "location": ev.get("location"),
        "all_day": all_day,
        "start": start.get("date") or start.get("dateTime"),
        "end": end.get("date") or end.get("dateTime"),
        "start_tz": start.get("timeZone"),
        "html_link": ev.get("htmlLink"),
    }


def main():
    if not CREDS_FILE.exists():
        sys.exit(f"Missing {CREDS_FILE}. Run login.py first.")
    creds = json.loads(CREDS_FILE.read_text())
    token = get_access_token(creds)

    now = dt.datetime.now(dt.timezone.utc)
    time_min = (now - dt.timedelta(days=WINDOW_PAST_DAYS)).isoformat(timespec="seconds").replace("+00:00", "Z")
    time_max = (now + dt.timedelta(days=WINDOW_FUTURE_DAYS)).isoformat(timespec="seconds").replace("+00:00", "Z")

    cals = list_calendars(token)
    events = []
    seen_cals = []
    for cal in cals:
        if cal.get("hidden") or cal.get("selected") is False:
            continue
        holiday = is_holiday_calendar(cal)
        try:
            evs = list_events(token, cal["id"], time_min, time_max)
        except Exception as e:
            print(f"[gcal-sync] failed to fetch {cal.get('summary')}: {e}", file=sys.stderr)
            continue
        for ev in evs:
            events.append(normalize_event(ev, cal, holiday))
        seen_cals.append({
            "id": cal["id"],
            "summary": cal.get("summaryOverride") or cal.get("summary"),
            "color": cal.get("backgroundColor"),
            "is_holiday": holiday,
            "primary": cal.get("primary", False),
        })

    # Sort by start time for stable rendering.
    events.sort(key=lambda e: (e.get("start") or "", e.get("calendar_id") or ""))

    payload = {
        "synced_at": now.astimezone().isoformat(timespec="seconds"),
        "window": {"start": time_min, "end": time_max},
        "calendars": seen_cals,
        "events": events,
    }

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=None))
    tmp.replace(OUT_FILE)
    print(f"[gcal-sync] wrote {len(events)} events from {len(seen_cals)} calendars to {OUT_FILE}")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:400]
        except Exception:
            pass
        sys.exit(f"[gcal-sync] HTTP {e.code} {e.reason}: {body}")
    except Exception as e:
        sys.exit(f"[gcal-sync] {e}")
