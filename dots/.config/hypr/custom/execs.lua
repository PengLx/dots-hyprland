-- 开机自启(原 exec-once 放进 hyprland.start 钩子里)
hl.on("hyprland.start", function()
    -- 输入法守护进程
    hl.exec_cmd("fcitx5")

    -- hy3 插件:每次会话需 reload 才能让 hy3 布局可用
    hl.exec_cmd("hyprpm reload -n")

    -- 按工作区切布局的守护脚本 + 动态 hy3 键位(socat 事件循环)
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/layout-per-workspace.sh")

    -- greetd 自动登录后的密码门
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/lock-on-startup.sh")

    -- Fairy(Claude 侧边栏):预载到隐藏的 special 工作区,带 kitty 远控 socket
    hl.exec_cmd("[workspace special:claude silent] kitty --app-id=claude-sidebar --listen-on=unix:/tmp/kitty-fairy.sock -d /home/lican -e /home/lican/.config/hypr/custom/scripts/fairy-launch.sh")

    -- Gmail AI 分诊后台 watcher
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/gmail-watcher.sh")
end)
