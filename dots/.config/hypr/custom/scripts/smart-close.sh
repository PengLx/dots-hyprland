#!/usr/bin/env bash
# Super+Q wrapper: if fairy is focused, hide it instead of killing.
cls=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
# NB: under the Lua config, `hyprctl dispatch <legacy>` is reinterpreted as Lua
# (hl.dispatch(...)), so legacy dispatcher names no longer parse. Use hl.dsp.*.
if [ "$cls" = "claude-sidebar" ]; then
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("claude")'
else
  hyprctl dispatch 'hl.dsp.window.close()'
fi
