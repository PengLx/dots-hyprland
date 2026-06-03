import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * Bar widget that shows the current synced-lyric line for whichever
 * track is playing. Hides itself entirely (zero width, not visible) when
 * the active track has no lyrics or when nothing is playing.
 *
 * Long lines crossfade in/out at the boundary so the change isn't
 * jarring; the text itself elides on the right when it doesn't fit.
 */
Item {
    id: root

    readonly property bool _shouldShow: Lyrics.hasLyrics && Lyrics.currentLine.length > 0

    visible: _shouldShow
    // Now that we live in the right section (just left of the clock,
    // before the tray icons) there's a lot more horizontal real estate
    // available; let lines run up to ~480px before eliding.
    implicitWidth: _shouldShow ? Math.min(480, lyricText.implicitWidth + 16) : 0
    implicitHeight: lyricText.implicitHeight + 6

    Behavior on implicitWidth {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
        visible: false  // background off by default; uncomment if you want a chip look
    }

    StyledText {
        id: lyricText
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        font.pixelSize: Appearance.font.pixelSize.normal
        color: Appearance.colors.colOnLayer1
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
        text: Lyrics.currentLine

        // Soft fade-in on every line change; makes line transitions feel
        // synced with playback rather than abrupt.
        opacity: Lyrics.currentLine.length > 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    StyledToolTip {
        // Long lines elide; tooltip shows the full line plus the next one
        // queued, useful when the bar is narrow.
        text: Lyrics.nextLine.length > 0
            ? `${Lyrics.currentLine}\n→ ${Lyrics.nextLine}`
            : Lyrics.currentLine
    }
}
