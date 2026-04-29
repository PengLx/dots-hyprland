pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

/**
 * Cider local RPC bridge.
 *
 * Cider is Electron-based and registers as a Chromium MPRIS bus. Its
 * MPRIS metadata is unreliable: mpris:length is a fake number, position
 * looks like a session-relative counter rather than per-track time.
 *
 * Cider also exposes a local HTTP API on 127.0.0.1:10767. We poll the
 * `now-playing` endpoint once a second whenever Cider is the active
 * MPRIS player and the user has stored an apitoken. The data is exposed
 * via `nowPlaying` for the media-controls panel to override its display.
 *
 * Inert (and free) unless:
 *   - ~/.config/quickshell-cider/api_token exists with non-empty content
 *   - There is an MprisPlayer with identity "Cider" registered
 *
 * Setup: see personal/cider/README.md.
 */
Singleton {
    id: root

    readonly property string baseUrl: "http://127.0.0.1:10767"
    readonly property string tokenPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell-cider/api_token`)

    property string apiToken: ""
    property bool tokenPresent: false
    property var nowPlaying: ({})  // { name, artistName, albumName, currentPlaybackTime, durationInMillis, artwork: { url } }
    property bool connected: false
    property string lastError: ""

    // Polling is gated on Cider being present on D-Bus; the apitoken
    // header is sent only when we have one, so users who turn auth off
    // in Cider's settings (also a documented option) can skip the token
    // file entirely.
    readonly property bool active: ciderRunning
    property bool ciderRunning: false

    function _ciderInMpris() {
        const players = Mpris.players?.values || []
        for (let i = 0; i < players.length; i++) {
            if (players[i] && players[i].identity === "Cider") return true
        }
        return false
    }

    // ---- HTTP polling ----
    function fetchNowPlaying() {
        // Cheap presence check — refresh ciderRunning every tick from
        // Mpris.players.values (the Mpris singleton doesn't fire a
        // generic players-changed signal we can hook into, so polling
        // it here is the simplest reliable approach).
        root.ciderRunning = _ciderInMpris()
        if (!root.ciderRunning) {
            root.connected = false
            return
        }
        const xhr = new XMLHttpRequest()
        xhr.open("GET", root.baseUrl + "/api/v1/playback/now-playing")
        if (root.tokenPresent && root.apiToken) {
            xhr.setRequestHeader("apitoken", root.apiToken)
        }
        xhr.timeout = 1500
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    const data = JSON.parse(xhr.responseText || "{}")
                    if (data && data.status === "ok" && data.info) {
                        const wasConnected = root.connected
                        root.nowPlaying = data.info
                        root.connected = true
                        root.lastError = ""
                        if (!wasConnected) {
                            console.log("[Cider] connected;",
                                "now playing:", data.info.name,
                                "(" + Math.round(data.info.durationInMillis / 1000) + "s)")
                        }
                        return
                    }
                    if (data && data.status === "error") {
                        root.connected = false
                        root.lastError = data.message || "RPC error"
                        return
                    }
                } catch (e) {
                    root.connected = false
                    root.lastError = "parse: " + e
                    return
                }
            }
            root.connected = false
            if (xhr.status === 401 || xhr.status === 403) {
                root.lastError = "auth (HTTP " + xhr.status + ")"
            } else if (xhr.status === 0) {
                root.lastError = "Cider RPC unreachable"
            } else {
                root.lastError = "HTTP " + xhr.status
            }
        }
        try {
            xhr.send()
        } catch (e) {
            root.connected = false
            root.lastError = "send: " + e
        }
    }

    function seek(positionSec) {
        if (!root.active) return
        const xhr = new XMLHttpRequest()
        xhr.open("POST", root.baseUrl + "/api/v1/playback/seek")
        if (root.tokenPresent && root.apiToken) {
            xhr.setRequestHeader("apitoken", root.apiToken)
        }
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.timeout = 1500
        try {
            xhr.send(JSON.stringify({ position: positionSec }))
        } catch (e) { /* ignore */ }
    }

    Timer {
        // 1s while connected, 3s while we're trying to (re)connect.
        // Avoids hammering localhost when Cider isn't responding.
        interval: root.connected ? 1000 : 3000
        running: root.active
        repeat: true
        onTriggered: root.fetchNowPlaying()
    }

    FileView {
        id: tokenFile
        path: Qt.resolvedUrl(root.tokenPath)
        watchChanges: true
        onFileChanged: tokenFile.reload()
        onLoaded: {
            const text = (tokenFile.text() || "").trim()
            root.apiToken = text
            const wasPresent = root.tokenPresent
            root.tokenPresent = text.length > 0
            if (root.tokenPresent && !wasPresent) {
                console.log("[Cider] api_token present, polling")
                root.fetchNowPlaying()
            }
        }
        onLoadFailed: {
            root.tokenPresent = false
            root.connected = false
        }
    }

    // FileView watchChanges misses first-time creation — re-probe.
    Timer {
        interval: 10 * 1000
        running: !root.tokenPresent
        repeat: true
        onTriggered: tokenFile.reload()
    }

    Component.onCompleted: {
        tokenFile.reload()
        fetchNowPlaying()
    }
}
