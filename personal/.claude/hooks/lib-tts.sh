# Shared library for Fairy TTS hooks. Source this from hook scripts.
# Provides: fairy_speak <text>, is_fairy_session, is_sidebar_visible

is_fairy_session() {
  local pid=$$
  local i
  for i in $(seq 1 30); do
    [ "$pid" = "1" ] || [ -z "$pid" ] && break
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")
    if echo "$cmdline" | grep -qE 'claude.*(--name|-n)[ =]+fairy'; then
      return 0
    fi
    pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo 1)
  done
  return 1
}

is_sidebar_visible() {
  hyprctl monitors -j 2>/dev/null | jq -e '.[] | select(.specialWorkspace.name == "special:claude")' >/dev/null 2>&1
}

fairy_speak() {
  local text="$1"
  [ -z "$text" ] && return 0
  local env_file="$HOME/.config/claude-tts/.env"
  [ -f "$env_file" ] || return 0
  set -a; . "$env_file"; set +a
  [ -z "${MINIMAX_API_KEY:-}" ] && return 0

  local out_dir=/tmp/fairy-tts
  mkdir -p "$out_dir"
  local ts; ts=$(date +%s%N)
  local json_out="$out_dir/$ts.json"
  local mp3_out="$out_dir/$ts.mp3"

  curl -sS --max-time 30 -X POST "${MINIMAX_BASE_URL:-https://api.minimax.io}/v1/t2a_v2" \
    -H "Authorization: Bearer $MINIMAX_API_KEY" -H "Content-Type: application/json" \
    -d "$(jq -n --arg m "${MINIMAX_MODEL:-speech-2.8-hd}" \
      --arg v "${MINIMAX_VOICE_ID:-fairy_voice_2026}" \
      --argjson s "${MINIMAX_SPEED:-1.0}" --arg t "$text" \
      '{model:$m, text:$t, voice_setting:{voice_id:$v, speed:$s, vol:1, pitch:0}, audio_setting:{sample_rate:32000, bitrate:128000, format:"mp3", channel:1}}' \
    )" > "$json_out" 2>/dev/null || return 1

  JSON_OUT="$json_out" MP3_OUT="$mp3_out" python3 - <<'PYEOF' || return 1
import json, os, binascii, sys
try:
    d = json.load(open(os.environ["JSON_OUT"]))
    a = d.get("data", {}).get("audio")
    if a:
        open(os.environ["MP3_OUT"], "wb").write(binascii.unhexlify(a))
except Exception:
    sys.exit(1)
PYEOF

  [ -s "$mp3_out" ] || return 1

  # Prepend 400ms of silence so PipeWire sink wakes before audio starts
  # (otherwise the first syllable gets clipped on a suspended sink).
  local mp3_padded="${mp3_out}.padded.mp3"
  if ffmpeg -y -i "$mp3_out" -af "adelay=400" -loglevel error "$mp3_padded" 2>/dev/null && [ -s "$mp3_padded" ]; then
    mv -f "$mp3_padded" "$mp3_out"
  fi

  setsid -f mpv --no-video --really-quiet --volume-max=150 --volume=145 "$mp3_out" >/dev/null 2>&1 < /dev/null
  ls -t "$out_dir"/*.mp3 2>/dev/null | tail -n +21 | xargs -r rm -f
  ls -t "$out_dir"/*.json 2>/dev/null | tail -n +21 | xargs -r rm -f
  return 0
}
