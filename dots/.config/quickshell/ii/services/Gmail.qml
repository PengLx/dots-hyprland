pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Gmail data source.
 *
 * Reads `~/.local/state/quickshell/user/gmail_data.json` (produced by
 * personal/gmail/sync.py) and exposes the inbox to the QML sidebar.
 *
 * Mutations (mark_read / mark_unread / archive / fetch_body) shell out
 * to mutate.py with env-var arguments. fetch_body returns a path to a
 * cached plain-text body file via `bodyReady(msgId, path)`.
 *
 * Inert when ~/.config/quickshell-gmail/credentials.json doesn't exist.
 */
Singleton {
    id: root

    readonly property string statePath: FileUtils.trimFileProtocol(`${Directories.state}/user/gmail_data.json`)
    readonly property string credsPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell-gmail/credentials.json`)
    readonly property string bodyCacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/quickshell-gmail/bodies`)
    readonly property string syncScript: FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/gmail/sync.py`)
    readonly property string mutateScript: FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/gmail/mutate.py`)

    property var messages: []
    property string syncedAt: ""
    property string lastError: ""
    property bool refreshing: false
    property bool credentialsPresent: false

    // Emitted when fetch_body finishes for `msgId`. The QML detail view
    // listens for this and reads the path to populate its body field.
    signal bodyReady(string msgId, string path)
    signal mutationComplete(string msgId, string op)

    readonly property int unreadCount: {
        var n = 0
        for (var i = 0; i < messages.length; i++) {
            if (messages[i].is_unread) n++
        }
        return n
    }

    function refresh() {
        if (root.refreshing) return
        if (!root.credentialsPresent) return
        root.refreshing = true
        syncProc.command = ["python3", root.syncScript]
        syncProc.running = true
    }

    // Lazy-load the full message body. Result comes via `bodyReady` signal.
    function fetchBody(msgId) {
        if (!msgId) return
        bodyProc.environment.GMAIL_OP = "fetch_body"
        bodyProc.environment.GMAIL_MSG_ID = msgId
        bodyProc.lastMsgId = msgId
        bodyProc.command = ["python3", root.mutateScript]
        bodyProc.running = true
    }

    function markRead(msgId) {
        if (!msgId) return
        modifyProc.environment.GMAIL_OP = "mark_read"
        modifyProc.environment.GMAIL_MSG_ID = msgId
        modifyProc.lastMsgId = msgId
        modifyProc.lastOp = "mark_read"
        modifyProc.command = ["python3", root.mutateScript]
        modifyProc.running = true
    }

    function markUnread(msgId) {
        if (!msgId) return
        modifyProc.environment.GMAIL_OP = "mark_unread"
        modifyProc.environment.GMAIL_MSG_ID = msgId
        modifyProc.lastMsgId = msgId
        modifyProc.lastOp = "mark_unread"
        modifyProc.command = ["python3", root.mutateScript]
        modifyProc.running = true
    }

    function archive(msgId) {
        if (!msgId) return
        modifyProc.environment.GMAIL_OP = "archive"
        modifyProc.environment.GMAIL_MSG_ID = msgId
        modifyProc.lastMsgId = msgId
        modifyProc.lastOp = "archive"
        modifyProc.command = ["python3", root.mutateScript]
        modifyProc.running = true
    }

    Process {
        id: syncProc
        running: false
        stdout: SplitParser { onRead: (line) => console.log("[Gmail/sync]", line) }
        stderr: SplitParser { onRead: (line) => console.warn("[Gmail/sync]", line) }
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
        id: bodyProc
        property string lastMsgId: ""
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                const path = line.trim()
                if (path.length > 0 && bodyProc.lastMsgId.length > 0) {
                    root.bodyReady(bodyProc.lastMsgId, path)
                }
            }
        }
        stderr: SplitParser { onRead: (line) => console.warn("[Gmail/body]", line) }
    }

    Process {
        id: modifyProc
        property string lastMsgId: ""
        property string lastOp: ""
        running: false
        stdout: SplitParser { onRead: (line) => console.log("[Gmail/modify]", line) }
        stderr: SplitParser { onRead: (line) => console.warn("[Gmail/modify]", line) }
        onExited: (exitCode, _) => {
            if (exitCode === 0 && modifyProc.lastMsgId.length > 0) {
                root.mutationComplete(modifyProc.lastMsgId, modifyProc.lastOp)
            }
            // Re-sync so the UI reflects label changes (or the missing
            // archived message) immediately rather than after the 5-min timer.
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
                root.messages = data.messages || []
                root.syncedAt = data.synced_at || ""
                console.log("[Gmail] loaded", root.messages.length, "messages")
            } catch (e) {
                console.warn("[Gmail] failed to parse state:", e)
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Gmail] no cached state yet — refresh() will create it")
            } else {
                console.warn("[Gmail] state load error:", error)
            }
        }
    }

    FileView {
        id: credsProbe
        path: Qt.resolvedUrl(root.credsPath)
        watchChanges: true
        onFileChanged: credsProbe.reload()
        onLoaded: {
            const present = (credsProbe.text() || "").trim().length > 0
            const wasPresent = root.credentialsPresent
            root.credentialsPresent = present
            if (present && !wasPresent) {
                console.log("[Gmail] credentials present, scheduling sync")
                stateFile.reload()
                root.refresh()
            }
        }
        onLoadFailed: () => {
            root.credentialsPresent = false
        }
    }

    Component.onCompleted: {
        credsProbe.reload()
    }

    // Same first-time fallback poller as Linear: watchChanges can miss
    // file *creation*, so re-probe every 10s until creds appear.
    Timer {
        interval: 10 * 1000
        running: !root.credentialsPresent
        repeat: true
        onTriggered: credsProbe.reload()
    }

    Timer {
        interval: 5 * 60 * 1000
        running: root.credentialsPresent && root.syncedAt.length > 0
        repeat: true
        onTriggered: root.refresh()
    }
}
