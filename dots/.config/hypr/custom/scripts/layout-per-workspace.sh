#!/usr/bin/env bash
# Per-workspace Hyprland layout switcher.
# Listens on the Hyprland event socket and changes `general:layout`
# when the active workspace changes.
#
# Workspaces 1, 2, 3 → scrolling (niri-style infinite tape)
# Workspaces 4–9    → dwindle  (Hyprland default tree)
# Special workspaces (e.g. claude) → ignored, layout untouched

set -u

declare -A LAYOUT_FOR_WS=(
  [1]="scrolling"
  [2]="scrolling"
  [3]="scrolling"
  [8]="hy3"
  [9]="master"
)
DEFAULT_LAYOUT="dwindle"

# hy3-only keybinds (loaded when entering an hy3 workspace, unloaded on leave)
HY3_BINDS=(
  "SUPER ALT,V,hy3:makegroup,v"
  "SUPER ALT,H,hy3:makegroup,h"
  "SUPER ALT,W,hy3:changegroup,tab"
  "SUPER ALT,E,hy3:changegroup,opposite"
  "SUPER ALT,Tab,hy3:focustab,r"
  "SUPER ALT SHIFT,Tab,hy3:focustab,l"
)

bind_hy3() {
  for b in "${HY3_BINDS[@]}"; do
    hyprctl keyword bind "$b" >/dev/null 2>&1
  done
}

unbind_hy3() {
  for b in "${HY3_BINDS[@]}"; do
    # unbind takes only "MODS,KEY" — strip the dispatcher trailing fields
    local key="${b%%,*}"
    local rest="${b#*,}"
    local keyname="${rest%%,*}"
    hyprctl keyword unbind "$key,$keyname" >/dev/null 2>&1
  done
}

LAST_LAYOUT=""

apply() {
  local ws="$1"
  # Skip special: workspaces and anything non-numeric
  case "$ws" in
    [1-9]|[1-9][0-9]) : ;;
    *) return 0 ;;
  esac
  local target="${LAYOUT_FOR_WS[$ws]:-$DEFAULT_LAYOUT}"
  local current
  current=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // empty')
  if [ "$current" != "$target" ]; then
    hyprctl keyword general:layout "$target" >/dev/null 2>&1
  fi
  # Toggle hy3-only keybinds on layout transitions
  if [ "$LAST_LAYOUT" != "hy3" ] && [ "$target" = "hy3" ]; then
    bind_hy3
  elif [ "$LAST_LAYOUT" = "hy3" ] && [ "$target" != "hy3" ]; then
    unbind_hy3
  fi
  LAST_LAYOUT="$target"
}

# Apply once at start based on current focus
init_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
[ -n "$init_ws" ] && apply "$init_ws"

# Listen on event socket
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
exec socat -U - "UNIX-CONNECT:$SOCK" | while IFS= read -r line; do
  case "$line" in
    workspace\>\>*)
      ws="${line#workspace>>}"
      apply "$ws"
      ;;
    workspacev2\>\>*)
      # workspacev2 format: ID,NAME
      rest="${line#workspacev2>>}"
      ws="${rest%%,*}"
      apply "$ws"
      ;;
  esac
done
