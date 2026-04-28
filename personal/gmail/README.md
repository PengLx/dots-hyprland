# Gmail AI triage

Background watcher that polls Gmail for new unread mail, hands each one to
Claude Code (headless) via a small MCP server, and fires desktop
notifications for the ones the AI decides matter to you. The user-editable
`notify-rules.md` is the brain — change what you want notified about by
editing English/Chinese plain text, no code changes needed.

```
                                  ┌──────────── notify-rules.md ────────────┐
                                  │   验证码 / 银行 / 取件码 / 工作紧急      │
                                  └─────────────────┬───────────────────────┘
                                                    │
新邮件 (poll 30s)  ─→  watcher.py  ─→  claude -p  ─→ gmail-triage MCP
                                                    │             │
                                                    │             ├─ prompt: triage_email
                                                    │             └─ tool:   notify_user
                                                    │                          │
                                                    └────────── 决策 ──────────┘
                                                                              │
                                                                              ▼
                                                              notify-send + wl-copy
```

## 一次性 setup

### 1. Gmail API 在 GCP project 上启用

如果你已经为 calendar 配置过 GCP project,直接复用。Google Cloud Console:
- 进 calendar 在用的 project
- APIs & Services → Library → 搜 "Gmail API" → Enable

### 2. OAuth client 复用

Calendar 那个 desktop OAuth client 可以直接给 Gmail 用。最快的办法:

```sh
mkdir -p ~/.config/quickshell-gmail
ln -s ~/.config/quickshell-gcal/oauth_client.json \
      ~/.config/quickshell-gmail/oauth_client.json
chmod 700 ~/.config/quickshell-gmail
```

### 3. Login

```sh
python3 ~/Projects/end4-staging/dots-hyprland/personal/gmail/login.py
```

浏览器弹出 → Google 登录 → 同意 gmail.readonly → 终端打印 "Saved
credentials"。`~/.config/quickshell-gmail/credentials.json` 里就有 refresh
token 了。

### 4. (可选)调整通知偏好

`~/.config/quickshell-gmail/notify-rules.md` 是你写给 AI 看的中文规则文件。
默认副本在 `personal/gmail/notify-rules.md`,login 后**复制一份过去**:

```sh
cp ~/Projects/end4-staging/dots-hyprland/personal/gmail/notify-rules.md \
   ~/.config/quickshell-gmail/notify-rules.md
```

之后任何时候改这个文件,下一次新邮件来时就会按新规则判断,**不需要重启
watcher**。

### 5. 启动 watcher

下次 Hyprland 启动会自动跑(`exec-once` 已加到 `~/.config/hypr/custom/execs.conf`)。
要立刻启动:

```sh
~/.config/hypr/custom/scripts/gmail-watcher.sh &
```

## 文件

| 文件 | 作用 |
|---|---|
| `login.py` | OAuth 流程,refresh token 存到 credentials.json |
| `watcher.py` | 主 daemon,30s 轮询新邮件,逐封 dispatch 给 claude |
| `triage-mcp.py` | MCP server: 暴露 `triage_email` prompt + `notify_user` tool |
| `triage-mcp.json` | claude -p 用的 MCP 配置 |
| `notify-rules.md` | 默认通知偏好(用户拷贝到 ~/.config/quickshell-gmail/) |

## 触发流程

```
poll cycle:
  1. token = refresh access token (cached on disk)
  2. ids = list_messages(q="is:unread newer_than:10m", maxResults=10)
  3. for each id not in seen-set:
       email = fetch metadata + snippet
       claude -p --mcp-config triage-mcp.json --bare \
              --model claude-haiku-4-5 \
              --allowed-tools mcp__gmail-triage__notify_user \
              "/mcp__gmail-triage__triage_email email='<json>'"
       seen.add(id)
  4. sleep 30s
```

注意 watcher **从不**标记邮件为已读。它纯粹是观察者,你所有 Gmail 状态
还是你自己控制。

## 调试

- 日志: `~/.cache/quickshell-gmail/watcher.log`(包含 stdout + stderr)
- 看最近 20 行: `tail -20 ~/.cache/quickshell-gmail/watcher.log`
- AI 的 reasoning(没决定通知时):前段是 claude -p stdout,会进 watcher.log

要**手动测一封 email**(不通过轮询):

```sh
echo '{"from":"security@stripe.com","subject":"Stripe 验证码: 638251","date":"now","snippet":"Your Stripe verification code is 638251. It expires in 10 minutes.","label_ids":["UNREAD"]}' \
| jq -c | xargs -I {} bash -c '
  claude -p --mcp-config ~/Projects/end4-staging/dots-hyprland/personal/gmail/triage-mcp.json \
    --bare --model claude-haiku-4-5 \
    --allowed-tools mcp__gmail-triage__notify_user \
    "/mcp__gmail-triage__triage_email email='\''{}'\''"
'
```

应该弹一条「Stripe 验证码 / 638251」桌面通知,且剪贴板里是 638251。

## 重新授权 / 换账号

```sh
rm ~/.config/quickshell-gmail/credentials.json ~/.config/quickshell-gmail/.access_token.json
python3 ~/Projects/end4-staging/dots-hyprland/personal/gmail/login.py
```

如果 Google 不再下发 refresh_token,先去
https://myaccount.google.com/permissions 把这个 OAuth app 撤销,再 login。

## 关掉

- 临时:`pkill -f gmail-watcher.sh; pkill -f gmail/watcher.py`
- 永久:从 `~/.config/hypr/custom/execs.conf` 删那行 `exec-once`
