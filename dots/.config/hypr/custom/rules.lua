-- Fairy(Claude 侧边栏)—— VSCode 风格左侧面板
hl.window_rule({ match = { class = "^(claude-sidebar)$" }, float = true })
hl.window_rule({ match = { class = "^(claude-sidebar)$" }, size = {"(monitor_w*0.32)", "(monitor_h*0.92)"} })
hl.window_rule({ match = { class = "^(claude-sidebar)$" }, move = {12, 50} })
hl.window_rule({ match = { class = "^(claude-sidebar)$" }, rounding = 14 })

-- special:claude 工作区被清空时(claude 退出)自动重生 Fairy
hl.workspace_rule({
    workspace = "special:claude",
    on_created_empty = "exec [workspace special:claude silent] kitty --app-id=claude-sidebar --listen-on=unix:/tmp/kitty-fairy.sock -d /home/lican -e /home/lican/.config/hypr/custom/scripts/fairy-launch.sh",
})
