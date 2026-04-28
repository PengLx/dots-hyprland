# 我的 Hyprland / Fairy 自定义清单

本文件记录所有偏离 end4 默认的修改 + 怎么调。
按 `要改 X → 改文件 Y → 跑命令 Z` 组织。

---

## 显示器 / 缩放 / 刷新率

- **改文件**: `~/.config/hypr/monitors.conf`
- 现在配置:`monitor = DP-4, 3840x2160@160, 0x0, 1.5`(4K 160Hz, 1.5x 缩放)+ `HDMI-A-2, disable`
- **改完生效**: `hyprctl reload`
- 想换 GUI: `nwg-displays`

---

## 工作区布局(scrolling / dwindle / master / hy3)

- **改文件**: `~/.config/hypr/custom/scripts/layout-per-workspace.sh` 里的 `LAYOUT_FOR_WS` 数组
- 当前: WS 1/2/3 = scrolling, WS 8 = hy3, WS 9 = master, 其他 dwindle
- **改完生效**: `pkill -9 -f layout-per-workspace.sh; nohup ~/.config/hypr/custom/scripts/layout-per-workspace.sh >/dev/null 2>&1 &`
- hy3 专属键位(Super+Alt+H/V/W/E/Tab)是脚本动态加/卸的,只在 hy3 工作区生效
- **加 hy3 键位**: 改脚本里的 `HY3_BINDS` 数组

---

## Super+/ 快捷键表中文化

- **改文件**: `~/.config/hypr/translate-keybinds.sh`(这个**是我们自己写的脚本**,不是 end4 自带)
- **怎么用**: 直接跑 `~/.config/hypr/translate-keybinds.sh`,会备份+翻译 `hyprland/keybinds.conf` 和 `custom/keybinds.conf`
- **加新翻译**: 在脚本里照葫芦画瓢加 sed 行
- ⚠️ **end4 升级警告**: `setup exp-update` 会把 `hyprland/keybinds.conf` 还原成英文,**升级后再跑一次脚本**

---

## fcitx5 候选框配色(跟壁纸自动同步)

- **改文件**(改色键): `~/.config/matugen/templates/fcitx5/theme.conf`
- 现在用 `primary_container` (深色调,不会很粉);可改成 `primary` / `secondary` / `tertiary`
- **改完生效**: `matugen image $(cat ~/.local/state/quickshell/user/generated/wallpaper/path.txt) --prefer darkness && pkill -9 fcitx5 && fcitx5 -d &`
- **整套停用**: `~/.config/fcitx5/conf/classicui.conf` 把 `Theme=fairy` 改成 `Theme=default-dark` 等固定主题

---

## Fairy(Claude Code 侧栏 + 语音)

### 入口
- **召唤**: `Super+,`
- **语音输入(PTT)**: 按住 `Super+\``,松开自动 STT + 注入 + TTS

### 改启动行为
- **文件**: `~/.config/hypr/custom/execs.conf`(找到 `kitty --app-id=claude-sidebar` 那行)
- 加 / 改 claude 启动参数:`--name fairy`、`--dangerously-skip-permissions`、`--channels plugin:telegram@claude-plugins-official` 等
- **改完生效**: `pkill -f 'kitty.*claude-sidebar'`,sidebar 自动重生成(workspace rule `on-created-empty` 会拉起新的)

### 改 sidebar 尺寸 / 位置 / 圆角
- **文件**: `~/.config/hypr/custom/rules.conf` 里 `claude-sidebar` 那几条 windowrule
- `size (monitor_w*0.32) (monitor_h*0.92)` — 改 0.32 / 0.92 调宽高占比
- `move 12 50` — 调左上角偏移
- `rounding 14` — 圆角

### 改 TTS(MiniMax 音色 / 模型)
- **文件**: `~/.config/claude-tts/.env`
- `MINIMAX_VOICE_ID` — 你的克隆音色是 `fairy_voice_2026`
- `MINIMAX_SPEED` — 1.0 默认,0.8 慢一点,1.2 快
- 列出所有音色: `curl -s "https://api.minimax.io/v1/get_voice" -H "Authorization: Bearer $MINIMAX_API_KEY" -d '{"voice_type":"all"}' | jq`

### 改 TTS 音量
- **文件**: `~/.claude/hooks/lib-tts.sh` 最底下 mpv 那行 `--volume=145 --volume-max=150`

### 改 TTS 触发条件
- **Notification 范围**(idle 提示):`~/.claude/hooks/notify-tts.sh`,可在里面加更多 `case` 过滤
- **每次回复都念**(语音输入触发的):`~/.claude/hooks/stop-tts.sh` — 检查 `/tmp/fairy-voice-pending` 标记
- **关掉某条 hook**: 改 `~/.claude/settings.json` 的 `hooks` 字段

### 改 PTT 键
- **文件**: `~/.config/hypr/custom/keybinds.conf`,搜 `voice-input.sh` 改 `Super, grave` 为别的

### Telegram channel 配对
- **配对**: 在 sidebar 里 `/telegram:access pair <code>` 然后 `/telegram:access policy allowlist`
- **关掉**: 改 sidebar 启动命令去掉 `--channels` 那段

### Obsidian MCP(只 fairy 启用)
- Obsidian 插件: **Local REST API** (Adam Coddington), API key 写在 `~/.config/obsidian-mcp/.env`
- MCP server: `uvx mcp-obsidian`(MarkusPfundstein/mcp-obsidian)
- fairy 启动通过 `~/.config/hypr/custom/scripts/fairy-launch.sh` 包装,脚本会 source `.env`,生成 `~/.claude/fairy-mcp.runtime.json`(把 key 注入),用 `--mcp-config` 给 claude
- vault 路径 `/mnt/data/ObsidianData`(NTFS),syncthing 同步到手机
- **所有 Obsidian 命令面板里的命令** fairy 都能通过 `mcp__obsidian__execute_command` 触发(包括其它插件注册的命令)
- 想关:删 `~/.config/obsidian-mcp/.env` 里的 OBSIDIAN_API_KEY,wrapper 检测到空就不挂 MCP

### claude-mem(只 fairy 启用,不污染主 session)
- 用户设置 `~/.claude/settings.json` 里 `"claude-mem@thedotmack": false`(全局默认关)
- fairy 专属 `~/.claude/fairy-extra-settings.json` 里 `"claude-mem@thedotmack": true`
- fairy 启动加 `--settings ~/.claude/fairy-extra-settings.json` 来 override
- 数据存 `~/.claude-mem/`(SQLite + ChromaDB),Web UI `http://localhost:37777`
- 想给所有 session 启用:把主 settings.json 改回 true,删掉 fairy-extra(简单)
- 想完全卸:`/plugin uninstall claude-mem@thedotmack`,然后 `rm -rf ~/.claude-mem/`

---

## 音频(FIIO KA17 HiRes)

- **改文件**: `~/.config/pipewire/pipewire.conf.d/10-hires-rates.conf`
- 当前支持采样率: 44.1 / 48 / 88.2 / 96 / 176.4 / 192 kHz
- 加更高(384/768)**不建议**,大多数源文件不超过 192
- **改完生效**: `systemctl --user restart pipewire pipewire-pulse wireplumber`
- **验证当前播放采样率**: `pactl list sinks | grep -A2 KA17 | grep "Sample Spec"`

---

## Greeter(cage + regreet)

- **改文件**: `/etc/greetd/regreet.toml`(需 sudo)
- 主题、字体、壁纸、问候语、时钟格式都在这
- 壁纸文件: `/usr/share/backgrounds/regreet-bg.jpg`(必须 root 可读路径,不能用 ~/Pictures)
- **改完生效**: 注销重登(下次 greeter 弹出时刷新)

---

## 输入法 / fcitx5

- **改文件**: `~/.config/hypr/custom/env.conf` 里 fcitx5 环境变量
- 配置文件: `~/.config/fcitx5/`
- **改完生效**: `pkill fcitx5 && fcitx5 -d &`,然后注销重登(让环境变量进新会话)

---

## 终端(kitty)

- **改文件**: `~/.config/kitty/kitty.conf`
- shell 已改 `zsh`(end4 默认 fish)
- 颜色 = matugen 动态生成(随壁纸变);要改回 Catppuccin 注释掉第 2 行 `include`

---

## 隐藏会话条目(plasma / hyprland-uwsm)

- **改文件**: `/usr/share/wayland-sessions/<name>.desktop`,加 `NoDisplay=true`
- ⚠️ 系统升级会覆盖,需要手动重加

---

## 设置面板「保存当前壁纸」按钮

- **改文件**: `~/.config/quickshell/ii/modules/settings/QuickConfig.qml`(在「Choose file」按钮和深/浅色按钮之间插入了 `RippleButtonWithIcon` materialIcon=`bookmark_add`)
- **逻辑脚本**: `~/.config/hypr/custom/scripts/save-current-wallpaper.sh`(读 `illogical-impulse/config.json` 的 `wallpaperPath`,带时间戳复制到 `~/Pictures/Wallpapers/saved/`)
- **目的**: 随机壁纸都覆盖到 `~/Pictures/Wallpapers/random_wallpaper.<ext>` 同一文件,这个按钮把当前喜欢的壁纸永久留下来
- ⚠️ **end4 升级警告**: QuickConfig.qml 在 end4 更新区域,`setup exp-update` 会还原。升级后需要重新加这个按钮(脚本本身在 `custom/` 不会丢)

---

## 备份位置

- **配置整包备份**: `~/Backup/desktop-cleanup-2026-04-27.tar.gz`(end4 安装前的旧 mac 风格 + niri config)
- **每次跑 translate-keybinds.sh**: 自动留 `*.conf.bak-<timestamp>` 在原目录

---

## 想从零理解 fairy 工作流

1. 系统启动 → Hyprland 自动 exec-once 启动 kitty + claude (`--name fairy`),藏在 `special:claude` 工作区
2. Claude Code 加载 hooks (`~/.claude/settings.json` → `Notification` + `Stop` hook)
3. Telegram channel plugin 启动,bun 子进程跑起来
4. 用户按 `Super+,` 召唤侧栏
5. 用户按住 `Super+\`` 录音 → 松开 → Google STT → 文本通过 kitty remote-control 注入 fairy → claude 处理 → 回复 → Stop hook 看到 pending 标记 → MiniMax TTS → mpv 播
6. 平时 fairy 后台运行,Notification 事件触发(空闲时)→ TTS(若侧栏不可见)

---

*末次编辑: 2026-04-29*
