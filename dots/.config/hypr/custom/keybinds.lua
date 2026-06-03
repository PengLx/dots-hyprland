-- 编辑 shell / 用户配置
hl.bind("CTRL + SUPER + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/illogical-impulse/config.json"), { description = "自定义: 编辑 Shell 配置" })
hl.bind("CTRL + SUPER + ALT + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), { description = "自定义: 编辑用户键位" })

-- 切换 Fairy(Claude 侧边栏)
hl.bind("SUPER + comma", hl.dsp.workspace.toggle_special("claude"), { description = "自定义: 切换 Fairy 侧边栏" })

-- Super+Q:Fairy 上隐藏,否则关闭(替换默认 killactive,需先 unbind 否则叠加触发)
hl.unbind("SUPER + Q")
hl.bind("SUPER + Q", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/smart-close.sh"), { description = "自定义: 关闭窗口(Fairy 隐藏)" })

-- Fairy 语音输入 Push-to-talk(按下开始 / 松开停止)
hl.bind("SUPER + grave", hl.dsp.exec_cmd("~/.claude/hooks/voice-input.sh start"), { description = "自定义: Fairy 语音输入(按住说话)" })
hl.bind("SUPER + grave", hl.dsp.exec_cmd("~/.claude/hooks/voice-input.sh stop"), { release = true })
