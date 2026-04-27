import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    anchors.topMargin: 10
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property var selectedDate: new Date()
    readonly property var selectedEvents: GoogleCalendar.eventsByDate(selectedDate)

    property bool showAddDialog: false
    property int dialogMargins: 20
    property int fabSize: 48
    property int fabMargins: 14

    function _sameDay(a, b) {
        if (!a || !b) return false
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function _formatTime(iso) {
        if (!iso) return ""
        const d = new Date(iso)
        const hh = d.getHours() < 10 ? "0" + d.getHours() : "" + d.getHours()
        const mm = d.getMinutes() < 10 ? "0" + d.getMinutes() : "" + d.getMinutes()
        return hh + ":" + mm
    }

    function _formatRange(ev) {
        if (ev.all_day) return Translation.tr("All day")
        const start = _formatTime(ev.start)
        const end = _formatTime(ev.end)
        if (!end || end === start) return start
        return start + " – " + end
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) monthShift++;
            else if (event.key === Qt.Key_PageUp) monthShift--;
            event.accepted = true;
        }
        else if (event.key === Qt.Key_N && event.modifiers === Qt.NoModifier) {
            root.showAddDialog = true
            event.accepted = true
        }
        else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true
        }
    }

    // Whole widget scrolls vertically; switch month via the chevrons or
    // PageUp / PageDown. Wheel = scroll content (default ScrollView behavior).
    ScrollView {
        anchors.fill: parent
        anchors.topMargin: 10
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            spacing: 5

            // Header row with month label + chevrons.
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                CalendarHeaderButton {
                    clip: true
                    buttonText: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                    tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                    downAction: () => {
                        monthShift = 0;
                        selectedDate = new Date();
                    }
                }
                Item { Layout.fillWidth: true; Layout.fillHeight: false }
                CalendarHeaderButton {
                    forceCircle: true
                    downAction: () => { monthShift--; }
                    contentItem: MaterialSymbol {
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.larger
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colOnLayer1
                    }
                }
                CalendarHeaderButton {
                    forceCircle: true
                    downAction: () => { monthShift++; }
                    contentItem: MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // Week days row.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: 5
                Repeater {
                    model: CalendarLayout.weekDays
                    delegate: CalendarDayButton {
                        day: Translation.tr(modelData.day)
                        isToday: modelData.today
                        bold: true
                        enabled: false
                    }
                }
            }

            // Day grid — clicking a cell selects the day for the list below.
            Repeater {
                model: 6
                delegate: RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: false
                    spacing: 5
                    Repeater {
                        model: Array(7).fill(modelData)
                        delegate: CalendarDayButton {
                            day: calendarLayout[modelData][index].day
                            isToday: calendarLayout[modelData][index].today
                            cellDate: calendarLayout[modelData][index].date
                            selected: root._sameDay(cellDate, root.selectedDate)
                            onClicked: root.selectedDate = cellDate
                        }
                    }
                }
            }

            // Events block — flows in the same scroll surface; user reaches
            // it by scrolling down.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedDate
                            ? root.selectedDate.toLocaleDateString(Qt.locale(), "M月d日 dddd")
                            : ""
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        visible: GoogleCalendar.refreshing
                        text: Translation.tr("syncing…")
                        color: Appearance.m3colors.m3outline
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                StyledText {
                    visible: root.selectedEvents.length === 0
                    Layout.fillWidth: true
                    text: GoogleCalendar.syncedAt.length === 0
                        ? Translation.tr("Run personal/gcal/login.py to enable Google Calendar")
                        : Translation.tr("No events")
                    color: Appearance.m3colors.m3outline
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: root.selectedEvents
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        color: Appearance.colors.colLayer2
                        radius: Appearance.rounding.verysmall
                        implicitHeight: eventRow.implicitHeight + 10

                        RowLayout {
                            id: eventRow
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.topMargin: 5
                            anchors.bottomMargin: 5
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 3
                                Layout.fillHeight: true
                                radius: 1.5
                                color: modelData.calendar_color && !modelData.is_holiday
                                    ? modelData.calendar_color
                                    : (modelData.is_holiday
                                        ? Appearance.m3colors.m3error
                                        : Appearance.colors.colPrimary)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.summary || ""
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const range = root._formatRange(modelData)
                                        const cal = modelData.calendar_summary || ""
                                        if (cal && range) return range + " · " + cal
                                        return range || cal
                                    }
                                    color: Appearance.m3colors.m3outline
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // + FAB to add an event for the selected day.
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        onClicked: root.showAddDialog = true
        iconText: "event"
    }

    // Add-event dialog (scrim + Material card).
    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                addInput.text = ""
                fabButton.focus = true
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
            }
        }

        Rectangle {
            id: addDialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: addDialogColumn.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            function commit() {
                if (addInput.text.length > 0 && root.selectedDate) {
                    GoogleCalendar.addAllDayEvent(addInput.text, root.selectedDate)
                    addInput.text = ""
                    root.showAddDialog = false
                }
            }

            ColumnLayout {
                id: addDialogColumn
                anchors.fill: parent
                spacing: 16

                StyledText {
                    Layout.topMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add event")
                }

                StyledText {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    color: Appearance.m3colors.m3outline
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.selectedDate
                        ? Translation.tr("All-day on") + " " + root.selectedDate.toLocaleDateString(Qt.locale(), "yyyy-MM-dd dddd")
                        : ""
                }

                TextField {
                    id: addInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Event title")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showAddDialog
                    onAccepted: addDialog.commit()

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: addInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: addInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }
                }

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: addInput.text.length > 0
                        onClicked: addDialog.commit()
                    }
                }
            }
        }
    }
}
