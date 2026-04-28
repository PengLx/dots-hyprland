#!/usr/bin/env bash
# Hyprland exec-once wrapper for the Gmail watcher. Re-runs the python
# script in a tight loop if it crashes (with a small backoff so we don't
# busy-spin on auth/network failures). Logs go to ~/.cache/quickshell-gmail.

set -uo pipefail

LOG_DIR="$HOME/.cache/quickshell-gmail"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/watcher.log"
WATCHER="$HOME/Projects/end4-staging/dots-hyprland/personal/gmail/watcher.py"

# Single-instance lock so multiple Hyprland reloads don't pile up workers.
LOCK_FILE="$LOG_DIR/watcher.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[gmail-watcher.sh] another instance is already running" | tee -a "$LOG_FILE"
    exit 0
fi

if [[ ! -x "$WATCHER" ]]; then
    echo "[gmail-watcher.sh] $WATCHER not found / not executable" | tee -a "$LOG_FILE"
    exit 1
fi

backoff=5
while true; do
    {
        echo "---- $(date '+%F %T') starting watcher ----"
        python3 "$WATCHER"
        ec=$?
        echo "---- $(date '+%F %T') watcher exited with $ec, sleeping ${backoff}s ----"
    } >>"$LOG_FILE" 2>&1
    sleep "$backoff"
    # Exponential-ish backoff up to 5 minutes
    if (( backoff < 300 )); then
        backoff=$(( backoff * 2 ))
    fi
done
