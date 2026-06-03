#!/usr/bin/env bash
# Toggle Fairy (claude-sidebar) between:
#   overlay mode  — lives on the special:claude workspace, shown/hidden via Super+,
#   pinned mode   — moved onto the CURRENT workspace and Hyprland-pinned (sticky:
#                   stays visible as you switch workspaces), floating, right edge.
#
# Under the Lua config, actions MUST go through `hyprctl dispatch 'hl.dsp...'`
# (not `eval`). Window is targeted by class selector so focus doesn't matter.
# Pin only works on a real workspace + floating window, so we move-then-pin.
set -u
SEL='class:^(claude-sidebar)$'

# Current workspace id of Fairy (id < 0 means it's on a special workspace)
ws=$(hyprctl clients -j | jq -r '.[] | select(.class=="claude-sidebar") | .workspace.id' | head -1)
[ -z "${ws:-}" ] && exit 0   # Fairy window not found

if [ "$ws" -lt 0 ]; then
  # Overlay (special) -> pin onto the current workspace
  hyprctl dispatch "hl.dsp.window.move({window=\"$SEL\", workspace=\"e+0\"})"
  hyprctl dispatch "hl.dsp.window.pin({window=\"$SEL\", action=\"on\"})"
  hyprctl dispatch "hl.dsp.window.bring_to_top({window=\"$SEL\"})"
else
  # Pinned on a real workspace -> unpin and send back to the special overlay
  hyprctl dispatch "hl.dsp.window.pin({window=\"$SEL\", action=\"off\"})"
  hyprctl dispatch "hl.dsp.window.move({window=\"$SEL\", workspace=\"special:claude\"})"
fi
