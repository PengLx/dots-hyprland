import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property var teamsWithCycle: Linear.teamsWithActiveCycle()
    property string selectedTeamId: ""
    property var board: null

    function _selectFirstTeamIfNeeded() {
        if (!selectedTeamId && teamsWithCycle.length > 0) {
            selectedTeamId = teamsWithCycle[0].id
        }
        // If selected team disappears, reset to first
        if (selectedTeamId && !teamsWithCycle.find(t => t.id === selectedTeamId)) {
            selectedTeamId = teamsWithCycle.length > 0 ? teamsWithCycle[0].id : ""
        }
    }

    function _refresh() {
        _selectFirstTeamIfNeeded()
        root.board = selectedTeamId ? Linear.cycleBoardForTeam(selectedTeamId) : null
    }

    Component.onCompleted: _refresh()

    Connections {
        target: Linear
        function onTeamsChanged() { root.teamsWithCycle = Linear.teamsWithActiveCycle(); root._refresh() }
        function onCycleIssuesChanged() { root._refresh() }
    }

    onSelectedTeamIdChanged: _refresh()

    StateMenu {
        id: stateMenu
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // Team selector + cycle info
        RowLayout {
            visible: root.teamsWithCycle.length > 0
            Layout.fillWidth: true
            spacing: 6

            // Team chip dropdown — simple cycle through if multiple
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 6

                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: (root.board && root.board.team && root.board.team.color) || "#888"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: root.board && root.board.team
                            ? (root.board.team.name + "  ·  Cycle " + (root.board.cycle.number || "?"))
                            : "无活跃 cycle"
                    }
                    MaterialSymbol {
                        visible: root.teamsWithCycle.length > 1
                        iconSize: 18
                        text: "expand_more"
                        color: Appearance.colors.colSubtext
                    }
                }

                MouseArea {
                    visible: root.teamsWithCycle.length > 1
                    enabled: root.teamsWithCycle.length > 1
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: teamMenu.popup()
                }

                Menu {
                    id: teamMenu
                    Repeater {
                        model: root.teamsWithCycle
                        delegate: MenuItem {
                            required property var modelData
                            text: modelData.name + "  ·  Cycle " + (modelData.active_cycle ? modelData.active_cycle.number : "")
                            onTriggered: root.selectedTeamId = modelData.id
                        }
                    }
                }
            }
        }

        // Cycle progress bar
        Rectangle {
            visible: root.board && root.board.cycle
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: Appearance.colors.colLayer2

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * (root.board && root.board.cycle ? (root.board.cycle.progress || 0) : 0)
                radius: 2
                color: (root.board && root.board.team && root.board.team.color) || Appearance.colors.colPrimary

                Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
            }
        }

        // Three columns
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            visible: !!root.board

            Repeater {
                model: [
                    { key: "todo",  title: "Todo",        types: ["unstarted", "backlog", "triage"] },
                    { key: "doing", title: "In Progress", types: ["started"] },
                    { key: "done",  title: "Done",        types: ["completed"] },
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    function _columnIssues() {
                        if (!root.board) return []
                        const out = []
                        for (var i = 0; i < modelData.types.length; i++) {
                            const t = modelData.types[i]
                            const arr = root.board.byStateType[t] || []
                            for (var j = 0; j < arr.length; j++) out.push(arr[j])
                        }
                        return out
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                            text: modelData.title
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: "" + _columnIssues().length
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        StyledListView {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4
                            clip: true
                            model: _columnIssues()
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
                    }
                }
            }
        }

    }

    PagePlaceholder {
        z: 2
        anchors.centerIn: parent
        shown: root.teamsWithCycle.length === 0 && Linear.credentialsPresent && Linear.syncedAt.length > 0
        icon: "view_kanban"
        title: "无活跃 cycle"
        description: "你所在的 team 当前没有 active cycle"
        shape: MaterialShape.Shape.Bun
    }
}
