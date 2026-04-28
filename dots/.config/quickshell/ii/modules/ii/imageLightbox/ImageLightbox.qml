import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Fullscreen lightbox/zoom overlay.
 *
 * Open: set GlobalStates.imageLightboxData = { url, fallbackUrl?, tags?,
 *       source?, fileLink? } then GlobalStates.imageLightboxOpen = true.
 * Close: click the backdrop, press Esc, or click the close button.
 *
 * Uses WlrLayer.Overlay so it draws above all other panels (sidebar, bar,
 * dock). Backdrop is a semi-transparent black; the image is centered with
 * 90% of viewport size and PreserveAspectFit. While the high-res `url` is
 * loading, `fallbackUrl` (typically the small preview already cached by the
 * sidebar) is shown to avoid a blank flash.
 */
Scope {
    id: root

    Loader {
        id: lightboxLoader
        active: GlobalStates.imageLightboxOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            visible: monitorIsFocused
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:imageLightbox"
            WlrLayershell.layer: WlrLayer.Overlay
            // OnDemand acts as Exclusive on Hyprland 0.49+, so Esc reaches
            // Keys.onPressed without needing a prior click. We deliberately
            // do NOT register with GlobalFocusGrab — that lumps all
            // dismissables together so closing the lightbox would cascade
            // into the sidebar, which we don't want.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            // Register as a "persistent" focus-grab participant: clicks on
            // the lightbox don't count as "outside" the sidebar (so the
            // sidebar stays alive), but the lightbox itself isn't closed
            // by GlobalFocusGrab.dismiss().
            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(panelWindow)
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(panelWindow)
            }

            // Backdrop — closes on click
            Rectangle {
                id: backdrop
                anchors.fill: parent
                color: "#cc000000"
                opacity: GlobalStates.imageLightboxOpen ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: GlobalStates.imageLightboxOpen = false
                }
            }

            // Esc / +-0 / arrows
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.imageLightboxOpen = false
                        event.accepted = true
                    } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                        imageContainer.zoomAt(imageContainer.width/2, imageContainer.height/2, 1.25)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Minus) {
                        imageContainer.zoomAt(imageContainer.width/2, imageContainer.height/2, 1/1.25)
                        event.accepted = true
                    } else if (event.key === Qt.Key_0) {
                        imageContainer.resetZoom()
                        event.accepted = true
                    }
                }
            }

            // Image container
            Item {
                id: imageContainer
                anchors.centerIn: parent
                width: parent.width * 0.9
                height: parent.height * 0.9
                opacity: GlobalStates.imageLightboxOpen ? 1 : 0
                // Note: not animating Item.scale here — we use that property
                // for zoom now. Open/close is just opacity.
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                // Zoom + pan state
                property real zoom: 1.0
                property real panX: 0
                property real panY: 0
                readonly property real minZoom: 0.5
                readonly property real maxZoom: 8.0

                function resetZoom() {
                    zoom = 1.0
                    panX = 0
                    panY = 0
                }

                // Mouse-anchored zoom: keep the logical pixel under the
                // cursor at the same viewport point after the zoom change.
                function zoomAt(localX, localY, factor) {
                    const oldZoom = zoom
                    const newZoom = Math.max(minZoom, Math.min(maxZoom, oldZoom * factor))
                    if (newZoom === oldZoom) return
                    const cx = width / 2 + panX
                    const cy = height / 2 + panY
                    const ratio = 1 - newZoom / oldZoom
                    panX += (localX - cx) * ratio
                    panY += (localY - cy) * ratio
                    zoom = newZoom
                }

                Behavior on zoom { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on panX { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
                Behavior on panY { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

                // Reset zoom whenever a new image is shown.
                Connections {
                    target: GlobalStates
                    function onImageLightboxDataChanged() { imageContainer.resetZoom() }
                    function onImageLightboxOpenChanged() {
                        if (GlobalStates.imageLightboxOpen) imageContainer.resetZoom()
                    }
                }

                // Zoom/pan area — clips so the zoomed image stays inside the
                // 90% container, doesn't bleed onto the backdrop.
                Item {
                    id: zoomArea
                    anchors.fill: parent
                    clip: true

                    Image {
                        id: placeholderImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: GlobalStates.imageLightboxData?.fallbackUrl ?? ""
                        visible: hiResImage.status !== Image.Ready
                        smooth: true
                        asynchronous: true
                        sourceSize.width: width
                        sourceSize.height: height
                        transform: [
                            Scale {
                                origin.x: placeholderImage.width / 2
                                origin.y: placeholderImage.height / 2
                                xScale: imageContainer.zoom
                                yScale: imageContainer.zoom
                            },
                            Translate { x: imageContainer.panX; y: imageContainer.panY }
                        ]
                    }

                    Image {
                        id: hiResImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: GlobalStates.imageLightboxData?.url ?? ""
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: true
                        // Don't cap sourceSize — let the image decode at full
                        // resolution so zoomed-in pixels stay crisp. Memory
                        // cost is one image's full decode (~10-60MB for
                        // typical anime). Worth it for the use case.
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        transform: [
                            Scale {
                                origin.x: hiResImage.width / 2
                                origin.y: hiResImage.height / 2
                                xScale: imageContainer.zoom
                                yScale: imageContainer.zoom
                            },
                            Translate { x: imageContainer.panX; y: imageContainer.panY }
                        ]
                    }

                    MouseArea {
                        id: zoomMouseArea
                        anchors.fill: parent
                        property real lastX: 0
                        property real lastY: 0
                        property bool dragging: false

                        cursorShape: imageContainer.zoom > 1.001
                            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                            : Qt.ArrowCursor

                        onPressed: function(mouse) {
                            if (imageContainer.zoom > 1.001) {
                                lastX = mouse.x; lastY = mouse.y
                                dragging = true
                                mouse.accepted = true
                            }
                        }
                        onReleased: dragging = false
                        onPositionChanged: function(mouse) {
                            if (dragging) {
                                imageContainer.panX += mouse.x - lastX
                                imageContainer.panY += mouse.y - lastY
                                lastX = mouse.x; lastY = mouse.y
                            }
                        }
                        onDoubleClicked: imageContainer.resetZoom()
                        onWheel: function(wheel) {
                            const factor = wheel.angleDelta.y > 0 ? 1.18 : 1 / 1.18
                            imageContainer.zoomAt(wheel.x, wheel.y, factor)
                            wheel.accepted = true
                        }
                    }
                }

                // Zoom indicator + reset (top-left, shown only when zoomed)
                Rectangle {
                    z: 10
                    visible: Math.abs(imageContainer.zoom - 1.0) > 0.01
                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: 12
                    }
                    radius: Appearance.rounding.small
                    color: "#80000000"
                    implicitWidth: zoomBadgeRow.implicitWidth + 12
                    implicitHeight: 32

                    RowLayout {
                        id: zoomBadgeRow
                        anchors.centerIn: parent
                        spacing: 6

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: "white"
                            text: Math.round(imageContainer.zoom * 100) + "%"
                        }
                        RippleButton {
                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 14
                                text: "fit_screen"
                                color: "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: imageContainer.resetZoom()
                            }
                            StyledToolTip { text: "重置缩放 (0)" }
                        }
                    }
                }

                // Loading indicator
                MaterialLoadingIndicator {
                    visible: hiResImage.status === Image.Loading
                    anchors {
                        bottom: parent.bottom
                        right: parent.right
                        margins: 16
                    }
                    loading: visible
                }

                // Top-right close button
                RippleButton {
                    anchors {
                        top: parent.top
                        right: parent.right
                        margins: 12
                    }
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: "#80000000"
                    colBackgroundHover: "#a0000000"
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        text: "close"
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.imageLightboxOpen = false
                    }
                }

                property bool showShareMenu: false

                // Share menu (over footer when active)
                Rectangle {
                    z: 5
                    anchors {
                        bottom: footer.top
                        right: footer.right
                        bottomMargin: 8
                    }
                    visible: imageContainer.showShareMenu
                    implicitWidth: shareMenuCol.implicitWidth + 24
                    implicitHeight: shareMenuCol.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: "#dd000000"
                    border.width: 1
                    border.color: "#33ffffff"

                    ColumnLayout {
                        id: shareMenuCol
                        anchors.centerIn: parent
                        spacing: 4

                        // Telegram
                        Rectangle {
                            Layout.fillWidth: true
                            implicitWidth: 200
                            implicitHeight: 36
                            radius: Appearance.rounding.small
                            color: shareTgArea.containsMouse ? "#22ffffff" : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                MaterialSymbol { iconSize: 18; text: "send"; color: "white" }
                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: "white"
                                    text: "分享到 Telegram"
                                }
                            }
                            MouseArea {
                                id: shareTgArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const u = GlobalStates.imageLightboxData?.shareUrl
                                        ?? GlobalStates.imageLightboxData?.fileLink
                                        ?? GlobalStates.imageLightboxData?.url ?? ""
                                    if (u) {
                                        // tg:// scheme is handled by Telegram Desktop directly
                                        // (registered MIME: x-scheme-handler/tg). Falls back to
                                        // the t.me web share if no native handler.
                                        Quickshell.execDetached([
                                            "xdg-open",
                                            "tg://msg_url?url=" + encodeURIComponent(u)
                                        ])
                                    }
                                    imageContainer.showShareMenu = false
                                    GlobalStates.imageLightboxOpen = false
                                    // Also dismiss the sidebar — the user is moving to Telegram.
                                    // Without this, the sidebar's focus grab eats the first
                                    // click on the Telegram window.
                                    GlobalStates.sidebarLeftOpen = false
                                }
                            }
                        }

                        // Copy link
                        Rectangle {
                            Layout.fillWidth: true
                            implicitWidth: 200
                            implicitHeight: 36
                            radius: Appearance.rounding.small
                            color: copyArea.containsMouse ? "#22ffffff" : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                MaterialSymbol { iconSize: 18; text: "link"; color: "white" }
                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: "white"
                                    text: "复制链接"
                                }
                            }
                            MouseArea {
                                id: copyArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const u = GlobalStates.imageLightboxData?.shareUrl
                                        ?? GlobalStates.imageLightboxData?.fileLink
                                        ?? GlobalStates.imageLightboxData?.url ?? ""
                                    if (u) {
                                        Quickshell.execDetached([
                                            "bash", "-c",
                                            "printf '%s' \"$1\" | wl-copy && notify-send -a '图片' '已复制链接' \"$1\"",
                                            "_", u
                                        ])
                                    }
                                    imageContainer.showShareMenu = false
                                }
                            }
                        }
                    }
                }

                // Footer: tags + save + share + open-in-browser
                Rectangle {
                    id: footer
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                        leftMargin: 24
                        rightMargin: 24
                        bottomMargin: 24
                    }
                    height: footerRow.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: "#80000000"

                    RowLayout {
                        id: footerRow
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: "white"
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            text: GlobalStates.imageLightboxData?.tags ?? ""
                        }

                        // Save
                        RippleButton {
                            implicitWidth: 32; implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "download"
                                color: "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const u = GlobalStates.imageLightboxData?.saveUrl
                                        ?? GlobalStates.imageLightboxData?.fileLink
                                        ?? GlobalStates.imageLightboxData?.url ?? ""
                                    if (!u) return
                                    const ref = GlobalStates.imageLightboxData?.referer ?? ""
                                    Quickshell.execDetached([
                                        FileUtils.trimFileProtocol(`${Directories.home}/Projects/end4-staging/dots-hyprland/personal/booru/save-image.sh`),
                                        u, ref
                                    ])
                                }
                            }
                            StyledToolTip { text: "保存到 ~/Pictures/Anime/saved/" }
                        }

                        // Share
                        RippleButton {
                            implicitWidth: 32; implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: imageContainer.showShareMenu ? "#33ffffff" : "transparent"
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "share"
                                color: "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: imageContainer.showShareMenu = !imageContainer.showShareMenu
                            }
                            StyledToolTip { text: "分享" }
                        }

                        // Open original
                        RippleButton {
                            visible: !!GlobalStates.imageLightboxData?.fileLink
                            implicitWidth: 32; implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 18
                                text: "open_in_new"
                                color: "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (GlobalStates.imageLightboxData?.fileLink) {
                                        Quickshell.execDetached(["xdg-open", GlobalStates.imageLightboxData.fileLink])
                                    }
                                }
                            }
                            StyledToolTip { text: "在浏览器打开原图" }
                        }
                    }
                }
            }
        }
    }
}
