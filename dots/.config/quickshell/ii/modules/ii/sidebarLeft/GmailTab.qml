import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.gmail
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

Item {
    id: root
    property real padding: 4

    property bool unreadOnly: false
    property bool detailOpen: false
    property var detailMessage: null

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_R) {
            Gmail.refresh()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.detailOpen) {
            root.detailOpen = false
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        // Toggle row: All / Unread + status + refresh
        RowLayout {
            visible: Gmail.credentialsPresent
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 4
            spacing: 6

            // Filter chips
            Rectangle {
                radius: Appearance.rounding.small
                implicitHeight: 28
                implicitWidth: filterRow.implicitWidth + 8
                color: Appearance.colors.colLayer2
                RowLayout {
                    id: filterRow
                    anchors.centerIn: parent
                    spacing: 0
                    Repeater {
                        model: [
                            { value: false, label: "全部",   icon: "inbox" },
                            { value: true,  label: "未读",   icon: "mark_email_unread" },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            implicitHeight: 24
                            implicitWidth: chipText.implicitWidth + 24
                            radius: Appearance.rounding.small
                            color: root.unreadOnly === modelData.value
                                ? Appearance.colors.colPrimary
                                : "transparent"
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    iconSize: 14
                                    text: modelData.icon
                                    color: root.unreadOnly === modelData.value
                                        ? Appearance.m3colors.m3onPrimary
                                        : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    id: chipText
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.unreadOnly === modelData.value
                                        ? Appearance.m3colors.m3onPrimary
                                        : Appearance.colors.colOnLayer1
                                    text: modelData.label + (modelData.value && Gmail.unreadCount > 0
                                        ? (" (" + Gmail.unreadCount + ")") : "")
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.unreadOnly = modelData.value
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Gmail.refreshing ? "正在同步..."
                    : Gmail.lastError ? ("⚠ " + Gmail.lastError)
                    : Gmail.syncedAt ? Gmail.syncedAt.replace("T", " ").substring(11, 16)
                    : ""
            }

            RippleButton {
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: Appearance.rounding.small
                enabled: !Gmail.refreshing && Gmail.credentialsPresent
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 14
                    text: "refresh"
                    color: Appearance.colors.colOnLayer1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Gmail.refresh()
                }
            }
        }

        // Content area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            // Inbox list
            InboxView {
                anchors.fill: parent
                visible: Gmail.credentialsPresent
                unreadOnly: root.unreadOnly
                onOpened: function(msg) {
                    root.detailMessage = msg
                    root.detailOpen = true
                }
            }

            // Detail modal (overlays the list when open)
            EmailDetail {
                id: detailView
                anchors.fill: parent
                visible: root.detailOpen
                onClosed: root.detailOpen = false
                onVisibleChanged: {
                    if (visible && root.detailMessage) {
                        setMessage(root.detailMessage)
                    }
                }
            }

            // No-credentials placeholder
            ColumnLayout {
                anchors.centerIn: parent
                visible: !Gmail.credentialsPresent
                spacing: 12
                width: Math.min(parent.width - 40, 360)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                    text: "vpn_key"
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: "未配置 Gmail 登录"
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: "运行:\npython3 ~/Projects/end4-staging/dots-hyprland/personal/gmail/login.py"
                }
            }
        }
    }
}
