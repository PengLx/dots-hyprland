#!/usr/bin/env python3
"""Mutate Linear via GraphQL. Driven entirely by env vars so QML's Process
can call us without quoting headaches.

Operations
----------
LINEAR_OP=create
    LINEAR_BODY = JSON: {teamId, title, description?, priority?, stateId?,
                         assigneeId?, projectId?, cycleId?, dueDate?,
                         labelIds?: [..]}
    Runs `issueCreate(input: $input)` and prints the new issue identifier.

LINEAR_OP=set_state
    LINEAR_ISSUE_ID, LINEAR_STATE_ID
    Runs `issueUpdate(id: $id, input: { stateId: $stateId })`.

Reads the PAT from ~/.config/quickshell-linear/api_key.
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

KEY_FILE = Path.home() / ".config" / "quickshell-linear" / "api_key"
ENDPOINT = "https://api.linear.app/graphql"


def read_key() -> str:
    if not KEY_FILE.exists():
        sys.exit(f"Missing {KEY_FILE}. See personal/linear/README.md.")
    key = KEY_FILE.read_text().strip()
    if not key:
        sys.exit(f"{KEY_FILE} is empty.")
    return key


def graphql(key: str, query: str, variables: dict) -> dict:
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": key,
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read())
    if "errors" in payload:
        raise RuntimeError(f"GraphQL errors: {payload['errors']}")
    return payload["data"]


CREATE_MUT = """
mutation IssueCreate($input: IssueCreateInput!) {
  issueCreate(input: $input) {
    success
    issue { id identifier title url }
  }
}
"""

SET_STATE_MUT = """
mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
  issueUpdate(id: $id, input: $input) {
    success
    issue { id identifier state { id name type } }
  }
}
"""


def op_create(key: str) -> None:
    raw = os.environ.get("LINEAR_BODY", "")
    if not raw:
        sys.exit("LINEAR_OP=create needs LINEAR_BODY env var (JSON).")
    body = json.loads(raw)
    if "teamId" not in body or "title" not in body:
        sys.exit("LINEAR_BODY must include teamId and title.")
    # Translate snake-case-ish friendly keys to Linear's input shape if needed.
    input_obj = {
        "teamId": body["teamId"],
        "title": body["title"],
    }
    for k in ("description", "priority", "stateId", "assigneeId",
              "projectId", "cycleId", "dueDate", "labelIds"):
        if k in body and body[k] not in (None, ""):
            input_obj[k] = body[k]
    data = graphql(key, CREATE_MUT, {"input": input_obj})
    res = data.get("issueCreate") or {}
    if not res.get("success"):
        sys.exit(f"issueCreate failed: {res}")
    issue = res.get("issue") or {}
    print(f"[linear-mutate] created {issue.get('identifier')} {issue.get('url')}")


def op_set_state(key: str) -> None:
    issue_id = os.environ.get("LINEAR_ISSUE_ID")
    state_id = os.environ.get("LINEAR_STATE_ID")
    if not issue_id or not state_id:
        sys.exit("LINEAR_OP=set_state needs LINEAR_ISSUE_ID and LINEAR_STATE_ID.")
    data = graphql(key, SET_STATE_MUT, {"id": issue_id, "input": {"stateId": state_id}})
    res = data.get("issueUpdate") or {}
    if not res.get("success"):
        sys.exit(f"issueUpdate failed: {res}")
    issue = res.get("issue") or {}
    state = issue.get("state") or {}
    print(f"[linear-mutate] {issue.get('identifier')} → {state.get('name')}")


def main():
    op = os.environ.get("LINEAR_OP", "")
    key = read_key()
    if op == "create":
        op_create(key)
    elif op == "set_state":
        op_set_state(key)
    else:
        sys.exit(f"Unknown LINEAR_OP={op!r}. Use 'create' or 'set_state'.")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:400]
        except Exception:
            pass
        sys.exit(f"[linear-mutate] HTTP {e.code} {e.reason}: {body}")
    except Exception as e:
        sys.exit(f"[linear-mutate] {e}")
