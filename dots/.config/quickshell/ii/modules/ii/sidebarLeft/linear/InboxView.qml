import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    // 1=urgent first, 0=none last; then by due date asc (no-due last); then updatedAt desc
    function _sorted() {
        const arr = (Linear.myIssues || []).slice()
        const prio = (p) => p === 0 ? 5 : p
        const dueKey = (s) => s ? s : "9999"
        arr.sort(function(a, b) {
            const pa = prio(a.priority || 0)
            const pb = prio(b.priority || 0)
            if (pa !== pb) return pa - pb
            const da = dueKey(a.due_date)
            const db = dueKey(b.due_date)
            if (da !== db) return da.localeCompare(db)
            return (b.updated_at || "").localeCompare(a.updated_at || "")
        })
        return arr
    }

    property var sortedIssues: _sorted()
    Connections {
        target: Linear
        function onMyIssuesChanged() { root.sortedIssues = root._sorted() }
    }

    StateMenu {
        id: stateMenu
    }

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: Appearance.rounding.small
        }
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6
        clip: true
        model: root.sortedIssues

        delegate: IssueCard {
            required property var modelData
            issue: modelData
            onStateMenuRequested: function(it, x, y) {
                const pos = mapToItem(root, x, y)
                stateMenu.openFor(it, pos.x, pos.y)
            }
        }
    }

    PagePlaceholder {
        z: 2
        anchors.centerIn: parent
        shown: root.sortedIssues.length === 0 && Linear.credentialsPresent && Linear.syncedAt.length > 0
        icon: "inbox"
        title: "Inbox 是空的"
        description: "暂无分配给你的活跃 issue"
        shape: MaterialShape.Shape.Bun
    }
}
