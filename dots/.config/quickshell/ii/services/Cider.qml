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
    property var queue: []          // [{ id, name, artistName, albumName }] — Cider returns the queue with index 0 = current track.
    property string lastError: ""

    // Slot 1 of the queue — the track Cider will play next. Lyrics
    // service watches this so it can warm its cache before that track
    // becomes the active one, eliminating the ~1s LRCLIB fetch latency
    // at every track boundary.
    readonly property var nextTrack: (queue.length > 1) ? queue[1] : null

    // Smoothed playback time. The RPC returns currentPlaybackTime once a
    // second; in between polls we extrapolate from the wall clock so the
    // displayed position keeps moving even when Cider briefly returns the
    // same value (Apple Music Electron client occasionally stalls its RPC
    // mid-track even though playback continues). Resets on every
    // successful poll to whatever the RPC just told us, so any drift is
    // bounded by one poll interval.
    property real smoothPosition: 0
    property real _basePosition: 0
    property real _basePollWallSec: 0
    property bool _basePlaying: false

    // `connected` exposes a sticky version of the connection state. A
    // single bad poll (Cider transitioning between tracks, briefly
    // returns status:"error" or 5xx) used to flip us straight to false;
    // PlayerControl would then fall back to MPRIS, which shows Cider's
    // bogus accumulated time, until the next 1s tick reconnected us.
    // We now require `failureGraceCount` consecutive failures before
    // declaring the connection lost, so transient flutter doesn't bleed
    // into the UI.
    readonly property int failureGraceCount: 4
    property int _consecutiveFailures: 0
    property bool _everConnected: false
    readonly property bool connected:
        _everConnected && _consecutiveFailures < failureGraceCount

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
    function _markFailure(msg) {
        root.lastError = msg
        if (root._consecutiveFailures < failureGraceCount * 2) {
            root._consecutiveFailures += 1
        }
    }

    // Pulled separately from nowPlaying — refreshed on track change
    // (driven from fetchNowPlaying) rather than every second, since the
    // queue rarely changes and is comparatively heavy (full track list).
    function fetchQueue() {
        if (!root.connected) return
        const xhr = new XMLHttpRequest()
        xhr.open("GET", root.baseUrl + "/api/v1/playback/queue")
        if (root.tokenPresent && root.apiToken) {
            xhr.setRequestHeader("apitoken", root.apiToken)
        }
        xhr.timeout = 2500
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) return
            try {
                const data = JSON.parse(xhr.responseText || "[]")
                if (!Array.isArray(data)) return
                root.queue = data.map(function(item) {
                    const a = item.attributes || {}
                    return {
                        id: item.id,
                        name: a.name || "",
                        artistName: a.artistName || "",
                        albumName: a.albumName || "",
                    }
                })
            } catch (e) { /* ignore parse errors */ }
        }
        try { xhr.send() } catch (e) { /* ignore */ }
    }

    function fetchNowPlaying() {
        // Cheap presence check — refresh ciderRunning every tick from
        // Mpris.players.values (the Mpris singleton doesn't fire a
        // generic players-changed signal we can hook into, so polling
        // it here is the simplest reliable approach).
        root.ciderRunning = _ciderInMpris()
        if (!root.ciderRunning) {
            // Cider gone for real — drop everything immediately.
            root._everConnected = false
            root._consecutiveFailures = 0
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
                        const oldName = (root.nowPlaying && root.nowPlaying.name) || ""
                        root.nowPlaying = data.info
                        root._consecutiveFailures = 0
                        const justBecameConnected = !root._everConnected
                        root._everConnected = true
                        root.lastError = ""

                        // Reset the smoothing base every successful poll
                        // so the wall-clock extrapolation is anchored
                        // somewhere honest. _basePlaying drives the tick
                        // timer below; we trust MprisController for
                        // play state since Cider's now-playing payload
                        // doesn't include it directly.
                        root._basePosition = data.info.currentPlaybackTime ?? 0
                        root._basePollWallSec = Date.now() / 1000
                        root._basePlaying = MprisController.isPlaying
                        root.smoothPosition = root._basePosition

                        // Track changed → refresh queue so consumers know
                        // what's coming up next. Skipped on no-op ticks
                        // for the same track.
                        if (data.info.name !== oldName) {
                            root.fetchQueue()
                        }

                        if (justBecameConnected || !wasConnected) {
                            console.log("[Cider] connected;",
                                "now playing:", data.info.name,
                                "(" + Math.round(data.info.durationInMillis / 1000) + "s)")
                        }
                        return
                    }
                    if (data && data.status === "error") {
                        _markFailure(data.message || "RPC error")
                        return
                    }
                } catch (e) {
                    _markFailure("parse: " + e)
                    return
                }
            }
            if (xhr.status === 401 || xhr.status === 403) {
                _markFailure("auth (HTTP " + xhr.status + ")")
            } else if (xhr.status === 0) {
                _markFailure("Cider RPC unreachable")
            } else {
                _markFailure("HTTP " + xhr.status)
            }
        }
        try {
            xhr.send()
        } catch (e) {
            _markFailure("send: " + e)
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
            // Token going away doesn't disconnect — Cider with auth off
            // works fine without one. The polling loop's own failure
            // counter handles real disconnects.
        }
    }

    // FileView watchChanges misses first-time creation — re-probe.
    Timer {
        interval: 10 * 1000
        running: !root.tokenPresent
        repeat: true
        onTriggered: tokenFile.reload()
    }

    // Smooth-position interpolator. Ticks while we believe the player
    // is playing and updates the exposed smoothPosition from the wall
    // clock, so consumers (PlayerControl, Lyrics) keep moving even when
    // the underlying RPC value is stale for a tick or two.
    Timer {
        interval: 200
        running: root.connected && root._basePlaying
        repeat: true
        onTriggered: {
            const now = Date.now() / 1000
            root.smoothPosition = root._basePosition + (now - root._basePollWallSec)
        }
    }

    // Keep the smoothing flag in sync with MPRIS play state; on pause we
    // freeze at the last extrapolated value, on resume we resume ticking
    // from that point until the next RPC poll resets us.
    Connections {
        target: MprisController
        function onIsPlayingChanged() {
            if (!MprisController.isPlaying) {
                root._basePosition = root.smoothPosition
                root._basePollWallSec = Date.now() / 1000
            } else {
                root._basePollWallSec = Date.now() / 1000
            }
            root._basePlaying = MprisController.isPlaying
        }
    }

    Component.onCompleted: {
        tokenFile.reload()
        fetchNowPlaying()
    }
}
