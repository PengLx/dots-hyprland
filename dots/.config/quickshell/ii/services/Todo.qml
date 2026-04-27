pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * To-do list manager with optional Todoist sync.
 * - If ${XDG_CONFIG_HOME}/todoist_token exists and is non-empty, sync via Todoist v1 API.
 * - Otherwise fall back to local-only JSON at Directories.todoPath.
 * Items are { content, done, id }. id is the Todoist task id (string) or undefined for local-only.
 */
Singleton {
    id: root

    readonly property string apiBase: "https://api.todoist.com/api/v1"
    readonly property string tokenPath: FileUtils.trimFileProtocol(`${Directories.config}/todoist_token`)
    readonly property var filePath: Directories.todoPath

    property string token: ""
    property bool useTodoist: false
    property bool initialized: false
    property var list: []

    function _persistLocal() {
        todoFileView.setText(JSON.stringify(root.list))
    }

    function _setList(items) {
        root.list = items.slice ? items.slice(0) : []
        _persistLocal()
    }

    function _request(method, url, body, onOk, onErr) {
        const xhr = new XMLHttpRequest()
        xhr.open(method, url)
        if (root.token) xhr.setRequestHeader("Authorization", "Bearer " + root.token)
        if (body) xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status >= 200 && xhr.status < 300) {
                let data = null
                if (xhr.responseText && xhr.responseText.length) {
                    try { data = JSON.parse(xhr.responseText) } catch (e) {}
                }
                if (onOk) onOk(data)
            } else {
                console.warn("[Todo/Todoist]", method, url, "->", xhr.status, (xhr.responseText || "").slice(0, 200))
                if (onErr) onErr(xhr.status, xhr.responseText)
            }
        }
        xhr.send(body ? JSON.stringify(body) : null)
    }

    function refresh() {
        if (root.useTodoist) {
            _request("GET", root.apiBase + "/tasks", null, function(data) {
                if (!data || !data.results) return
                const items = data.results.map(function(t) {
                    return { content: t.content, done: false, id: t.id }
                })
                _setList(items)
            })
        } else {
            todoFileView.reload()
        }
    }

    function addItem(item) {
        if (root.useTodoist) {
            addTask((item && item.content) || "")
        } else {
            list.push(item)
            _setList(list)
        }
    }

    function addTask(desc) {
        if (root.useTodoist) {
            const tmpId = "_tmp_" + Date.now()
            const optimistic = { content: desc, done: false, id: tmpId }
            _setList([optimistic].concat(root.list))
            _request("POST", root.apiBase + "/tasks", { content: desc }, function(t) {
                if (!t) { refresh(); return }
                const idx = root.list.findIndex(function(x){ return x.id === tmpId })
                if (idx >= 0) {
                    const nl = root.list.slice(0)
                    nl[idx] = { content: t.content, done: false, id: t.id }
                    _setList(nl)
                }
            }, function() {
                _setList(root.list.filter(function(x){ return x.id !== tmpId }))
            })
        } else {
            addItem({ content: desc, done: false })
        }
    }

    function markDone(index) {
        if (index < 0 || index >= list.length) return
        const item = list[index]
        list[index].done = true
        _setList(list)
        if (root.useTodoist && item.id && !String(item.id).startsWith("_tmp_")) {
            _request("POST", root.apiBase + "/tasks/" + item.id + "/close", null, null, function() {
                if (index >= 0 && index < list.length && list[index].id === item.id) {
                    list[index].done = false
                    _setList(list)
                }
            })
        }
    }

    function markUnfinished(index) {
        if (index < 0 || index >= list.length) return
        const item = list[index]
        list[index].done = false
        _setList(list)
        if (root.useTodoist && item.id && !String(item.id).startsWith("_tmp_")) {
            _request("POST", root.apiBase + "/tasks/" + item.id + "/reopen", null, null, function() {
                if (index >= 0 && index < list.length && list[index].id === item.id) {
                    list[index].done = true
                    _setList(list)
                }
            })
        }
    }

    function deleteItem(index) {
        if (index < 0 || index >= list.length) return
        const removed = list[index]
        list.splice(index, 1)
        _setList(list)
        if (root.useTodoist && removed.id && !String(removed.id).startsWith("_tmp_")) {
            _request("DELETE", root.apiBase + "/tasks/" + removed.id, null, null, function() {
                refresh()
            })
        }
    }

    Component.onCompleted: {
        tokenFileView.reload()
    }

    // Periodic resync so external Todoist changes (mobile app, web) propagate.
    Timer {
        interval: 60000
        running: root.useTodoist && root.initialized
        repeat: true
        onTriggered: root.refresh()
    }

    FileView {
        id: tokenFileView
        path: Qt.resolvedUrl(root.tokenPath)
        onLoaded: {
            const t = (tokenFileView.text() || "").replace(/[\r\n]+$/g, "").trim()
            if (t.length > 0) {
                root.token = t
                root.useTodoist = true
                console.log("[Todo] Todoist token loaded, fetching remote list")
                // Show local cache first (instant UI), then refresh from server.
                todoFileView.reload()
                root.refresh()
                root.initialized = true
            } else {
                console.log("[Todo] Empty Todoist token file, using local mode")
                todoFileView.reload()
                root.initialized = true
            }
        }
        onLoadFailed: (error) => {
            console.log("[Todo] No Todoist token (" + error + "), using local mode")
            todoFileView.reload()
            root.initialized = true
        }
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            try {
                root.list = JSON.parse(todoFileView.text() || "[]")
            } catch (e) {
                root.list = []
            }
            console.log("[Todo] local cache loaded (" + root.list.length + " items)")
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Todo] local file not found, creating")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                console.log("[Todo] error loading local cache: " + error)
            }
        }
    }
}
