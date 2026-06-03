#!/usr/bin/env python3
# Translate the `description = "..."` strings in Hyprland's Lua keybinds to Chinese,
# for the Super+/ cheatsheet. Re-runnable & idempotent: only English keys are
# replaced, so re-run after pulling upstream changes. The cheatsheet groups by the
# text before the first ":", so categories are translated consistently.
#
# Usage: translate-keybinds-lua.py [path-to-keybinds.lua]
#   default path: ~/.config/hypr/hyprland/keybinds.lua
import os
import sys

# Category words (kept consistent so cheatsheet grouping stays intact):
#   App→应用 Media→媒体 Screen→屏幕 Session→会话 Shell→界面 Utilities→工具
#   Window→窗口 Workspace→工作区
TRANSLATIONS = {
    "App: Browser": "应用: 浏览器",
    "App: Code editor": "应用: 代码编辑器",
    "App: File manager": "应用: 文件管理器",
    "App: Office software": "应用: 办公软件",
    "App: Settings app": "应用: 设置",
    "App: Task manager": "应用: 任务管理器",
    "App: Terminal": "应用: 终端",
    "App: Text editor": "应用: 文本编辑器",
    "App: Volume mixer": "应用: 音量混合器",
    "Media: Next track": "媒体: 下一曲",
    "Media: Play/pause media": "媒体: 播放/暂停",
    "Media: Previous track": "媒体: 上一曲",
    "Media: Toggle mic": "媒体: 麦克风开关",
    "Media: Toggle mute": "媒体: 静音开关",
    "Screen: Zoom in": "屏幕: 放大",
    "Screen: Zoom out": "屏幕: 缩小",
    "Session: Lock": "会话: 锁屏",
    "Session: Shut down": "会话: 关机",
    "Session: Sleep": "会话: 睡眠",
    "Shell: Change wallpaper": "界面: 更换壁纸",
    "Shell: Cycle panel family": "界面: 切换面板风格",
    "Shell: Random wallpaper": "界面: 随机壁纸",
    "Shell: Restart widgets": "界面: 重启组件",
    "Shell: Toggle bar": "界面: 切换状态栏",
    "Shell: Toggle cheatsheet": "界面: 切换快捷键速查",
    "Shell: Toggle left sidebar": "界面: 切换左侧栏",
    "Shell: Toggle light/dark mode": "界面: 切换明暗模式",
    "Shell: Toggle media controls": "界面: 切换媒体控制",
    "Shell: Toggle on-screen keyboard": "界面: 切换屏幕键盘",
    "Shell: Toggle overview": "界面: 切换工作区总览",
    "Shell: Toggle right sidebar": "界面: 切换右侧栏",
    "Shell: Toggle search": "界面: 切换搜索",
    "Shell: Toggle session menu": "界面: 切换会话菜单",
    "Shell: Toggle widget overlay": "界面: 切换悬浮组件",
    "Utilities: Character recognition >> clipboard": "工具: 文字识别 → 剪贴板",
    "Utilities: Clipboard history >> clipboard": "工具: 剪贴板历史 → 剪贴板",
    "Utilities: Emoji >> clipboard": "工具: Emoji → 剪贴板",
    "Utilities: Generate AI summary for selected text": "工具: 为选中文本生成 AI 摘要",
    "Utilities: Google Lens": "工具: Google 识图",
    "Utilities: Pick color #RRGGBB >> clipboard": "工具: 取色 #RRGGBB → 剪贴板",
    "Utilities: Record region (no sound)": "工具: 录制区域(无声)",
    "Utilities: Record screen (with sound)": "工具: 录屏(带声音)",
    "Utilities: Screenshot >> clipboard": "工具: 截图 → 剪贴板",
    "Utilities: Screenshot >> clipboard & file": "工具: 截图 → 剪贴板和文件",
    "Utilities: Screen snip": "工具: 屏幕截取",
    "Utilities: Translate screen content": "工具: 翻译屏幕内容",
    "Window: Close": "窗口: 关闭",
    "Window: Float/Tile": "窗口: 浮动/平铺",
    "Window: Focus ": "窗口: 聚焦 ",
    "Window: Forcefully zap a window": "窗口: 强杀窗口",
    "Window: Fullscreen": "窗口: 全屏",
    "Window: Fullscreen spoof": "窗口: 伪全屏",
    "Window: Maximize": "窗口: 最大化",
    "Window: Move": "窗口: 移动",
    "Window: Move ": "窗口: 移动 ",
    "Window: Pin": "窗口: 置顶",
    "Window: Resize": "窗口: 调整大小",
    "Window: Send to scratchpad": "窗口: 发送到暂存区",
    "Window: Send to workspace ": "窗口: 发送到工作区 ",
    "Workspace: Focus ": "工作区: 聚焦 ",
    "Workspace: Toggle scratchpad": "工作区: 切换暂存区",
}


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.config/hypr/hyprland/keybinds.lua")
    with open(path, encoding="utf-8") as f:
        text = f.read()

    replaced = 0
    # Match the full quoted form so "Move" and "Move " (trailing space) stay distinct.
    for en, zh in TRANSLATIONS.items():
        needle = 'description = "%s"' % en
        repl = 'description = "%s"' % zh
        n = text.count(needle)
        if n:
            text = text.replace(needle, repl)
            replaced += n

    # Warn about any English descriptions we don't have a translation for
    import re
    leftover = sorted(set(re.findall(r'description = "([^"]*[A-Za-z][^"]*)"', text)))
    leftover = [d for d in leftover if d not in TRANSLATIONS.values()
                and not any(u'一' <= c <= u'鿿' for c in d)]

    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

    print("translated %d description(s) in %s" % (replaced, path))
    if leftover:
        print("⚠ untranslated (add to TRANSLATIONS):")
        for d in leftover:
            print("   " + repr(d))


if __name__ == "__main__":
    main()
