#!/usr/bin/env bash
# Migrate the live config to upstream end-4 + Hyprland Lua config.
# Installs the validated `lican-on-upstream` branch over the live ~/.config,
# arms the .conf -> .lua switch, and verifies with Hyprland's real parser.
# Does NOT restart Hyprland (that ends your session — you do it when ready).
#
# Safe to dry-run:  HOME=/tmp/dry  bash cutover.sh   (operates on that HOME)
set -euo pipefail

FORK="${FORK:-/home/lican/Projects/end4-staging/dots-hyprland}"
BRANCH="${BRANCH:-lican-on-upstream}"
TS="$(date +%Y%m%d-%H%M%S)"
CFG="$HOME/.config"
BACKUP="$CFG/_premigration-backup-$TS"

echo "==> dots-hyprland Lua migration cutover"
echo "    fork=$FORK branch=$BRANCH home=$HOME"

command -v Hyprland >/dev/null || { echo "!! Hyprland not found"; exit 1; }
git -C "$FORK" rev-parse --verify "$BRANCH" >/dev/null 2>&1 || { echo "!! branch $BRANCH not found in $FORK"; exit 1; }

# 1) Back up everything we touch
echo "[1/7] backup -> $BACKUP"
mkdir -p "$BACKUP"
for d in hypr quickshell matugen fontconfig; do
  [ -e "$CFG/$d" ] && cp -a "$CFG/$d" "$BACKUP/$d"
done

# 2) Export the branch tree to a temp dir (branch-checkout-independent)
echo "[2/7] export branch tree"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git -C "$FORK" archive "$BRANCH" dots/.config 2>/dev/null | tar -x -C "$TMP"
SRC="$TMP/dots/.config"

# git archive DROPS submodule contents (e.g. quickshell .../widgets/shapes) -> the
# install ends up missing a module and quickshell black-screens. Copy submodule
# working-tree contents from the fork into the export. (Bug found the hard way.)
git -C "$FORK" config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}' | while read -r sm; do
  [ -d "$FORK/$sm" ] || continue
  dst="$SRC/${sm#dots/.config/}"
  mkdir -p "$dst"
  rsync -a --exclude='.git' "$FORK/$sm/" "$dst/"
done

# 3) Shell + theming: mirror branch over live (authoritative; runtime state lives elsewhere)
echo "[3/7] quickshell / matugen / fontconfig"
rsync -a --delete "$SRC/quickshell/" "$CFG/quickshell/"
rsync -a "$SRC/matugen/"    "$CFG/matugen/"
rsync -a "$SRC/fontconfig/" "$CFG/fontconfig/"

# 4) Hypr: additively install the Lua tree (old *.conf are left as inert backups)
echo "[4/7] hypr Lua tree (additive)"
cp -a "$SRC/hypr/hyprland.lua" "$CFG/hypr/hyprland.lua"
rsync -a "$SRC/hypr/hyprland/" "$CFG/hypr/hyprland/"   # lua modules + lib/services/shellOverrides/scripts
rsync -a "$SRC/hypr/custom/"   "$CFG/hypr/custom/"     # *.lua overlays + scripts

# 5) Machine-local monitor config (DP-4 4K@160 1.5x, HDMI off)
echo "[5/7] monitors.lua"
cat > "$CFG/hypr/monitors.lua" <<'LUA'
hl.monitor({ output = "DP-4", mode = "3840x2160@160", position = "0x0", scale = 1.5 })
hl.monitor({ output = "HDMI-A-2", disabled = true })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA

# 6) Flip the entry so Hyprland auto-detects hyprland.lua on next start
echo "[6/7] rename hyprland.conf -> .conf.old"
[ -f "$CFG/hypr/hyprland.conf" ] && mv "$CFG/hypr/hyprland.conf" "$CFG/hypr/hyprland.conf.old" || true

# 7) Final real-parser verification of the LIVE config; auto-rollback hypr on failure
echo "[7/7] Hyprland --verify-config (live)"
if Hyprland --verify-config -c "$CFG/hypr/hyprland.lua" 2>&1 | grep -q 'config ok'; then
  echo "    config ok"
else
  echo "!! verify FAILED — rolling back hypr to .conf"
  rm -f "$CFG/hypr/hyprland.lua"
  [ -f "$CFG/hypr/hyprland.conf.old" ] && mv "$CFG/hypr/hyprland.conf.old" "$CFG/hypr/hyprland.conf"
  echo "   rolled back. quickshell/matugen are updated; hypr stays on .conf. backup: $BACKUP"
  exit 1
fi

cat <<EOF

==> Installed & verified. ONE more step (ends this session — do it when ready):
      hyprctl dispatch exit        # or log out / reboot
    On next login Hyprland loads the Lua config + the updated shell.

    Colors refresh on your next wallpaper change (matugen now targets colors.lua).

    Rollback (from a TTY: Ctrl+Alt+F3, log in):
      bash $FORK/personal/migrate-to-lua/rollback.sh
    Full pre-migration backup: $BACKUP
EOF
