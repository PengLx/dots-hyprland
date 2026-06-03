#!/usr/bin/env bash
# Launches Claude Code as Fairy with all extras:
# - sources Obsidian REST API key
# - injects it into the MCP config
# - exec claude
# This wrapper exists because Hyprland exec-once can't source env files inline.
set -u

# Hyprland exec-once inherits a minimal PATH (no ~/.local/bin), so claude is not found.
export PATH="$HOME/.local/bin:$PATH"

ENV_FILE="$HOME/.config/obsidian-mcp/.env"
MCP_TEMPLATE="$HOME/.claude/fairy-mcp.json"
MCP_RUNTIME="$HOME/.claude/fairy-mcp.runtime.json"

# Pull the key from the local env file and bake it into a runtime mcp config
# (Claude Code's --mcp-config doesn't expand env vars in the JSON — has to be literal).
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi

if [ -n "${OBSIDIAN_API_KEY:-}" ]; then
  jq --arg key "$OBSIDIAN_API_KEY" \
     --arg host "${OBSIDIAN_HOST:-127.0.0.1}" \
     '.mcpServers.obsidian.env.OBSIDIAN_API_KEY = $key
      | .mcpServers.obsidian.env.OBSIDIAN_HOST = $host' \
     "$MCP_TEMPLATE" > "$MCP_RUNTIME"
  chmod 600 "$MCP_RUNTIME"
  EXTRA_ARGS=(--mcp-config "$MCP_RUNTIME")
else
  # Key not configured yet — launch without obsidian MCP.
  EXTRA_ARGS=()
fi

exec claude \
  --name fairy \
  --dangerously-skip-permissions \
  --channels plugin:telegram@claude-plugins-official \
  --settings "$HOME/.claude/fairy-extra-settings.json" \
  "${EXTRA_ARGS[@]}"
