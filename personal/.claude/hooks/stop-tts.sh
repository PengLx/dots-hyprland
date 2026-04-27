#!/usr/bin/env bash
# Fairy: Stop hook → TTS the last assistant reply, only when voice-input set the pending flag.
set -u
. "$HOME/.claude/hooks/lib-tts.sh"
LOG=/tmp/fairy-hook.log
printf '[%s] Stop hook fired\n' "$(date +%H:%M:%S.%3N)" >> "$LOG"

is_fairy_session || { printf '  not fairy, exit\n' >> "$LOG"; exit 0; }

PENDING="/tmp/fairy-voice-pending"
if [ ! -f "$PENDING" ]; then
  printf '  no pending flag, exit\n' >> "$LOG"
  exit 0
fi
rm -f "$PENDING"
printf '  pending flag found and cleared\n' >> "$LOG"

# Wait for Claude to flush the newest assistant message to JSONL before reading.
# The Stop event can fire before the writer is done.
sleep 1.0

input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$transcript_path" ] && { printf '  no transcript_path\n' >> "$LOG"; exit 0; }
[ ! -f "$transcript_path" ] && { printf '  transcript missing: %s\n' "$transcript_path" >> "$LOG"; exit 0; }
printf '  transcript=%s size=%s\n' "$transcript_path" "$(stat -c %s "$transcript_path")" >> "$LOG"

# Find last assistant message in JSONL transcript and concat its text blocks.
last_msg=$(TRANSCRIPT="$transcript_path" python3 - <<'PYEOF'
import json, os, sys
path = os.environ["TRANSCRIPT"]
last = None
with open(path) as f:
    for line in f:
        try: d = json.loads(line)
        except Exception: continue
        if d.get("type") == "assistant":
            last = d
if not last: sys.exit(0)
content = last.get("message", {}).get("content", [])
parts = [c.get("text","") for c in content if isinstance(c, dict) and c.get("type") == "text"]
out = "\n".join(p for p in parts if p).strip()
# Cap length to avoid 30s+ TTS bills on long answers
if len(out) > 1500: out = out[:1500] + "(后略)"
print(out)
PYEOF
)

[ -z "$last_msg" ] && { printf '  empty last_msg, exit\n' >> "$LOG"; exit 0; }
printf '  TTS last_msg=%s\n' "$(echo "$last_msg" | head -c 200)" >> "$LOG"
fairy_speak "$last_msg"
exit 0
