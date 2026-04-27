import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    anchors.topMargin: 10
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    // Day whose events are shown in the list below the grid. Defaults to today.
    property var selectedDate: new Date()
    readonly property var selectedEvents: GoogleCalendar.eventsByDate(selectedDate)

    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 10 * 2

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
            if (event.key === Qt.Key_PageDown) {
                monthShift++;
            } else if (event.key === Qt.Key_PageUp) {
                monthShift--;
            }
            event.accepted = true;
        }
    }
    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
        }
    }

    ColumnLayout {
        id: calendarColumn
        anchors.centerIn: parent
        spacing: 5

        // Calendar header
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
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
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

        // Week days row
        RowLayout {
            id: weekDaysRow
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

        // Real week rows — clicking a cell selects the day for the list below.
        Repeater {
            id: calendarRows
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
                        onClicked: {
                            root.selectedDate = cellDate
                        }
                    }
                }
            }
        }

        // Event list for `selectedDate`. Compact, scrolls if there are many.
        ColumnLayout {
            id: eventsBlock
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 4
            visible: root.selectedDate !== undefined

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

            // Empty state.
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

            // Event rows.
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

                        // Color bar — uses the calendar's background color
                        // when present, falling back to error red for holidays
                        // and primary for everything else.
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
