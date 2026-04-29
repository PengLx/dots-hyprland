#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.2"]
# ///
"""Gmail triage MCP server.

Exposes:
  - prompt: triage_email(email)  — system prompt loaded from
    ~/.config/quickshell-gmail/notify-rules.md, with the email metadata
    embedded.
  - tool:   notify_user(title, body, code_to_copy?)  — fires a desktop
    notification via notify-send. If code_to_copy is set, also copies it
    to the clipboard with wl-copy and adds a prominent body.

Designed to be invoked by `claude -p --mcp-config <this server's config>`
from the watcher loop.
"""
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP


RULES_FILE = Path.home() / ".config" / "quickshell-gmail" / "notify-rules.md"
ICON_FILE = Path(__file__).resolve().parent / "icon.svg"

mcp = FastMCP("gmail-triage")


def load_rules() -> str:
    """Read the user's preferences file. Falls back to a minimal default."""
    if RULES_FILE.exists():
        return RULES_FILE.read_text(encoding="utf-8")
    return (
        "# 默认规则(用户未自定义)\n"
        "## 通知:验证码/OTP、银行交易异常、紧急工作邮件、物流取件码\n"
        "## 不通知:广告、newsletter、GitHub 自动通知\n"
    )


@mcp.prompt()
def triage_email(email: str) -> str:
    """构造一封邮件的 triage 系统提示。

    Parameters
    ----------
    email : str
        Email metadata as a JSON string with fields: from, subject, date,
        snippet (and optionally body_text). The watcher fills this in.

    Returns
    -------
    str
        The full prompt text (acts as both system + user message in
        Claude Code's slash-command flow).
    """
    rules = load_rules()
    return f"""你是一个个人 Gmail 三角分流(triage)助手。
你的工作是为下面这封邮件做出**单一决定**:是否需要桌面通知打扰用户。

## 用户偏好规则
{rules}

## 决策流程
1. 仔细读邮件元数据(From / Subject / Snippet)。
2. 对照上面的偏好规则判断。
3. 如果决定通知 → 调用 `notify_user` 工具,参数:
   - `title`: 简短中文(< 30 字)
   - `body`: 1-2 行,包含关键信息和发件人
   - `code_to_copy`: 提取的验证码 / OTP / 取件码,纯数字字母,没有就留空
4. 如果决定不通知 → 一句话说明理由,不调用工具。

## 重要
- 保持冷静和保守 —— 拿不准时**不**通知。
- 验证码场景一定要把码精确提取到 `code_to_copy`(纯码,不要带其他字)。
- 不要解释你的决策过程,直接调用工具或简短回复。

## 待处理邮件
```json
{email}
```
"""


@mcp.tool()
def notify_user(title: str, body: str, code_to_copy: str = "") -> str:
    """Fire a desktop notification. Returns a confirmation string.

    Parameters
    ----------
    title : str
        Short notification heading.
    body : str
        Notification body (1-2 lines).
    code_to_copy : str, optional
        Verification / OTP / pickup code. If non-empty, copied to the
        Wayland clipboard and the body is augmented with a prominent
        version of the code.
    """
    if not title:
        return "error: title required"

    body_final = body or ""
    if code_to_copy:
        # Make the code very visible — first line of the body.
        body_final = f"<b><span size='x-large'>{code_to_copy}</span></b>\n{body_final}".strip()
        # Auto-copy to clipboard so the user can paste immediately.
        try:
            subprocess.run(
                ["wl-copy", code_to_copy],
                timeout=5,
                check=False,
            )
        except FileNotFoundError:
            # wl-copy missing — non-fatal, just lose the auto-copy.
            print("[triage-mcp] wl-copy not found; skipping clipboard step", file=sys.stderr)

    # Branded Gmail icon (bundled SVG). Falls back to the freedesktop
    # mail-message-new theme icon if the file is missing.
    icon = str(ICON_FILE) if ICON_FILE.exists() else "mail-message-new"
    notify_args = [
        "notify-send",
        "-a", "Gmail",
        "-i", icon,
        "-u", "normal",
        title,
        body_final,
    ]
    try:
        subprocess.run(notify_args, timeout=5, check=False)
    except FileNotFoundError:
        return "error: notify-send not installed"

    return f"notified: {title}" + (f" (code copied: {code_to_copy})" if code_to_copy else "")


if __name__ == "__main__":
    mcp.run()
