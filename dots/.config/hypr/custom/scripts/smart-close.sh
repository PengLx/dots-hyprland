#!/usr/bin/env bash
# Super+Q wrapper: if fairy is focused, hide it instead of killing.
cls=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
if [ "$cls" = "claude-sidebar" ]; then
  hyprctl dispatch togglespecialworkspace claude
else
  hyprctl dispatch killactive
fi
