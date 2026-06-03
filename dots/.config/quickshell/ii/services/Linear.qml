pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Linear data source.
 *
 * Reads `~/.local/state/quickshell/user/linear_data.json` (produced by
 * personal/linear/sync.py) and exposes:
 *   - `viewer`         — current Linear user
 *   - `teams`          — viewer's teams (with workflow states + active cycle)
 *   - `myIssues`       — assigned-to-me active issues
 *   - `cycleIssues`    — issues across all active cycles (filter by team for kanban)
 *   - `projects`       — viewer's projects (member or lead)
 *   - `notifications`  — recent notifications
 *   - `syncedAt`, `lastError`
 *
 * Mutations (issueCreate / issueUpdate) shell out to mutate.py and force a
 * refresh on exit.
 *
 * Inert when ~/.config/quickshell-linear/api_key doesn't exist.
 */
Singleton {
    id: root

    readonly property string statePath: FileUtils.trimFileProtocol(`${Directories.state}/user/linear_data.json`)
    readonly property string keyPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell-linear/api_key`)
    readonly property string syncScript: FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/linear/sync.py`)
    readonly property string mutateScript: FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/linear/mutate.py`)

    property var viewer: ({})
    property var teams: []
    property var myIssues: []
    property var cycleIssues: []
    property var projects: []
    property var notifications: []
    property string syncedAt: ""
    property string lastError: ""
    property bool refreshing: false
    property bool credentialsPresent: false

    // Group cycleIssues by team's active cycle for the kanban view. Each entry
    // returns { team, cycle, byStateType: { backlog: [], unstarted: [],
    // started: [], completed: [], cancelled: [], triage: [] } }
    function cycleBoardForTeam(teamId) {
        const team = root.teams.find(t => t.id === teamId)
        if (!team || !team.active_cycle) return null
        const cycleId = team.active_cycle.id
        const issues = root.cycleIssues.filter(i =>
            i.team && i.team.id === teamId && i.cycle && i.cycle.id === cycleId
        )
        const byStateType = { backlog: [], unstarted: [], started: [], completed: [], cancelled: [], triage: [] }
        for (var i = 0; i < issues.length; i++) {
            const t = (issues[i].state && issues[i].state.type) || "unstarted"
            if (byStateType[t]) byStateType[t].push(issues[i])
            else byStateType.unstarted.push(issues[i])
        }
        // Sort each column by priority (1=urgent first, 0=none last) then updatedAt desc
        const prioOrder = (p) => p === 0 ? 5 : p
        for (var k in byStateType) {
            byStateType[k].sort(function(a, b) {
                const pa = prioOrder(a.priority || 0)
                const pb = prioOrder(b.priority || 0)
                if (pa !== pb) return pa - pb
                return (b.updated_at || "").localeCompare(a.updated_at || "")
            })
        }
        return { team: team, cycle: team.active_cycle, byStateType: byStateType }
    }

    // Teams that have an active cycle (the only ones useful for kanban)
    function teamsWithActiveCycle() {
        return root.teams.filter(t => t.active_cycle && t.active_cycle.id)
    }

    function refresh() {
        if (root.refreshing) return
        if (!root.credentialsPresent) return
        root.refreshing = true
        syncProc.command = ["python3", root.syncScript]
        syncProc.running = true
    }

    // Create a new issue. body = { teamId, title, description?, priority?, stateId? }
    function createIssue(body) {
        if (!body || !body.teamId || !body.title) return
        mutateProc.environment.LINEAR_OP = "create"
        mutateProc.environment.LINEAR_BODY = JSON.stringify(body)
        mutateProc.command = ["python3", root.mutateScript]
        mutateProc.running = true
    }

    // Move an issue to a different workflow state.
    function setIssueState(issueId, stateId) {
        if (!issueId || !stateId) return
        mutateProc.environment.LINEAR_OP = "set_state"
        mutateProc.environment.LINEAR_ISSUE_ID = issueId
        mutateProc.environment.LINEAR_STATE_ID = stateId
        mutateProc.command = ["python3", root.mutateScript]
        mutateProc.running = true
    }

    Process {
        id: syncProc
        running: false
        stdout: SplitParser { onRead: (line) => console.log("[Linear/sync]", line) }
        stderr: SplitParser { onRead: (line) => console.warn("[Linear/sync]", line) }
        onExited: (exitCode, _) => {
            root.refreshing = false
            if (exitCode === 0) {
                root.lastError = ""
                stateFile.reload()
            } else {
                root.lastError = "sync.py exit " + exitCode
            }
        }
    }

    Process {
        id: mutateProc
        running: false
        stdout: SplitParser { onRead: (line) => console.log("[Linear/mutate]", line) }
        stderr: SplitParser { onRead: (line) => console.warn("[Linear/mutate]", line) }
        onExited: (exitCode, _) => {
            root.refresh()
        }
    }

    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.statePath)
        watchChanges: true
        onFileChanged: stateFile.reload()
        onLoaded: {
            try {
                const data = JSON.parse(stateFile.text() || "{}")
                root.viewer = data.viewer || {}
                root.teams = data.teams || []
                root.myIssues = data.my_issues || []
                root.cycleIssues = data.cycle_issues || []
                root.projects = data.projects || []
                root.notifications = data.notifications || []
                root.syncedAt = data.synced_at || ""
                console.log("[Linear] loaded",
                    root.myIssues.length, "my-issues,",
                    root.cycleIssues.length, "cycle-issues,",
                    root.projects.length, "projects")
            } catch (e) {
                console.warn("[Linear] failed to parse state:", e)
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Linear] no cached state yet — refresh() will create it")
            } else {
                console.warn("[Linear] state load error:", error)
            }
        }
    }

    FileView {
        id: keyProbe
        path: Qt.resolvedUrl(root.keyPath)
        watchChanges: true
        onFileChanged: keyProbe.reload()
        onLoaded: {
            const txt = (keyProbe.text() || "").trim()
            const present = txt.length > 0
            const wasPresent = root.credentialsPresent
            root.credentialsPresent = present
            if (present && !wasPresent) {
                console.log("[Linear] api_key present, scheduling sync")
                stateFile.reload()
                root.refresh()
            }
        }
        onLoadFailed: () => {
            root.credentialsPresent = false
            console.log("[Linear] api_key missing — see personal/linear/README.md")
        }
    }

    Component.onCompleted: {
        keyProbe.reload()
    }

    // Fallback poller: FileView's watchChanges can miss file *creation*
    // for the first-time setup (api_key didn't exist when the FileView was
    // wired up). Re-probe every 10s until we detect the key, then stop.
    Timer {
        interval: 10 * 1000
        running: !root.credentialsPresent
        repeat: true
        onTriggered: keyProbe.reload()
    }

    Timer {
        interval: 5 * 60 * 1000
        running: root.credentialsPresent && root.syncedAt.length > 0
        repeat: true
        onTriggered: root.refresh()
    }
}
