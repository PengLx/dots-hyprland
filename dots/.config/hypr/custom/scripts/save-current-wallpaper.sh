#!/usr/bin/env bash
# Copy the currently-set wallpaper to ~/Pictures/Wallpapers/saved/ with a
# timestamp prefix so subsequent random-wallpaper switches don't overwrite it.

set -euo pipefail

CONFIG_JSON="$HOME/.config/illogical-impulse/config.json"
SAVED_DIR="$HOME/Pictures/Wallpapers/saved"

src=$(jq -r '.background.wallpaperPath' "$CONFIG_JSON")

if [[ -z "$src" || "$src" == "null" || ! -f "$src" ]]; then
    notify-send -a "壁纸保存" -u critical "保存失败" "找不到当前壁纸文件:\n$src"
    exit 1
fi

mkdir -p "$SAVED_DIR"

ts=$(date +%Y%m%d_%H%M%S)
base=$(basename "$src")
dst="$SAVED_DIR/${ts}_${base}"

# If the source already lives in saved/, just notify and exit — no duplication.
case "$src" in
    "$SAVED_DIR"/*)
        notify-send -a "壁纸保存" "已经保存过了" "$src"
        exit 0
        ;;
esac

cp -- "$src" "$dst"
notify-send -a "壁纸保存" -i "$dst" "壁纸已保存" "$dst"
