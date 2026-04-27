pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Google Calendar event source.
 *
 * Reads `~/.local/state/quickshell/user/gcal_events.json` (produced by
 * personal/gcal/sync.py) and exposes:
 *   - `events`           — full sorted array of normalized events
 *   - `calendars`        — list of seen calendars with metadata
 *   - `syncedAt`, `lastError`
 *   - `eventsByDate(d)`  — returns events that overlap a given JS Date's
 *                          local day (handy for the day list under the
 *                          calendar grid)
 *   - `holidayForDate(d)`— first holiday-flagged event on a given date
 *                          (used to color the day cell)
 *   - `refresh()`        — runs sync.py via `python3 ~/.config/quickshell-gcal/sync.py`
 *                          (or the path packaged with this dotfiles repo)
 *
 * Sync runs once at startup and every 5 minutes thereafter. If
 * `~/.config/quickshell-gcal/credentials.json` doesn't exist (login.py
 * never run), the singleton stays inert — `events` is just [].
 */
Singleton {
    id: root

    readonly property string statePath: FileUtils.trimFileProtocol(`${Directories.state}/user/gcal_events.json`)
    readonly property string credentialsPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell-gcal/credentials.json`)
    readonly property string syncScript: FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/gcal/sync.py`)

    property var events: []
    property var calendars: []
    property string syncedAt: ""
    property string lastError: ""
    property bool refreshing: false

    function _pad(n) { return n < 10 ? "0" + n : "" + n }
    function _ymd(d) {
        return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate())
    }

    // True when `iso` (any of YYYY-MM-DD or full RFC3339) overlaps the
    // local-day window for `dateObj`.
    function _eventOverlapsDay(ev, dateObj) {
        const target = _ymd(dateObj)
        const startStr = ev.start || ""
        const endStr = ev.end || ""
        if (!startStr) return false

        if (ev.all_day) {
            // start = "YYYY-MM-DD"; end = exclusive next-day "YYYY-MM-DD"
            // event covers [start, end). target in [start, end - 1d]
            if (!endStr) return startStr === target
            return startStr <= target && target < endStr
        }

        // Timed event: compare against [start, end] in local time
        const s = new Date(startStr)
        const e = endStr ? new Date(endStr) : s
        const dayStart = new Date(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate(), 0, 0, 0, 0)
        const dayEnd = new Date(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate(), 23, 59, 59, 999)
        return s <= dayEnd && e >= dayStart
    }

    function eventsByDate(dateObj) {
        if (!dateObj) return []
        return root.events.filter(function(ev) { return _eventOverlapsDay(ev, dateObj) })
    }

    function holidayForDate(dateObj) {
        const matches = root.eventsByDate(dateObj)
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].is_holiday) return matches[i]
        }
        return null
    }

    function refresh() {
        if (root.refreshing) return
        root.refreshing = true
        syncProc.command = ["python3", root.syncScript]
        syncProc.running = true
    }

    Process {
        id: syncProc
        running: false
        stdout: SplitParser { onRead: (line) => console.log("[GCal/sync]", line) }
        stderr: SplitParser { onRead: (line) => console.warn("[GCal/sync]", line) }
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

    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.statePath)
        watchChanges: true
        onFileChanged: stateFile.reload()
        onLoaded: {
            try {
                const data = JSON.parse(stateFile.text() || "{}")
                root.events = data.events || []
                root.calendars = data.calendars || []
                root.syncedAt = data.synced_at || ""
                console.log("[GCal] loaded", root.events.length, "events")
            } catch (e) {
                console.warn("[GCal] failed to parse state:", e)
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[GCal] no cached state yet — refresh() will create it")
            } else {
                console.warn("[GCal] state load error:", error)
            }
        }
    }

    // Probe credentials file to decide whether to start polling at all.
    // watchChanges lets us pick up `login.py` running for the first time
    // without needing a quickshell restart.
    FileView {
        id: credsProbe
        path: Qt.resolvedUrl(root.credentialsPath)
        watchChanges: true
        onFileChanged: credsProbe.reload()
        onLoaded: {
            console.log("[GCal] credentials present, scheduling sync")
            stateFile.reload()
            root.refresh()
        }
        onLoadFailed: () => {
            console.log("[GCal] credentials missing — run personal/gcal/login.py")
        }
    }

    Component.onCompleted: {
        credsProbe.reload()
    }

    // Poll every 5 minutes; only fires when credentials exist (refresh()
    // is a no-op without a credentials file because sync.py would error,
    // but the syncProc still spends a process — so gate on syncedAt
    // having been populated at least once).
    Timer {
        interval: 5 * 60 * 1000
        running: root.syncedAt.length > 0
        repeat: true
        onTriggered: root.refresh()
    }
}
