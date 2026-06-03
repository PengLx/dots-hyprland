# Google Calendar integration

End4 sidebar's calendar widget shows event dots + a per-day list, fed by
this folder's helpers.

## One-time setup

1. https://console.cloud.google.com → create/pick a project.
2. **APIs & Services → Library** → search "Google Calendar API" → Enable.
3. **APIs & Services → OAuth consent screen** → External (testing). Add
   your Google address as a test user. Don't add scopes here yet.
4. **APIs & Services → Credentials → Create Credentials → OAuth Client ID**
   → Application type **Desktop app** → Create → **Download JSON**.
5. Save the JSON as `~/.config/quickshell-gcal/oauth_client.json`.
6. Run the login flow:

   ```bash
   python3 personal/gcal/login.py
   ```

   Browser opens, sign in, click Allow on the read-only scope. Terminal
   prints "Saved credentials". You're done — `~/.config/quickshell-gcal/credentials.json`
   now holds the long-lived `refresh_token` (chmod 600).

7. (Holidays) In Google Calendar web UI: left sidebar → Other calendars →
   `+` → Browse calendars of interest → check your country's holidays.
   The next sync picks them up automatically.

## How it works

- `sync.py` exchanges `refresh_token` → `access_token` (cached at
  `~/.config/quickshell-gcal/.access_token.json` until expiry), lists
  every visible calendar, fetches events in `[now-30d, now+90d]` with
  `singleEvents=true` (RRULE-expanded), and writes the merged result to
  `~/.local/state/quickshell/user/gcal_events.json`.
- The QML `GoogleCalendar` singleton watches that file and runs `sync.py`
  on a 5-minute timer + once at quickshell start.
- Calendars whose id matches `*#holiday@group.v.calendar.google.com` (or
  whose name says "假日"/"holidays") are flagged `is_holiday: true` so
  the day cell can render them differently from regular events.

## Re-auth

If Google revokes the refresh token (long inactivity, password change,
scope change), `sync.py` will fail with HTTP 400 `invalid_grant`. Re-run
`python3 personal/gcal/login.py` to mint a new one.

## Files (gitignored — recreate after fresh install)

- `~/.config/quickshell-gcal/oauth_client.json` — from Google Console
- `~/.config/quickshell-gcal/credentials.json`  — from `login.py`
- `~/.config/quickshell-gcal/.access_token.json` — sync.py runtime cache
- `~/.local/state/quickshell/user/gcal_events.json` — sync output
