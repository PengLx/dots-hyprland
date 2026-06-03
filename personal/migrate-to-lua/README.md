# Hyprland .conf → Lua migration (2026-06)

Switches the live config to the `lican-on-upstream` branch: upstream end-4 + all
fork customizations re-applied, and Hyprland's config moved from `.conf` to the
native Lua schema (Hyprland 0.55+).

## Run
```bash
bash personal/migrate-to-lua/cutover.sh      # installs + verifies, no restart
hyprctl dispatch exit                         # ONE restart to apply (ends session)
```
Cutover backs up `~/.config/{hypr,quickshell,matugen,fontconfig}` to
`~/.config/_premigration-backup-<ts>`, installs the branch, writes machine-local
`monitors.lua` (DP-4 4K@160 1.5x, HDMI off), renames `hyprland.conf`→`.conf.old`,
and runs `Hyprland --verify-config` (auto-rolls-back hypr on failure).

## Rollback (from a TTY if the restart misbehaves)
```bash
bash personal/migrate-to-lua/rollback.sh && hyprctl dispatch exit
```

## Validated before shipping
- `luac -p` on every overlay
- stub-`hl` execution of the whole config (no runtime Lua errors)
- `Hyprland --verify-config` => `config ok` (real parser), incl. a negative control
- full cutover dry-run against a temp HOME => `config ok`

## Not auto-ported (by design)
- Chinese cheatsheet descriptions for *upstream* keybinds (custom binds are already
  zh). The old `translate-keybinds.sh` targeted `.conf`; re-point it at the new
  `hyprland/keybinds.lua` `description = "..."` strings if wanted.
- `layout-per-workspace.sh` stays an external socat daemon (works as-is on 0.55).
