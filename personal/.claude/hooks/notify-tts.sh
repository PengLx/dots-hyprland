#!/usr/bin/env bash
# Fairy: Notification hook → TTS when sidebar is hidden.
set -u
. "$HOME/.claude/hooks/lib-tts.sh"
LOG=/tmp/fairy-hook.log
printf '[%s] Notification hook fired\n' "$(date +%H:%M:%S.%3N)" >> "$LOG"

is_fairy_session || { printf '  not fairy session, exit\n' >> "$LOG"; exit 0; }

input=$(cat)
printf '  payload=%s\n' "$(echo "$input" | jq -c '.' 2>/dev/null | head -c 500)" >> "$LOG"
msg=$(echo "$input" | jq -r '.message // .notification // empty' 2>/dev/null)
[ -z "$msg" ] && { printf '  no message field, exit\n' >> "$LOG"; exit 0; }
printf '  message=%s\n' "$(echo "$msg" | head -c 200)" >> "$LOG"

# Skip the noisy "Claude is waiting for your input" idle notification.
# (Stop hook handles real responses; voice-input handles the input flow.)
case "$msg" in
  *"waiting for your input"*|*"等待你的输入"*|*"等待您的输入"*)
    printf '  skipped (idle wait notification)\n' >> "$LOG"
    exit 0
    ;;
esac

if is_sidebar_visible; then
  printf '  sidebar visible, skip TTS\n' >> "$LOG"
  exit 0
fi
printf '  sidebar hidden, TTS now\n' >> "$LOG"
fairy_speak "$msg"
exit 0
