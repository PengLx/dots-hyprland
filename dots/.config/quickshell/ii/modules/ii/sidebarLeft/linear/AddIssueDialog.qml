import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * Modal-style add-issue overlay. Sits on top of the Linear root tab,
 * dimming the background.
 *
 * Required fields: title + team
 * Optional: description, priority
 *
 * Emits `submitted(body)` with a body suitable for Linear.createIssue() or
 * `cancelled()` if the user dismisses.
 */
Item {
    id: root
    signal submitted(var body)
    signal cancelled()

    property string titleText: ""
    property string descText: ""
    property string selectedTeamId: ""
    property int selectedPriority: 0  // 0=none

    function _reset() {
        titleText = ""
        descText = ""
        if ((Linear.teams || []).length > 0) {
            selectedTeamId = Linear.teams[0].id
        }
        selectedPriority = 0
    }

    onVisibleChanged: { if (visible) _reset() }

    // Backdrop
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelled()
        }
    }

    // Dialog box
    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 380)
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        implicitHeight: dialogCol.implicitHeight + 32

        // Block clicks from passing through to the backdrop
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: dialogCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
                text: "新建 issue"
            }

            // Title
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: "标题 *"
                }
                Rectangle {
                    Layout.fillWidth: true
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    implicitHeight: 38

                    TextInput {
                        id: titleInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        clip: true
                        focus: root.visible
                        onTextChanged: root.titleText = text
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) {
                                root.cancelled()
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            // Description
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: "描述"
                }
                Rectangle {
                    Layout.fillWidth: true
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    implicitHeight: 80

                    TextEdit {
                        id: descInput
                        anchors.fill: parent
                        anchors.margins: 10
                        wrapMode: TextEdit.Wrap
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        onTextChanged: root.descText = text
                    }
                }
            }

            // Team picker
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: "团队 *"
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: Linear.teams || []
                        delegate: Rectangle {
                            required property var modelData
                            radius: Appearance.rounding.small
                            color: root.selectedTeamId === modelData.id
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2
                            implicitWidth: tlabel.implicitWidth + 20
                            implicitHeight: 28
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: modelData.color || "#888"
                                }
                                StyledText {
                                    id: tlabel
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.selectedTeamId === modelData.id
                                        ? Appearance.m3colors.m3onPrimary
                                        : Appearance.colors.colOnLayer1
                                    text: modelData.key
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedTeamId = modelData.id
                            }
                        }
                    }
                }
            }

            // Priority picker
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: "优先级"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: [
                            { value: 0, label: "无",   icon: "remove",        color: Appearance.colors.colSubtext },
                            { value: 1, label: "紧急", icon: "error",         color: "#FF5252" },
                            { value: 2, label: "高",   icon: "keyboard_double_arrow_up",   color: "#FFB74D" },
                            { value: 3, label: "中",   icon: "drag_handle",   color: Appearance.colors.colSubtext },
                            { value: 4, label: "低",   icon: "keyboard_double_arrow_down", color: "#90A4AE" },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: Appearance.rounding.small
                            color: root.selectedPriority === modelData.value
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                MaterialSymbol {
                                    iconSize: 14
                                    text: modelData.icon
                                    color: root.selectedPriority === modelData.value
                                        ? Appearance.m3colors.m3onPrimary
                                        : modelData.color
                                }
                                StyledText {
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.selectedPriority === modelData.value
                                        ? Appearance.m3colors.m3onPrimary
                                        : Appearance.colors.colOnLayer1
                                    text: modelData.label
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedPriority = modelData.value
                            }
                        }
                    }
                }
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        text: "取消"
                        leftPadding: 16; rightPadding: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }
                }

                RippleButton {
                    enabled: root.titleText.length > 0 && root.selectedTeamId.length > 0
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: parent.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "创建"
                        leftPadding: 16; rightPadding: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.enabled
                        cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const body = {
                                teamId: root.selectedTeamId,
                                title: root.titleText,
                            }
                            if (root.descText) body.description = root.descText
                            if (root.selectedPriority !== 0) body.priority = root.selectedPriority
                            root.submitted(body)
                        }
                    }
                }
            }
        }
    }
}
