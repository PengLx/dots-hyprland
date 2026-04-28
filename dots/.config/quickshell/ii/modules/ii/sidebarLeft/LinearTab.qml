import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.linear
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

Item {
    id: root
    property real padding: 4

    property var subTabList: [
        { "icon": "inbox",     "name": "Inbox" },
        { "icon": "view_kanban","name": "Cycle" },
        { "icon": "folder_open","name": "Projects" },
        { "icon": "history",    "name": "Activity" },
    ]

    property bool showAddDialog: false
    property int fabSize: 48
    property int fabMargins: 14

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.NoModifier && event.key === Qt.Key_N) {
            root.showAddDialog = true
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_R) {
            Linear.refresh()
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        // Sub-tab toolbar
        Toolbar {
            visible: Linear.credentialsPresent
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: subTabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.subTabList
                currentIndex: subSwipeView.currentIndex
            }
        }

        // Status row: synced time + manual refresh button
        RowLayout {
            visible: Linear.credentialsPresent
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                text: Linear.refreshing ? "正在同步..."
                    : Linear.lastError ? ("⚠ " + Linear.lastError)
                    : Linear.syncedAt ? ("已同步 " + Linear.syncedAt.replace("T", " ").substring(0, 16))
                    : "等待第一次同步"
            }
            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                enabled: !Linear.refreshing && Linear.credentialsPresent
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 16
                    text: "refresh"
                    color: Appearance.colors.colOnLayer1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Linear.refresh()
                }
            }
        }

        // Content swipe view
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView {
                id: subSwipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: subTabBar.currentIndex
                clip: true
                visible: Linear.credentialsPresent

                contentChildren: [
                    inboxView.createObject(),
                    cycleView.createObject(),
                    projectsView.createObject(),
                    activityView.createObject(),
                ]
            }

            // No-credentials placeholder
            ColumnLayout {
                anchors.centerIn: parent
                visible: !Linear.credentialsPresent
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
                    text: "未配置 Linear API Key"
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: "在 Linear 网页端 Settings → API → Personal API keys 创建一个 PAT"
                }
                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            iconSize: 16
                            text: "key"
                            color: Appearance.m3colors.m3onPrimary
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onPrimary
                            text: "提供 API Key"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([
                            "bash", "-c",
                            FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/linear/save-key.sh`)
                        ])
                    }
                }
            }

            // Floating action button (create issue) — only on Inbox & Cycle tabs
            RippleButton {
                z: 10
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.fabMargins
                implicitWidth: root.fabSize
                implicitHeight: root.fabSize
                buttonRadius: root.fabSize / 2
                colBackground: Appearance.colors.colPrimary
                visible: Linear.credentialsPresent &&
                         (subSwipeView.currentIndex === 0 || subSwipeView.currentIndex === 1)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    text: "add"
                    color: Appearance.m3colors.m3onPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAddDialog = true
                }
                StyledToolTip {
                    text: "新建 issue (N)"
                }
            }

            // Add-issue dialog (block 5)
            AddIssueDialog {
                id: addDialog
                anchors.fill: parent
                visible: root.showAddDialog
                onCancelled: root.showAddDialog = false
                onSubmitted: function(body) {
                    Linear.createIssue(body)
                    root.showAddDialog = false
                }
            }
        }

        Component { id: inboxView; InboxView {} }
        Component { id: cycleView; CycleBoardView {} }
        Component { id: projectsView; ProjectsView {} }
        Component { id: activityView; ActivityView {} }
    }
}
