import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    // Full Date for this cell (undefined for the weekday-header row).
    property var cellDate: undefined
    // Externally-driven highlight (e.g. clicked day for the per-day list).
    property bool selected: false

    readonly property var dayEvents: cellDate ? GoogleCalendar.eventsByDate(cellDate) : []
    readonly property var holiday: cellDate ? GoogleCalendar.holidayForDate(cellDate) : null
    readonly property bool hasEvent: dayEvents.length > 0
    readonly property bool isHoliday: holiday !== null

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38;
    implicitHeight: 38;

    toggled: (isToday == 1) || selected
    buttonRadius: Appearance.rounding.small

    contentItem: Item {
        anchors.fill: parent

        StyledText {
            anchors.fill: parent
            text: button.day
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.weight: button.bold ? Font.DemiBold : Font.Normal
            color: (button.isToday == 1) ? Appearance.m3colors.m3onPrimary :
                button.isHoliday ? Appearance.m3colors.m3error :
                (button.isToday == 0) ? Appearance.colors.colOnLayer1 :
                Appearance.colors.colOutlineVariant

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Rectangle {
            id: dot
            visible: button.hasEvent
            width: 4
            height: 4
            radius: 2
            color: button.isHoliday ? Appearance.m3colors.m3error :
                (button.isToday == 1) ? Appearance.m3colors.m3onPrimary :
                Appearance.colors.colPrimary
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: button.isToday == -1 ? 0.5 : 1.0
        }
    }
}
