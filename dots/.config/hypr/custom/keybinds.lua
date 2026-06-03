-- 编辑 shell / 用户配置
hl.bind("CTRL + SUPER + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/illogical-impulse/config.json"), { description = "自定义: 编辑 Shell 配置" })
hl.bind("CTRL + SUPER + ALT + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), { description = "自定义: 编辑用户键位" })

-- 切换 Fairy(Claude 侧边栏)显示/隐藏(special 覆盖层)
hl.bind("SUPER + comma", hl.dsp.workspace.toggle_special("claude"), { description = "自定义: 切换 Fairy 侧边栏" })
-- 把 Fairy 钉到当前工作区(浮动+置顶,跨工作区常驻);再按收回 special 覆盖层
hl.bind("SUPER + SHIFT + comma", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/fairy-pin.sh"), { description = "自定义: Fairy 钉到当前工作区 / 收回" })

-- Super+Q:Fairy 上隐藏,否则关闭(替换默认 killactive,需先 unbind 否则叠加触发)
hl.unbind("SUPER + Q")
hl.bind("SUPER + Q", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/smart-close.sh"), { description = "自定义: 关闭窗口(Fairy 隐藏)" })

-- Fairy 语音输入 Push-to-talk(按下开始 / 松开停止)
hl.bind("SUPER + grave", hl.dsp.exec_cmd("~/.claude/hooks/voice-input.sh start"), { description = "自定义: Fairy 语音输入(按住说话)" })
hl.bind("SUPER + grave", hl.dsp.exec_cmd("~/.claude/hooks/voice-input.sh stop"), { release = true })

-- 滚动布局(WS 1-6)niri 风格列管理。这些命令在 dwindle 工作区上为无害空操作,
-- 故全局绑定即可(焦点上下/左右仍可用默认 Super+方向键)。
hl.bind("SUPER + bracketleft",        hl.dsp.layout("focus l"),          { description = "滚动: 焦点左列" })
hl.bind("SUPER + bracketright",       hl.dsp.layout("focus r"),          { description = "滚动: 焦点右列" })
hl.bind("SUPER + SHIFT + bracketleft",  hl.dsp.layout("swapcol l"),      { description = "滚动: 移窗到左列" })
hl.bind("SUPER + SHIFT + bracketright", hl.dsp.layout("swapcol r"),      { description = "滚动: 移窗到右列" })
hl.bind("SUPER + minus",  hl.dsp.layout("colresize -conf"),              { description = "滚动: 列宽 −" })
hl.bind("SUPER + equal",  hl.dsp.layout("colresize +conf"),              { description = "滚动: 列宽 +" })
hl.bind("SUPER + U",         hl.dsp.layout("consume_or_expel"),          { description = "滚动: 并入/弹出列" })
hl.bind("SUPER + SHIFT + U", hl.dsp.layout("promote"),                   { description = "滚动: 独立成列" })
hl.bind("SUPER + period", hl.dsp.layout("fit active"),                   { description = "滚动: 居中当前列" })

-- 修复「Super+Alt+数字 一次按键移走两个窗口」:upstream 把发送到工作区同时绑了 keysym
-- (1-0)和数字行 keycode(code:10-19),标准键盘上是同一批物理键 → 一次按键触发两次。
-- 第一次移走焦点窗后焦点跳到下一个,第二次把它也移走。解绑重复的数字行 keycode 那套
-- (keysym 已够用且带中文描述;小键盘 code:87-90 不冲突,保留)。
for _, kc in ipairs({ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }) do
    hl.unbind("SUPER + ALT + code:" .. kc)
end
