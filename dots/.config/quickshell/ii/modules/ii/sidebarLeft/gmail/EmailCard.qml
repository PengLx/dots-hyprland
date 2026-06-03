import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * One email row in the inbox list. Click → opens the EmailDetail modal.
 *
 * Required: `message` (normalized object from sync.py).
 */
Rectangle {
    id: card
    required property var message
    signal opened(var message)

    Layout.fillWidth: true
    width: ListView.view ? ListView.view.width : (parent ? parent.width : implicitWidth)
    implicitHeight: cardCol.implicitHeight + 18
    radius: Appearance.rounding.small
    color: hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    property bool hovered: false

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
    }

    function _formatTime(internalDateMs) {
        if (!internalDateMs) return ""
        const ms = parseInt(internalDateMs)
        if (isNaN(ms)) return ""
        const now = Date.now()
        const diff = now - ms
        const mins = Math.round(diff / 60000)
        if (mins < 1) return "刚刚"
        if (mins < 60) return mins + " 分钟前"
        const hrs = Math.round(mins / 60)
        if (hrs < 24) return hrs + " 小时前"
        const d = new Date(ms)
        const today = new Date()
        const sameYear = d.getFullYear() === today.getFullYear()
        const pad = function(n) { return n < 10 ? "0" + n : "" + n }
        if (sameYear) return (d.getMonth() + 1) + "月" + d.getDate() + "日"
        return d.getFullYear() + "/" + pad(d.getMonth() + 1) + "/" + pad(d.getDate())
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: card.hovered = true
        onExited: card.hovered = false
        onClicked: card.opened(card.message)
    }

    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: 9
        spacing: 3

        // Top row: unread dot · sender · time
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                width: 8; height: 8; radius: 4
                color: card.message.is_unread ? Appearance.colors.colPrimary : "transparent"
                border.width: card.message.is_unread ? 0 : 1
                border.color: Appearance.colors.colSubtext
                opacity: card.message.is_unread ? 1 : 0.4
            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: card.message.is_unread ? Font.Medium : Font.Normal
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                text: (card.message.from && card.message.from.name) || (card.message.from && card.message.from.email) || "(unknown)"
            }

            MaterialSymbol {
                visible: card.message.is_starred
                iconSize: 12
                text: "star"
                color: "#FFC107"
            }
            MaterialSymbol {
                visible: card.message.is_important
                iconSize: 12
                text: "label_important"
                color: "#FFB74D"
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: card._formatTime(card.message.internal_date)
            }
        }

        // Subject
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: card.message.is_unread ? Font.Medium : Font.Normal
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            text: card.message.subject || "(无主题)"
        }

        // Snippet
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            text: card.message.snippet || ""
        }
    }
}
