#!/usr/bin/env bash
# Download a booru image to ~/Pictures/Anime/saved/ with a timestamped name
# so it survives next random refresh.
#
# Usage:  save-image.sh <url> [referer]

set -euo pipefail

URL="${1:-}"
REFERER="${2:-}"

if [[ -z "$URL" ]]; then
    notify-send -a "图片保存" -u critical "保存失败" "URL 为空"
    exit 1
fi

DEST_DIR="$HOME/Pictures/Anime/saved"
mkdir -p "$DEST_DIR"

ts=$(date +%Y%m%d_%H%M%S)
ext="${URL##*.}"
ext="${ext%%[!a-zA-Z0-9]*}"
[[ -z "$ext" || ${#ext} -gt 5 ]] && ext="jpg"
dst="$DEST_DIR/${ts}.${ext}"

curl_args=(-fsSL --max-time 60 --retry 2)
if [[ -n "$REFERER" ]]; then
    curl_args+=(-e "$REFERER")
fi

if curl "${curl_args[@]}" "$URL" -o "$dst"; then
    notify-send -a "图片保存" -i "$dst" "已保存" "$dst"
else
    notify-send -a "图片保存" -u critical "保存失败" "下载错误,见终端"
    exit 2
fi
