# Linear sidebar integration

Adds a Linear tab to end4's left sidebar with four read views (Inbox / Cycle
Board / Projects / Activity) and one write FAB (create issue + change state).

Backend is plain `python3` + stdlib — no extra packages. State is cached at
`~/.local/state/quickshell/user/linear_data.json`; the QML `Linear` singleton
watches that file.

## Setup (one-time, ~2 minutes)

1. Open Linear → **Settings → API → Personal API keys → New**
2. Label it whatever (e.g. `quickshell-sidebar`); copy the key — you only see it once
3. Save it locally:

   ```sh
   mkdir -p ~/.config/quickshell-linear
   chmod 700 ~/.config/quickshell-linear
   printf '%s' 'lin_api_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
     > ~/.config/quickshell-linear/api_key
   chmod 600 ~/.config/quickshell-linear/api_key
   ```

   (PAT, not OAuth — picked because it's per-user and zero ceremony.)

4. Smoke-test:

   ```sh
   python3 ~/Projects/end4-staging/dots-hyprland/personal/linear/sync.py
   ```

   You should see `[linear-sync] wrote N issues, M projects, K notifications`.

5. Open the sidebar (`Super+A`); the Linear tab will populate within 5
   minutes (or immediately if the QML singleton picked up the new state file).

## Files

- `sync.py` — read-only fetch (viewer + teams/states + assigned issues +
  active-cycle issues + projects + notifications) → `linear_data.json`
- `mutate.py` — write helper. `LINEAR_OP=create` reads `LINEAR_BODY` JSON for
  `issueCreate`; `LINEAR_OP=set_state` takes `LINEAR_ISSUE_ID` + `LINEAR_STATE_ID`
- `api_key` (in `~/.config/quickshell-linear/`, NOT in this repo) — the PAT

## Refresh cadence

- 5 minutes via timer in `Linear.qml`
- Once on quickshell start
- Once after every mutation (so creates/state-changes show up immediately)

## Re-auth

Just regenerate the PAT in Linear and overwrite `~/.config/quickshell-linear/api_key`.
No token refresh dance — PATs don't expire unless you revoke them.
