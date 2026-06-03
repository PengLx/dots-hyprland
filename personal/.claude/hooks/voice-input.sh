#!/usr/bin/env bash
# Fairy push-to-talk: bind=start (key down), bindr=stop (key up).
# Records via pw-record → Google STT → kitty remote-control send-text → flag pending TTS.
set -u

ENV_FILE="$HOME/.config/claude-tts/.env"
[ -f "$ENV_FILE" ] || { notify-send "Fairy voice-input" "Missing $ENV_FILE" 2>/dev/null; exit 1; }
set -a; . "$ENV_FILE"; set +a

PIDFILE=/tmp/fairy-voice.pid
WAVFILE=/tmp/fairy-voice.wav
PENDING=/tmp/fairy-voice-pending
KITTY_SOCK=unix:/tmp/kitty-fairy.sock

case "${1:-}" in
  start)
    # Aggressively kill any prior pw-record (PTT can fire start twice without stop)
    pkill -9 -f 'pw-record.*fairy-voice.wav' 2>/dev/null || true
    rm -f "$PIDFILE" "$WAVFILE"
    # Foreground pw-record backgrounded directly so $! is its real PID
    pw-record --target=@DEFAULT_SOURCE@ --rate=16000 --channels=1 --format=s16 "$WAVFILE" >/dev/null 2>&1 < /dev/null &
    echo $! > "$PIDFILE"
    notify-send -t 1500 -i microphone-sensitivity-high "Fairy" "Listening..." 2>/dev/null || true
    ;;

  stop)
    # Kill via PID file first, then sweep any leftover pw-record on our wav
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
    fi
    pkill -f 'pw-record.*fairy-voice.wav' 2>/dev/null || true
    sleep 0.3
    [ -s "$WAVFILE" ] || { notify-send -t 1500 "Fairy" "No audio captured" 2>/dev/null; exit 0; }

    [ -z "${GOOGLE_STT_API_KEY:-}" ] && { notify-send -t 2000 "Fairy" "Set GOOGLE_STT_API_KEY in claude-tts/.env" 2>/dev/null; exit 1; }

    # Google STT v1 sync recognize.
    # Use files + stdin pipe to avoid shell ARG_MAX (~2MB) on large audio.
    B64FILE=/tmp/fairy-voice.b64
    REQFILE=/tmp/fairy-stt-req.json
    base64 -w 0 "$WAVFILE" > "$B64FILE"
    jq -n --rawfile a "$B64FILE" '{
      config: {
        encoding: "LINEAR16",
        sampleRateHertz: 16000,
        languageCode: "zh-CN",
        alternativeLanguageCodes: ["en-US"],
        enableAutomaticPunctuation: true
      },
      audio: { content: $a }
    }' > "$REQFILE"
    resp=$(curl -sS --max-time 30 -X POST \
      "https://speech.googleapis.com/v1/speech:recognize?key=$GOOGLE_STT_API_KEY" \
      -H "Content-Type: application/json" \
      --data-binary @"$REQFILE" 2>/dev/null)
    rm -f "$B64FILE" "$REQFILE"

    text=$(echo "$resp" | jq -r '.results[0].alternatives[0].transcript // empty' 2>/dev/null)
    if [ -z "$text" ]; then
      err=$(echo "$resp" | jq -r '.error.message // "no transcript"' 2>/dev/null)
      notify-send -t 3000 "Fairy" "STT: $err" 2>/dev/null || true
      exit 0
    fi

    # Pre-arm voice-out
    touch "$PENDING"

    # Inject text + Enter into fairy
    if ! kitty @ --to=$KITTY_SOCK send-text --match=all "$text" 2>/dev/null; then
      notify-send -t 3000 "Fairy" "kitty remote-control unreachable. Heard: $text" 2>/dev/null
      rm -f "$PENDING"
      exit 1
    fi
    # Submit the prompt
    printf '\r' | kitty @ --to=$KITTY_SOCK send-text --match=all --stdin

    notify-send -t 2000 "Fairy" "→ $text" 2>/dev/null || true
    ;;

  *) echo "usage: $0 {start|stop}" >&2; exit 2 ;;
esac
