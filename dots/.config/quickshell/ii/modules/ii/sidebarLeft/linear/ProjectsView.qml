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

    property string expandedProjectId: ""

    function _issuesForProject(projectId) {
        const out = []
        const arr = Linear.cycleIssues || []
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].project && arr[i].project.id === projectId) out.push(arr[i])
        }
        // Also include myIssues that match (in case sync window doesn't overlap)
        const my = Linear.myIssues || []
        const seen = {}
        for (var k = 0; k < out.length; k++) seen[out[k].id] = true
        for (var j = 0; j < my.length; j++) {
            if (my[j].project && my[j].project.id === projectId && !seen[my[j].id]) {
                out.push(my[j])
                seen[my[j].id] = true
            }
        }
        return out
    }

    StateMenu {
        id: stateMenu
    }

    StyledListView {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6
        clip: true
        model: Linear.projects

        delegate: Rectangle {
            required property var modelData
            id: projectCard
            width: ListView.view.width
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            implicitHeight: cardCol.implicitHeight + 16

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                // Header row
                MouseArea {
                    Layout.fillWidth: true
                    implicitHeight: headerRow.implicitHeight
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.expandedProjectId = (root.expandedProjectId === projectCard.modelData.id)
                            ? "" : projectCard.modelData.id
                    }

                    RowLayout {
                        id: headerRow
                        anchors.fill: parent
                        spacing: 8

                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: projectCard.modelData.color || "#888"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                text: projectCard.modelData.name
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: !!projectCard.modelData.target_date
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: "目标 " + (projectCard.modelData.target_date || "")
                            }
                        }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Math.round(((projectCard.modelData.progress || 0) * 100)) + "%"
                        }
                        MaterialSymbol {
                            iconSize: 18
                            text: root.expandedProjectId === projectCard.modelData.id ? "expand_less" : "expand_more"
                            color: Appearance.colors.colSubtext
                        }

                        RippleButton {
                            implicitWidth: 28; implicitHeight: 28
                            buttonRadius: Appearance.rounding.small
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 14
                                text: "open_in_new"
                                color: Appearance.colors.colOnLayer1
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (projectCard.modelData.url) Quickshell.execDetached(["xdg-open", projectCard.modelData.url])
                            }
                        }
                    }
                }

                // Progress bar
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Appearance.colors.colLayer1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (projectCard.modelData.progress || 0)
                        radius: 2
                        color: projectCard.modelData.color || Appearance.colors.colPrimary
                        Behavior on width {
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // Milestones (compact)
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: projectCard.modelData.milestones && projectCard.modelData.milestones.length > 0
                    Repeater {
                        model: projectCard.modelData.milestones || []
                        delegate: Rectangle {
                            required property var modelData
                            radius: 4
                            color: Appearance.colors.colLayer1
                            implicitWidth: msText.implicitWidth + 12
                            implicitHeight: 20
                            StyledText {
                                id: msText
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: (modelData.name || "milestone") + (modelData.target_date ? (" · " + modelData.target_date) : "")
                            }
                        }
                    }
                }

                // Expanded: child issues
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.expandedProjectId === projectCard.modelData.id
                    spacing: 4

                    Repeater {
                        model: visible ? root._issuesForProject(projectCard.modelData.id) : []
                        delegate: IssueCard {
                            required property var modelData
                            issue: modelData
                            compact: true
                            onStateMenuRequested: function(it, x, y) {
                                const pos = mapToItem(root, x, y)
                                stateMenu.openFor(it, pos.x, pos.y)
                            }
                        }
                    }
                    StyledText {
                        visible: root.expandedProjectId === projectCard.modelData.id &&
                                 root._issuesForProject(projectCard.modelData.id).length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: "(没有缓存到的 issue;查看 Linear 网页端)"
                    }
                }
            }
        }
    }

    PagePlaceholder {
        z: 2
        anchors.centerIn: parent
        shown: (Linear.projects || []).length === 0 && Linear.credentialsPresent && Linear.syncedAt.length > 0
        icon: "folder_open"
        title: "没有 projects"
        description: "你不是任何 project 的成员或负责人"
        shape: MaterialShape.Shape.Bun
    }
}
