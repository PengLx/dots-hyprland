#!/usr/bin/env bash
# Batch translate end4's keybind description comments to Chinese.
# Re-runnable. Backups any *.conf to *.conf.bak-<timestamp> in same dir.
set -u

FILES=(
  "$HOME/.config/hypr/hyprland/keybinds.conf"
  "$HOME/.config/hypr/custom/keybinds.conf"
)

ts=$(date +%Y%m%d-%H%M%S)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  cp "$f" "$f.bak-$ts"
done

translate_file() {
  local f="$1"
  [ -f "$f" ] || return
  # Section headers (##!)
  sed -i \
    -e 's|##! Apps$|##! 应用|' \
    -e 's|##! User$|##! 用户|' \
    -e 's|##! Shell$|##! 桌面|' \
    -e 's|##! Window$|##! 窗口|' \
    -e 's|##! Session$|##! 会话|' \
    -e 's|##! Screen$|##! 屏幕|' \
    -e 's|##! Media$|##! 媒体|' \
    -e 's|##! Workspaces$|##! 工作区|' \
    -e 's|##! Workspace$|##! 工作区|' \
    -e 's|##! Utilities$|##! 工具|' \
    -e 's|##! Virtual machines$|##! 虚拟机|' \
    "$f"

  # Description comments — order: longer phrases first
  sed -i \
    -e 's|# Toggle search$|# 切换搜索|' \
    -e 's|# Toggle overview$|# 切换工作区总览|' \
    -e 's|# Toggle left sidebar$|# 切换左侧栏|' \
    -e 's|# Toggle right sidebar$|# 切换右侧栏|' \
    -e 's|# Toggle cheatsheet$|# 切换快捷键表|' \
    -e 's|# Toggle on-screen keyboard$|# 切换屏幕键盘|' \
    -e 's|# Toggle media controls$|# 切换媒体控制|' \
    -e 's|# Toggle session menu$|# 切换会话菜单|' \
    -e 's|# Toggle bar$|# 切换顶栏|' \
    -e 's|# Toggle overlay$|# 切换叠加层|' \
    -e 's|# Toggle scratchpad$|# 切换暂存区|' \
    -e 's|# Toggle mute$|# 切换静音|' \
    -e 's|# Toggle mic$|# 切换麦克风静音|' \
    -e 's|# Toggle Claude Code sidebar$|# 切换 Claude Code 侧边栏|' \
    -e 's|# Push-to-talk to Fairy (start)$|# Push-to-talk Fairy(按下)|' \
    -e 's|# Push-to-talk to Fairy (stop)$|# Push-to-talk Fairy(松开)|' \
    -e 's|# Clipboard history >> clipboard$|# 剪贴板历史 → 剪贴板|' \
    -e 's|# Copy clipboard history entry$|# 复制剪贴板历史条目|' \
    -e 's|# Emoji >> clipboard$|# Emoji → 剪贴板|' \
    -e 's|# Copy an emoji$|# 复制 emoji|' \
    -e 's|# Screen snip$|# 区域截图|' \
    -e 's|# Google Lens$|# Google Lens 反向搜图|' \
    -e 's|# Character recognition >> clipboard$|# OCR 文字识别 → 剪贴板|' \
    -e 's|# Translate screen content$|# 翻译屏幕内容|' \
    -e 's|# Pick color (Hex) >> clipboard$|# 取色(Hex)→ 剪贴板|' \
    -e 's|# Color picker$|# 取色器|' \
    -e 's|# Record region (no sound)$|# 区域录屏(无声)|' \
    -e 's|# Record screen (with sound)$|# 全屏录屏(有声)|' \
    -e 's|# Screenshot >> clipboard$|# 截图 → 剪贴板|' \
    -e 's|# Screenshot >> clipboard & file$|# 截图 → 剪贴板 \& 文件|' \
    -e 's|# Toggle wallpaper selector$|# 壁纸选择|' \
    -e 's|# Wallpaper selector$|# 壁纸选择|' \
    -e 's|# Select random wallpaper$|# 随机壁纸|' \
    -e 's|# Random wallpaper$|# 随机壁纸|' \
    -e 's|# Change wallpaper$|# 更换壁纸|' \
    -e 's|# Restart widgets$|# 重启 widgets|' \
    -e 's|# Cycle panel family$|# 切换面板风格|' \
    -e 's|# Edit shell config$|# 编辑 shell 配置|' \
    -e 's|# Edit extra keybinds$|# 编辑用户键位|' \
    -e 's|# Settings app$|# 设置|' \
    -e 's|# Terminal$|# 终端|' \
    -e 's|# File manager$|# 文件管理器|' \
    -e 's|# Browser$|# 浏览器|' \
    -e 's|# Code editor$|# 代码编辑器|' \
    -e 's|# Office software$|# 办公软件|' \
    -e 's|# Text editor$|# 文本编辑器|' \
    -e 's|# Volume mixer$|# 音量混音器|' \
    -e 's|# Task manager$|# 任务管理器|' \
    -e 's|# Move$|# 移动窗口|' \
    -e 's|# Resize$|# 调整窗口大小|' \
    -e 's|# Fullscreen$|# 全屏|' \
    -e 's|# Maximize$|# 最大化|' \
    -e 's|# Pin$|# 置顶|' \
    -e 's|# Close$|# 关闭|' \
    -e 's|# Float/Tile$|# 浮动/平铺|' \
    -e 's|# Send to scratchpad$|# 送到暂存区|' \
    -e 's|# Lock$|# 锁屏|' \
    -e 's|# Sleep$|# 休眠|' \
    -e 's|# Next track$|# 下一曲|' \
    -e 's|# Previous track$|# 上一曲|' \
    -e 's|# Play/pause media$|# 播放/暂停|' \
    -e 's|# Forcefully zap a window$|# 强杀窗口|' \
    -e 's|# Zoom in$|# 放大|' \
    -e 's|# Zoom out$|# 缩小|' \
    -e 's|# Fullscreen spoof$|# 伪全屏|' \
    -e 's|# AI summary for selected text|# 选中文本 AI 总结|' \
    -e 's|# Generate AI summary for selected text$|# 选中文本生成 AI 总结|' \
    -e 's|# Generate AI summary$|# 生成 AI 总结|' \
    -e 's|# Disable keybinds$|# 禁用键位|' \
    -e 's|# (terminal)$|# (终端)|' \
    -e 's|# (terminal) (alt)$|# (终端,备用)|' \
    -e 's|# (terminal) (for Ubuntu people)$|# (Ubuntu 习惯)|' \
    -e 's|# (browser)$|# (浏览器)|' \
    -e 's|# (alt)$|# (备用)|' \
    -e 's|# Focus in direction$|# 焦点方向移动|' \
    -e 's|# Move in direction$|# 窗口方向移动|' \
    -e 's|# Adjust split ratio$|# 调整分割比例|' \
    -e 's|# Switch to workspace$|# 切到工作区|' \
    -e 's|# Send to workspace$|# 送到工作区|' \
    -e 's|# Send to scratchpad$|# 送到暂存区|' \
    -e 's|# Cycle to next/previous workspace$|# 切下/上一工作区|' \
    -e 's|# Cycle next$|# 循环下一个|' \
    -e 's|# Cycle prev$|# 循环上一个|' \
    -e 's|# Cycle$|# 循环切换|' \
    -e 's|# Switch$|# 切换|' \
    -e 's|# Switching$|# 切换|' \
    -e 's|# Focusing$|# 焦点|' \
    -e 's|# Window split ratio$|# 窗口分割比例|' \
    -e 's|# Positioning mode$|# 定位模式|' \
    -e 's|# Recording stuff$|# 录屏相关|' \
    -e 's|# AI$|# AI|' \
    -e 's|# OCR$|# OCR|' \
    -e 's|# Zoom$|# 缩放|' \
    -e 's|# Zoom with keypad$|# 数字键盘缩放|' \
    -e 's|# Cursed stuff$|# 奇怪键位|' \
    -e 's|# Send to workspace # (1, 2, 3,...)$|# 送到工作区 # (1, 2, 3,...)|' \
    -e 's|# Send to workspace left/right$|# 送到左/右工作区|' \
    -e 's|# Focus workspace # (1, 2, 3,...)$|# 聚焦工作区 # (1, 2, 3,...)|' \
    -e 's|# Focus left/right$|# 焦点左/右|' \
    -e 's|# Focus busy left/right$|# 聚焦繁忙工作区左/右|' \
    -e 's|# Toggle wallpaper$|# 切换壁纸|' \
    -e 's|# Increase opacity$|# 增加不透明度|' \
    -e 's|# Decrease opacity$|# 减少不透明度|' \
    "$f"

  # `bindd = MOD,KEY, DESCRIPTION, dispatcher, args` — description is the 3rd field.
  # Cheatsheet renders THIS, not the trailing `#` comment. Order longest first.
  sed -i \
    -e 's|, Generate AI summary for selected text,|, 选中文本生成 AI 总结,|g' \
    -e 's|, Copy clipboard history entry,|, 复制剪贴板历史条目,|g' \
    -e 's|, Toggle wallpaper selector,|, 壁纸选择,|g' \
    -e 's|, Select random wallpaper,|, 随机壁纸,|g' \
    -e 's|, Clipboard history >> clipboard,|, 剪贴板历史 → 剪贴板,|g' \
    -e 's|, Toggle on-screen keyboard,|, 切换屏幕键盘,|g' \
    -e 's|, Toggle media controls,|, 切换媒体控制,|g' \
    -e 's|, Toggle right sidebar,|, 切换右侧栏,|g' \
    -e 's|, Toggle left sidebar,|, 切换左侧栏,|g' \
    -e 's|, Toggle session menu,|, 切换会话菜单,|g' \
    -e 's|, Toggle cheatsheet,|, 切换快捷键表,|g' \
    -e 's|, Toggle wallpaper,|, 切换壁纸,|g' \
    -e 's|, Toggle scratchpad,|, 切换暂存区,|g' \
    -e 's|, Toggle search,|, 切换搜索,|g' \
    -e 's|, Toggle overlay,|, 切换叠加层,|g' \
    -e 's|, Toggle overview,|, 切换工作区总览,|g' \
    -e 's|, Toggle bar,|, 切换顶栏,|g' \
    -e 's|, Toggle mute,|, 切换静音,|g' \
    -e 's|, Toggle mic,|, 切换麦克风静音,|g' \
    -e 's|, Toggle floating,|, 切换浮动,|g' \
    -e 's|, Toggle fullscreen,|, 切换全屏,|g' \
    -e 's|, Toggle pin,|, 切换置顶,|g' \
    -e 's|, Change wallpaper,|, 更换壁纸,|g' \
    -e 's|, Color picker,|, 取色器,|g' \
    -e 's|, Copy an emoji,|, 复制 emoji,|g' \
    -e 's|, Emoji >> clipboard,|, Emoji → 剪贴板,|g' \
    -e 's|, Move in direction,|, 移动焦点方向,|g' \
    -e 's|, Focus in direction,|, 切换焦点方向,|g' \
    -e 's|, Move window in direction,|, 移动窗口方向,|g' \
    -e 's|, Move window,|, 移动窗口,|g' \
    -e 's|, Resize window,|, 调整窗口大小,|g' \
    -e 's|, Adjust split ratio,|, 调整分割比例,|g' \
    -e 's|, Switch to workspace,|, 切到工作区,|g' \
    -e 's|, Send to workspace,|, 送到工作区,|g' \
    -e 's|, Send to scratchpad,|, 送到暂存区,|g' \
    -e 's|, Send to next workspace,|, 送到下一工作区,|g' \
    -e 's|, Send to previous workspace,|, 送到上一工作区,|g' \
    -e 's|, Cycle workspaces,|, 循环切换工作区,|g' \
    -e 's|, Cycle next,|, 循环下一个,|g' \
    -e 's|, Cycle prev,|, 循环上一个,|g' \
    -e 's|, Fullscreen,|, 全屏,|g' \
    -e 's|, Maximize,|, 最大化,|g' \
    -e 's|, Float/Tile,|, 浮动/平铺,|g' \
    -e 's|, Pin,|, 置顶,|g' \
    -e 's|, Lock,|, 锁屏,|g' \
    -e 's|, Sleep,|, 休眠,|g' \
    -e 's|, Shutdown,|, 关机,|g' \
    -e 's|, Reboot,|, 重启,|g' \
    -e 's|, Logout,|, 注销,|g' \
    -e 's|, Close,|, 关闭,|g' \
    -e 's|, Kill,|, 强杀,|g' \
    -e 's|, Forcefully zap a window,|, 强杀窗口,|g' \
    -e 's|, Next track,|, 下一曲,|g' \
    -e 's|, Previous track,|, 上一曲,|g' \
    -e 's|, Play/pause media,|, 播放/暂停,|g' \
    -e 's|, Volume up,|, 音量+,|g' \
    -e 's|, Volume down,|, 音量-,|g' \
    -e 's|, Brightness up,|, 亮度+,|g' \
    -e 's|, Brightness down,|, 亮度-,|g' \
    -e 's|, Zoom in,|, 放大,|g' \
    -e 's|, Zoom out,|, 缩小,|g' \
    -e 's|, Zoom reset,|, 重置缩放,|g' \
    -e 's|, Disable keybinds,|, 禁用键位,|g' \
    -e 's|, Reload Hyprland,|, 重新加载 Hyprland,|g' \
    -e 's|, Terminal,|, 终端,|g' \
    -e 's|, File manager,|, 文件管理器,|g' \
    -e 's|, Browser,|, 浏览器,|g' \
    -e 's|, Code editor,|, 代码编辑器,|g' \
    -e 's|, Settings app,|, 设置,|g' \
    -e 's|, Task manager,|, 任务管理器,|g' \
    -e 's|, Volume mixer,|, 音量混音器,|g' \
    "$f"
}

for f in "${FILES[@]}"; do
  translate_file "$f"
done

echo "Done. Backups at *.bak-$ts"
