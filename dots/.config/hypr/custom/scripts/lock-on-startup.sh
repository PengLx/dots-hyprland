#!/usr/bin/env bash
# Wait for quickshell's `lock` IPC handler, then trigger the end4 lock screen.
# Falls back to hyprlock if quickshell never comes up within ~10s.
for _ in $(seq 1 40); do
    if qs -c ii ipc call lock activate 2>/dev/null; then
        exit 0
    fi
    sleep 0.25
done
exec hyprlock
