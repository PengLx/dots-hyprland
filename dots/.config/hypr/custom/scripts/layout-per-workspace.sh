#!/usr/bin/env bash
# Per-workspace Hyprland layout switcher (Lua-config compatible).
# Changes general:layout when the active workspace changes.
#
# Workspaces 1–6           → scrolling (niri-style, built into Hyprland 0.55+)
# Workspaces 7–9 & others  → dwindle   (Hyprland default tree)
# Special workspaces (e.g. claude) → ignored, layout untouched.
#
# NB: under the Lua config `hyprctl keyword` is disabled ("use eval"), so the
# layout is switched via `hyprctl eval 'hl.config({general={layout=...}})'`.

set -u

declare -A LAYOUT_FOR_WS=(
  [1]="scrolling" [2]="scrolling" [3]="scrolling"
  [4]="scrolling" [5]="scrolling" [6]="scrolling"
)
DEFAULT_LAYOUT="dwindle"

apply() {
  local ws="$1"
  # Only act on numeric (non-special) workspaces
  case "$ws" in
    [1-9]|[1-9][0-9]) : ;;
    *) return 0 ;;
  esac
  local target="${LAYOUT_FOR_WS[$ws]:-$DEFAULT_LAYOUT}"
  local current
  current=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // empty')
  if [ "$current" != "$target" ]; then
    hyprctl eval "hl.config({general={layout=\"$target\"}})" >/dev/null 2>&1
  fi
}

# Apply once at start based on current focus
init_ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
[ -n "$init_ws" ] && apply "$init_ws"

# Listen on the Hyprland event socket
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
exec socat -U - "UNIX-CONNECT:$SOCK" | while IFS= read -r line; do
  case "$line" in
    workspace\>\>*)
      apply "${line#workspace>>}"
      ;;
    workspacev2\>\>*)
      rest="${line#workspacev2>>}"
      apply "${rest%%,*}"
      ;;
  esac
done
