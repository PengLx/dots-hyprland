import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Compact issue card. Shows identifier, state dot+name, priority icon,
 * title (1-2 lines), and the project + due date footer.
 *
 * Required: `issue` (the normalized object from sync.py).
 * Click → opens the issue in Linear web. Right-click / press-and-hold →
 * emits stateMenuRequested for parent to show a state-change dropdown
 * (block 5).
 */
Rectangle {
    id: card
    required property var issue
    property bool compact: false
    signal stateMenuRequested(var issue, real x, real y)

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight + 16
    radius: Appearance.rounding.small
    color: hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    property bool hovered: false

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
    }

    function _priorityIcon(p) {
        // 0 None, 1 Urgent, 2 High, 3 Normal, 4 Low
        switch (p) {
        case 1: return "error";        // urgent
        case 2: return "keyboard_double_arrow_up";   // high
        case 3: return "drag_handle";  // normal
        case 4: return "keyboard_double_arrow_down"; // low
        default: return "remove";
        }
    }
    function _priorityColor(p) {
        switch (p) {
        case 1: return "#FF5252";
        case 2: return "#FFB74D";
        case 3: return Appearance.colors.colSubtext;
        case 4: return "#90A4AE";
        default: return Appearance.colors.colSubtext;
        }
    }
    function _formatDue(s) {
        if (!s) return ""
        // s is YYYY-MM-DD
        const today = new Date()
        const due = new Date(s + "T00:00:00")
        const ms = due - new Date(today.getFullYear(), today.getMonth(), today.getDate())
        const days = Math.round(ms / 86400000)
        if (days === 0) return "今天"
        if (days === 1) return "明天"
        if (days === -1) return "昨天"
        if (days < 0) return Math.abs(days) + " 天前"
        if (days < 7) return "" + days + " 天后"
        return s
    }
    function _isOverdue(s) {
        if (!s) return false
        const today = new Date()
        const due = new Date(s + "T00:00:00")
        return due < new Date(today.getFullYear(), today.getMonth(), today.getDate())
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: card.hovered = true
        onExited: card.hovered = false
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                card.stateMenuRequested(card.issue, mouse.x, mouse.y)
            } else if (card.issue && card.issue.url) {
                Quickshell.execDetached(["xdg-open", card.issue.url])
            }
        }
        onPressAndHold: function(mouse) {
            card.stateMenuRequested(card.issue, mouse.x, mouse.y)
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // Top row: identifier · state · priority · spacer · cycle
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                font.family: Appearance.font.family.monospace
                text: card.issue.identifier || ""
            }

            Rectangle {
                width: 8; height: 8; radius: 4
                color: (card.issue.state && card.issue.state.color) || "#888"
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                text: (card.issue.state && card.issue.state.name) || ""
            }

            MaterialSymbol {
                visible: card.issue.priority && card.issue.priority > 0
                iconSize: 14
                text: card._priorityIcon(card.issue.priority)
                color: card._priorityColor(card.issue.priority)
            }

            Item { Layout.fillWidth: true }

            StyledText {
                visible: card.issue.cycle && card.issue.cycle.number
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: card.issue.cycle ? ("Cycle " + card.issue.cycle.number) : ""
            }
        }

        // Title
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.WordWrap
            maximumLineCount: card.compact ? 1 : 2
            elide: Text.ElideRight
            text: card.issue.title || "(no title)"
        }

        // Bottom row: project · due · labels
        RowLayout {
            Layout.fillWidth: true
            visible: !card.compact && (
                (card.issue.project && card.issue.project.id) ||
                card.issue.due_date ||
                (card.issue.labels && card.issue.labels.length > 0)
            )
            spacing: 6

            Rectangle {
                visible: card.issue.project && card.issue.project.id
                width: 8; height: 8; radius: 4
                color: (card.issue.project && card.issue.project.color) || "#888"
            }
            StyledText {
                visible: card.issue.project && card.issue.project.id
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                Layout.maximumWidth: 140
                text: (card.issue.project && card.issue.project.name) || ""
            }

            Item {
                Layout.fillWidth: true
                visible: (card.issue.project && card.issue.project.id) && (card.issue.due_date || (card.issue.labels && card.issue.labels.length > 0))
            }

            MaterialSymbol {
                visible: !!card.issue.due_date
                iconSize: 12
                text: "schedule"
                color: card._isOverdue(card.issue.due_date) ? "#FF5252" : Appearance.colors.colSubtext
            }
            StyledText {
                visible: !!card.issue.due_date
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: card._isOverdue(card.issue.due_date) ? "#FF5252" : Appearance.colors.colSubtext
                text: card._formatDue(card.issue.due_date)
            }

            Item { Layout.fillWidth: !((card.issue.project && card.issue.project.id) || card.issue.due_date) }

            // Up to 3 label dots
            Repeater {
                model: (card.issue.labels || []).slice(0, 3)
                delegate: Rectangle {
                    required property var modelData
                    width: 6; height: 6; radius: 3
                    color: modelData.color || "#888"
                }
            }
        }
    }
}
