#!/usr/bin/env bash
# Revert the Hyprland .conf -> .lua switch (the only session-affecting part).
# quickshell/matugen updates are left in place (reversible separately, and an
# improvement). For a TOTAL revert, restore from ~/.config/_premigration-backup-*.
set -euo pipefail
HYPR="$HOME/.config/hypr"

if [ -f "$HYPR/hyprland.lua" ]; then
  mv "$HYPR/hyprland.lua" "$HYPR/hyprland.lua.disabled-$(date +%s)"
  echo "disabled hyprland.lua"
fi
if [ -f "$HYPR/hyprland.conf.old" ]; then
  mv "$HYPR/hyprland.conf.old" "$HYPR/hyprland.conf"
  echo "restored hyprland.conf"
fi

echo
echo "Reverted hypr to the .conf config. Restart Hyprland to apply:"
echo "    hyprctl dispatch exit     # or log out / reboot"
echo
echo "Full pre-migration backups (hypr + quickshell + matugen + fontconfig):"
ls -d "$HOME/.config/_premigration-backup-"* 2>/dev/null || echo "  (none found)"
echo "To fully restore one:  cp -a <backup>/hypr ~/.config/  (etc.)"
