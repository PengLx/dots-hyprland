pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

/**
 * Synced lyrics from LRCLIB (https://lrclib.net), keyed off whichever
 * MPRIS track is currently active. Falls back to MprisPlayer.position for
 * timing; for Cider specifically (which lies through MPRIS), borrows
 * Cider.nowPlaying.currentPlaybackTime instead — that integration already
 * exists for the media-controls panel.
 *
 * Cache is keyed by `artist|title|album` so repeating a track within the
 * session doesn't re-fetch. A 404 for a track is also cached (as an empty
 * array) to avoid hitting LRCLIB on every replay of an obscure track.
 *
 * Exposes:
 *   - `lines`            — [{ time: seconds, text: "..." }]
 *   - `currentLine`      — text of the line whose time <= now < next.time
 *   - `currentLineIndex` — index into `lines`
 *   - `nextLine`         — text of the upcoming line (for two-line previews)
 *   - `hasLyrics`        — bool, true iff the current track has any lines
 *   - `fetching`         — bool, true while a request is in flight
 *   - `lastError`        — string, set on fetch / parse failure
 */
Singleton {
    id: root

    readonly property string baseUrl: "https://lrclib.net/api/get"

    property var cache: ({})       // trackKey → array of { time, text }
    property var lines: []
    property string currentLine: ""
    property string nextLine: ""
    property int currentLineIndex: -1
    property string lastError: ""
    property bool fetching: false

    readonly property bool hasLyrics: lines.length > 0

    // Use Cider's authoritative time when available, MPRIS otherwise.
    readonly property real currentPositionSec: {
        const player = MprisController.activePlayer
        if (Cider.connected && player?.identity === "Cider") {
            return Cider.smoothPosition ?? 0
        }
        return player?.position ?? 0
    }

    // Single source of truth: pick Cider's RPC data when it's the active
    // player and connected, MPRIS otherwise. trackKey derives from this
    // — they used to be two parallel bindings, which raced on track
    // change (one binding could read Cider while the other read MPRIS in
    // the same handler tick, and the URL we fetched ended up belonging
    // to a different song than the key we cached it under).
    readonly property var currentTrack: {
        const player = MprisController.activePlayer
        if (Cider.connected && player?.identity === "Cider" && Cider.nowPlaying?.name) {
            const np = Cider.nowPlaying
            return { artist: np.artistName || "", title: np.name || "", album: np.albumName || "" }
        }
        const t = MprisController.activeTrack
        return { artist: t?.artist || "", title: t?.title || "", album: t?.album || "" }
    }

    readonly property string trackKey:
        currentTrack.title.length === 0
            ? ""
            : `${currentTrack.artist}|${currentTrack.title}|${currentTrack.album}`


    onTrackKeyChanged: {
        root.currentLineIndex = -1
        root.currentLine = ""
        root.nextLine = ""
        if (!trackKey) { root.lines = []; return }
        if (cache[trackKey] !== undefined) {
            console.log("[Lyrics] track changed:", trackKey, "(cached,", cache[trackKey].length, "lines)")
            root.lines = cache[trackKey]
            _refreshCurrentLine()
        } else {
            console.log("[Lyrics] track changed:", trackKey, "(fetching)")
            root.lines = []
            _fetchLrclib(root.currentTrack)
        }
    }

    onLinesChanged: _refreshCurrentLine()

    // Warm the cache for the next queued track so when Cider auto-
    // advances, lyrics are already there. Fire-and-forget; the fetch
    // response handler stores the result in cache regardless of whether
    // that track is still "next" by then.
    Connections {
        target: Cider
        function onNextTrackChanged() {
            const nt = Cider.nextTrack
            if (!nt || !nt.name) return
            const track = {
                artist: nt.artistName || "",
                title: nt.name || "",
                album: nt.albumName || "",
            }
            const key = `${track.artist}|${track.title}|${track.album}`
            if (!key || root.cache[key] !== undefined) return
            console.log("[Lyrics] prefetching next:", key)
            root._fetchLrclib(track)
        }
    }

    function _fetchLrclib(track, withAlbum) {
        if (!track || !track.title) return
        if (withAlbum === undefined) withAlbum = true
        // The key we're fetching FOR. Recompute from the same `track` we
        // were called with rather than reading root.trackKey separately —
        // that avoided one race where binding re-evaluation order could
        // make `track` and `root.trackKey` describe different songs.
        const key = `${track.artist || ""}|${track.title || ""}|${track.album || ""}`
        // If we already have it cached (success or empty), no-op. Lets
        // prefetch be safely idempotent.
        if (root.cache[key] !== undefined) return
        let params = `artist_name=${encodeURIComponent(track.artist || "")}` +
                      `&track_name=${encodeURIComponent(track.title)}`
        if (withAlbum && track.album) {
            params += `&album_name=${encodeURIComponent(track.album)}`
        }
        const url = `${root.baseUrl}?${params}`
        console.log("[Lyrics] GET", url)

        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.timeout = 8000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            // Whether the just-fetched track is still the one playing.
            // We always cache; only update the live `lines` if so.
            const isCurrent = (key === root.trackKey)
            if (isCurrent) root.fetching = false

            console.log("[Lyrics] response", xhr.status, "for", key, isCurrent ? "" : "(prefetch)")
            if (xhr.status === 200) {
                try {
                    const data = JSON.parse(xhr.responseText || "{}")
                    if (data && data.syncedLyrics) {
                        const parsed = root._parseLrc(data.syncedLyrics)
                        const newCache = Object.assign({}, root.cache)
                        newCache[key] = parsed
                        root.cache = newCache
                        if (isCurrent) {
                            root.lines = parsed
                            root.lastError = parsed.length === 0 ? "empty" : ""
                        }
                        const sample = parsed.length > 0 ? parsed[0].text.substring(0, 40) : ""
                        console.log("[Lyrics] cached", parsed.length, "lines for", key,
                            "first:", JSON.stringify(sample))
                        return
                    }
                } catch (e) {
                    if (isCurrent) root.lastError = "parse: " + e
                }
            }
            // 404 with album set → try once more without it. LRCLIB's
            // /api/get is exact-match, and streaming clients (Cider with
            // Apple Music) often report album names that don't line up
            // with what's in LRCLIB's index (e.g. "÷ (Deluxe)" vs "÷").
            if (xhr.status === 404 && withAlbum && track.album) {
                console.log("[Lyrics] retrying without album")
                root._fetchLrclib(track, false)
                return
            }
            // Cache miss / error — remember as empty so we don't refetch.
            const newCache = Object.assign({}, root.cache)
            newCache[key] = []
            root.cache = newCache
            if (isCurrent) {
                root.lines = []
                root.lastError = xhr.status === 404 ? "no lyrics" : "HTTP " + xhr.status
            }
        }
        try {
            root.fetching = true
            root.lastError = ""
            xhr.send()
        } catch (e) {
            root.fetching = false
            root.lastError = "send: " + e
        }
    }

    // LRC format: `[mm:ss.cs] line text` (one or more `[..]` per line is
    // legal — same line repeated at multiple timestamps).
    function _parseLrc(text) {
        const rawLines = text.split(/\r?\n/)
        const out = []
        const tsAll = /\[(\d+):(\d+(?:\.\d+)?)\]/g
        for (let i = 0; i < rawLines.length; i++) {
            const raw = rawLines[i]
            const stripped = raw.replace(/\[[^\]]+\]/g, "").trim()
            tsAll.lastIndex = 0
            let m
            while ((m = tsAll.exec(raw)) !== null) {
                const t = parseInt(m[1]) * 60 + parseFloat(m[2])
                if (!isNaN(t)) {
                    out.push({ time: t, text: stripped })
                }
            }
        }
        out.sort((a, b) => a.time - b.time)
        return out
    }

    function _findCurrentIndex(time) {
        if (root.lines.length === 0) return -1
        let lo = 0, hi = root.lines.length - 1, ans = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (root.lines[mid].time <= time) {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    function _refreshCurrentLine() {
        const idx = root._findCurrentIndex(root.currentPositionSec)
        if (idx === root.currentLineIndex) return
        root.currentLineIndex = idx
        root.currentLine = idx >= 0 ? root.lines[idx].text : ""
        root.nextLine = (idx >= 0 && idx + 1 < root.lines.length)
            ? root.lines[idx + 1].text : ""
    }

    Timer {
        // 250ms is enough for LRC at typical line cadence (~3-6s) without
        // burning CPU. Only ticks when there's something to display and
        // the player is actually moving.
        interval: 250
        running: root.hasLyrics && (MprisController.activePlayer?.isPlaying ?? false)
        repeat: true
        onTriggered: root._refreshCurrentLine()
    }
}
