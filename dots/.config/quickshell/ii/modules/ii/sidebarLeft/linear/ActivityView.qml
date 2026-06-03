import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

Item {
    id: root

    function _iconForType(t) {
        if (!t) return "notifications"
        const s = String(t)
        if (s.indexOf("comment") !== -1 || s.indexOf("Comment") !== -1) return "chat"
        if (s.indexOf("mention") !== -1 || s.indexOf("Mention") !== -1) return "alternate_email"
        if (s.indexOf("status") !== -1 || s.indexOf("Status") !== -1) return "swap_horiz"
        if (s.indexOf("assigned") !== -1 || s.indexOf("Assigned") !== -1) return "person_add"
        if (s.indexOf("subscribed") !== -1) return "notifications"
        if (s.indexOf("reaction") !== -1) return "thumb_up"
        return "circle_notifications"
    }

    function _formatType(t) {
        if (!t) return ""
        const s = String(t)
        // Linear notification type strings look like "issueAssignedToYou", "issueCommentMention"...
        // Convert camelCase → spaced + simplify
        const out = s.replace(/^issue/, "")
                     .replace(/([A-Z])/g, " $1")
                     .trim()
                     .toLowerCase()
        return out.charAt(0).toUpperCase() + out.slice(1)
    }

    function _formatTime(s) {
        if (!s) return ""
        const d = new Date(s)
        const now = new Date()
        const ms = now - d
        const mins = Math.round(ms / 60000)
        if (mins < 1) return "刚刚"
        if (mins < 60) return mins + " 分钟前"
        const hrs = Math.round(mins / 60)
        if (hrs < 24) return hrs + " 小时前"
        const days = Math.round(hrs / 24)
        if (days < 7) return days + " 天前"
        return s.substring(0, 10)
    }

    function _truncate(s, n) {
        if (!s) return ""
        const t = String(s).replace(/\n+/g, " ")
        return t.length > n ? t.substring(0, n) + "…" : t
    }

    StyledListView {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6
        clip: true
        model: Linear.notifications || []

        delegate: Rectangle {
            required property var modelData
            id: notifCard
            width: ListView.view.width
            radius: Appearance.rounding.small
            color: notifCard.modelData.read_at ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Hover
            implicitHeight: row.implicitHeight + 16

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const url = (notifCard.modelData.issue && notifCard.modelData.issue.url) || ""
                    if (url) Quickshell.execDetached(["xdg-open", url])
                }
            }

            RowLayout {
                id: row
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    iconSize: 20
                    text: root._iconForType(notifCard.modelData.type)
                    color: notifCard.modelData.read_at ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            text: (notifCard.modelData.actor && notifCard.modelData.actor.name) || "?"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            text: root._formatType(notifCard.modelData.type)
                            elide: Text.ElideRight
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root._formatTime(notifCard.modelData.created_at)
                        }
                    }

                    RowLayout {
                        visible: notifCard.modelData.issue && notifCard.modelData.issue.identifier
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: (notifCard.modelData.issue && notifCard.modelData.issue.identifier) || ""
                        }
                        Rectangle {
                            visible: notifCard.modelData.issue && notifCard.modelData.issue.state
                            width: 6; height: 6; radius: 3
                            color: (notifCard.modelData.issue && notifCard.modelData.issue.state && notifCard.modelData.issue.state.color) || "#888"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            text: (notifCard.modelData.issue && notifCard.modelData.issue.title) || ""
                        }
                    }

                    StyledText {
                        visible: notifCard.modelData.comment && notifCard.modelData.comment.body
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.italic: true
                        color: Appearance.colors.colSubtext
                        text: "「" + root._truncate((notifCard.modelData.comment && notifCard.modelData.comment.body) || "", 160) + "」"
                    }
                }
            }
        }
    }

    PagePlaceholder {
        z: 2
        anchors.centerIn: parent
        shown: (Linear.notifications || []).length === 0 && Linear.credentialsPresent && Linear.syncedAt.length > 0
        icon: "history"
        title: "暂无活动"
        description: "近期没有通知"
        shape: MaterialShape.Shape.Bun
    }
}
