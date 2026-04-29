# Cider RPC bridge

Cider's MPRIS implementation reports a fake length and a session-relative
position counter (Electron quirk). This bridge talks to Cider's local HTTP
RPC instead, which gives the real `currentPlaybackTime` and
`durationInMillis`. The QML `Cider` singleton in
`services/Cider.qml` polls the RPC once a second when Cider is the active
MPRIS player and overrides what the media-controls panel displays.

## Setup

1. Open Cider → **Settings → Connectivity → Manage External Application
   Access to Cider** → enable RPC, copy the API token.
2. Save the token locally:
   ```sh
   mkdir -p ~/.config/quickshell-cider
   chmod 700 ~/.config/quickshell-cider
   printf '%s' 'YOUR_TOKEN_HERE' > ~/.config/quickshell-cider/api_token
   chmod 600 ~/.config/quickshell-cider/api_token
   ```
3. The next time the media panel pops up while Cider is playing, the
   position / length / progress bar should be correct. Seeking on the
   slider goes through Cider's `/api/v1/playback/seek` endpoint.

## How to tell it's working

```sh
curl -s -H "apitoken: $(cat ~/.config/quickshell-cider/api_token)" \
     http://localhost:10767/api/v1/playback/now-playing | jq .info | head
```

Shows the real `name`, `currentPlaybackTime` (seconds), and
`durationInMillis`.

## Falls back gracefully

- No token file → singleton inert, MPRIS values are used
- Cider not running → singleton inert, MPRIS used (irrelevant since
  there's no Cider player to fix anyway)
- HTTP request fails (Cider quitting, RPC disabled) → singleton flips
  `connected: false`, MPRIS values used
