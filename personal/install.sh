#!/usr/bin/env bash
# Deploy the user-only overlay (files end4's setup doesn't manage):
#   personal/.config/...  ->  $HOME/.config/...
#   personal/.claude/...  ->  $HOME/.claude/...
#
# Idempotent. Uses rsync without --delete so it WON'T wipe anything you have
# alongside the synced files. Re-run after pulling fork updates.
#
# Files NOT touched by this script (managed elsewhere):
#   - dots/.config/...           — installed by `./setup install-files`
#   - personal/.config/hypr/_example.monitors.conf — hardware-specific reference only,
#     copy to ~/.config/hypr/custom/monitors.conf manually after editing for your monitors
#
# Secrets (NEVER in git, fill in manually after fresh install):
#   ~/.config/todoist_token              (Todoist API token)
#   ~/.config/claude-tts/.env            (MINIMAX_API_KEY, GOOGLE_STT_API_KEY)
#   ~/.config/obsidian-mcp/.env          (OBSIDIAN_API_KEY, OBSIDIAN_HOST)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

deploy() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then return; fi
  mkdir -p "$(dirname "$dst")"
  rsync -a --no-owner --no-group "$src" "$dst"
  echo "  $src -> $dst"
}

echo "==> Deploying personal/ overlay to \$HOME"

# .config — recursive but exclude the example monitor config
rsync -a --no-owner --no-group \
  --exclude '_example.monitors.conf' \
  ".config/" "$HOME/.config/"
echo "  .config/* -> ~/.config/"

# .claude — recursive
rsync -a --no-owner --no-group \
  ".claude/" "$HOME/.claude/"
echo "  .claude/* -> ~/.claude/"

# Make scripts executable
chmod +x "$HOME"/.claude/hooks/*.sh 2>/dev/null || true
chmod +x "$HOME"/.config/hypr/translate-keybinds.sh 2>/dev/null || true

echo
echo "==> Done."
echo
echo "Manual follow-ups (one-time, on a fresh machine):"
echo "  1. Edit ~/.config/hypr/custom/monitors.conf for your displays"
echo "     (reference: personal/.config/hypr/_example.monitors.conf)"
echo "  2. Create secret files:"
echo "     - ~/.config/todoist_token            (Todoist API token, single line)"
echo "     - ~/.config/claude-tts/.env          (MiniMax + Google STT keys)"
echo "     - ~/.config/obsidian-mcp/.env        (Obsidian API key + host)"
echo "  3. Restart fcitx5 / quickshell / Hyprland to pick up changes"
