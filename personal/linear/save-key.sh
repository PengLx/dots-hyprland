#!/usr/bin/env bash
# Interactive prompt for the Linear Personal API key, then writes it to
# ~/.config/quickshell-linear/api_key with strict perms.
#
# Used by:
#   - Settings switch "启用 Linear"  (when toggling on without an existing key)
#   - Sidebar Linear placeholder "提供 API Key" button
#
# Uses kdialog --password so the input is masked. Exits non-zero (clean) when
# the user cancels.

set -euo pipefail

CONFIG_DIR="$HOME/.config/quickshell-linear"
KEY_FILE="$CONFIG_DIR/api_key"

KEY="$(kdialog --password "粘贴你的 Linear Personal API Key:" --title "启用 Linear" 2>/dev/null || true)"

if [[ -z "$KEY" ]]; then
    # User cancelled / pressed Esc — exit silently.
    exit 1
fi

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# Trim trailing whitespace / newlines that paste sometimes adds.
KEY="${KEY%$'\n'}"
KEY="${KEY%$'\r'}"

# Sanity-check the prefix so we don't silently accept garbage.
if [[ "$KEY" != lin_api_* && "$KEY" != lin_oauth_* ]]; then
    notify-send -a "Linear" -u critical "API Key 格式可疑" \
        "Linear PAT 通常以 lin_api_ 开头。已取消保存。"
    exit 2
fi

printf '%s' "$KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

notify-send -a "Linear" -i task_alt "API Key 已保存" \
    "侧栏 Linear tab 即将开始同步(最长 10 秒)"
