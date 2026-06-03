# Personal overlay

User-only files that end4's `./setup install-files` does NOT manage.
Run `./personal/install.sh` after fresh install or after pulling updates.

Layout mirrors `$HOME`:

- `.config/fcitx5/conf/classicui.conf`     — fcitx5 theme = `fairy` (matugen-driven)
- `.config/pipewire/pipewire.conf.d/`      — FIIO KA17 hi-res rate config
- `.config/hypr/translate-keybinds.sh`     — sed-based Chinese cheatsheet translator
- `.config/hypr/_example.monitors.conf`    — reference, copy to `custom/monitors.conf`
- `.claude/hooks/*.sh`                     — Fairy TTS hooks
- `.claude/settings.json`                  — Claude Code hook registration
- `.claude/fairy-mcp.json`                 — Fairy MCP config template (runtime is gitignored)
- `.claude/fairy-extra-settings.json`      — Fairy extra Claude Code settings

Secrets (gitignored — recreate manually):
- `~/.config/todoist_token`
- `~/.config/claude-tts/.env`
- `~/.config/obsidian-mcp/.env`
