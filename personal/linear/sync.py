#!/usr/bin/env python3
"""Pull Linear state into a single JSON cache for the quickshell sidebar.

Reads the user's Personal API key from ~/.config/quickshell-linear/api_key,
issues one big GraphQL query (multiple top-level fields) covering:
  - viewer
  - teams (+ workflow states + active cycle)
  - issues assigned to viewer (active states only)
  - issues in any active cycle (for the kanban view)
  - projects where viewer is member or lead
  - viewer's notifications

Writes ~/.local/state/quickshell/user/linear_data.json (atomic replace),
which the QML Linear singleton watches.

Re-runnable on a timer; cheap when nothing changed.
"""
import datetime as dt
import json
import os
import sys
import urllib.request
from pathlib import Path

KEY_FILE = Path.home() / ".config" / "quickshell-linear" / "api_key"
STATE_DIR = Path.home() / ".local" / "state" / "quickshell" / "user"
OUT_FILE = STATE_DIR / "linear_data.json"
ENDPOINT = "https://api.linear.app/graphql"

QUERY = """
query SyncEverything {
  viewer {
    id name email displayName avatarUrl url
  }
  teams(first: 50) {
    nodes {
      id key name color icon description
      states { nodes { id name color type position } }
      activeCycle { id number name startsAt endsAt progress }
    }
  }
  myIssues: issues(
    filter: {
      assignee: { isMe: { eq: true } }
      state: { type: { in: ["unstarted", "started", "backlog", "triage"] } }
    }
    first: 100
    orderBy: updatedAt
  ) {
    nodes {
      id identifier title url priority priorityLabel
      dueDate createdAt updatedAt
      state { id name color type }
      team { id key name }
      project { id name color }
      cycle { id number }
      labels { nodes { id name color } }
      assignee { id name }
    }
  }
  cycleIssues: issues(
    filter: {
      cycle: { isActive: { eq: true } }
    }
    first: 200
    orderBy: updatedAt
  ) {
    nodes {
      id identifier title url priority priorityLabel
      dueDate updatedAt
      state { id name color type position }
      team { id key name }
      project { id name color }
      cycle { id number }
      assignee { id name avatarUrl }
    }
  }
  projects(
    filter: {
      or: [
        { members: { isMe: { eq: true } } }
        { lead: { isMe: { eq: true } } }
      ]
    }
    first: 30
    orderBy: updatedAt
  ) {
    nodes {
      id name description color icon
      progress state url
      startDate targetDate
      lead { id name avatarUrl }
      teams { nodes { id key name } }
      projectMilestones { nodes { id name targetDate } }
    }
  }
  notifications(first: 40) {
    nodes {
      id type readAt createdAt
      actor { id name avatarUrl }
      ... on IssueNotification {
        issue {
          id identifier title url
          state { name color type }
        }
        comment { id body }
      }
    }
  }
}
"""


def read_key() -> str:
    if not KEY_FILE.exists():
        sys.exit(f"Missing {KEY_FILE}. See personal/linear/README.md.")
    key = KEY_FILE.read_text().strip()
    if not key:
        sys.exit(f"{KEY_FILE} is empty.")
    return key


def graphql(key: str, query: str, variables: dict | None = None) -> dict:
    body = json.dumps({"query": query, "variables": variables or {}}).encode()
    req = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": key,  # PAT — no Bearer prefix
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read())
    if "errors" in payload:
        raise RuntimeError(f"GraphQL errors: {payload['errors']}")
    return payload["data"]


def normalize_issue(it: dict) -> dict:
    return {
        "id": it.get("id"),
        "identifier": it.get("identifier"),
        "title": it.get("title"),
        "url": it.get("url"),
        "priority": it.get("priority", 0),
        "priority_label": it.get("priorityLabel", ""),
        "due_date": it.get("dueDate"),
        "created_at": it.get("createdAt"),
        "updated_at": it.get("updatedAt"),
        "state": (it.get("state") or {}),
        "team": (it.get("team") or {}),
        "project": (it.get("project") or {}),
        "cycle": (it.get("cycle") or {}),
        "labels": [
            {"id": l.get("id"), "name": l.get("name"), "color": l.get("color")}
            for l in (it.get("labels") or {}).get("nodes", [])
        ],
        "assignee": (it.get("assignee") or {}),
    }


def normalize_team(t: dict) -> dict:
    states = (t.get("states") or {}).get("nodes", [])
    states_sorted = sorted(states, key=lambda s: s.get("position", 0))
    return {
        "id": t.get("id"),
        "key": t.get("key"),
        "name": t.get("name"),
        "color": t.get("color"),
        "icon": t.get("icon"),
        "description": t.get("description"),
        "states": states_sorted,
        "active_cycle": t.get("activeCycle"),
    }


def normalize_project(p: dict) -> dict:
    teams = (p.get("teams") or {}).get("nodes", [])
    milestones = (p.get("projectMilestones") or {}).get("nodes", [])
    return {
        "id": p.get("id"),
        "name": p.get("name"),
        "description": p.get("description"),
        "color": p.get("color"),
        "icon": p.get("icon"),
        "progress": p.get("progress", 0),
        "state": p.get("state"),
        "url": p.get("url"),
        "start_date": p.get("startDate"),
        "target_date": p.get("targetDate"),
        "lead": p.get("lead") or {},
        "teams": [{"id": t.get("id"), "key": t.get("key"), "name": t.get("name")} for t in teams],
        "milestones": [
            {"id": m.get("id"), "name": m.get("name"), "target_date": m.get("targetDate")}
            for m in milestones
        ],
    }


def normalize_notification(n: dict) -> dict:
    return {
        "id": n.get("id"),
        "type": n.get("type"),
        "read_at": n.get("readAt"),
        "created_at": n.get("createdAt"),
        "actor": n.get("actor") or {},
        "issue": n.get("issue") or {},
        "comment": n.get("comment") or {},
    }


def main():
    key = read_key()
    data = graphql(key, QUERY)

    teams = [normalize_team(t) for t in (data.get("teams") or {}).get("nodes", [])]
    my_issues = [normalize_issue(i) for i in (data.get("myIssues") or {}).get("nodes", [])]
    cycle_issues = [normalize_issue(i) for i in (data.get("cycleIssues") or {}).get("nodes", [])]
    projects = [normalize_project(p) for p in (data.get("projects") or {}).get("nodes", [])]
    notifications = [normalize_notification(n) for n in (data.get("notifications") or {}).get("nodes", [])]

    payload = {
        "synced_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "viewer": data.get("viewer") or {},
        "teams": teams,
        "my_issues": my_issues,
        "cycle_issues": cycle_issues,
        "projects": projects,
        "notifications": notifications,
    }

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False))
    tmp.replace(OUT_FILE)
    print(
        f"[linear-sync] wrote {len(my_issues)} my-issues, "
        f"{len(cycle_issues)} cycle-issues, "
        f"{len(projects)} projects, "
        f"{len(notifications)} notifications, "
        f"{len(teams)} teams to {OUT_FILE}"
    )


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:400]
        except Exception:
            pass
        sys.exit(f"[linear-sync] HTTP {e.code} {e.reason}: {body}")
    except Exception as e:
        sys.exit(f"[linear-sync] {e}")
