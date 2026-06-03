import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root
    signal opened(var message)
    property bool unreadOnly: false

    // Reactive binding: re-evaluates whenever Gmail.messages or unreadOnly changes.
    property var filteredMessages: {
        const arr = Gmail.messages || []
        if (!root.unreadOnly) return arr
        return arr.filter(function(m) { return m.is_unread })
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
        spacing: 4
        clip: true
        model: root.filteredMessages

        delegate: EmailCard {
            required property var modelData
            message: modelData
            onOpened: function(msg) { root.opened(msg) }
        }
    }

    PagePlaceholder {
        z: 2
        anchors.centerIn: parent
        shown: root.filteredMessages.length === 0 && Gmail.credentialsPresent && Gmail.syncedAt.length > 0
        icon: root.unreadOnly ? "mark_email_read" : "inbox"
        title: root.unreadOnly ? "没有未读邮件" : "Inbox 是空的"
        description: root.unreadOnly ? "你都看完啦 ✨" : "暂无邮件"
        shape: MaterialShape.Shape.Bun
    }
}
