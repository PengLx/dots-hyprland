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
            // Exclusive keyboard so Esc fires reliably without a click first.
            // Intentionally NOT registered with GlobalFocusGrab — that grabs
            // all dismissables together, so dismissing the lightbox would
            // also close the sidebar that opened it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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

            // Esc / arrow keys
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.imageLightboxOpen = false
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
                scale: GlobalStates.imageLightboxOpen ? 1.0 : 0.96
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                // Block backdrop clicks from bubbling
                MouseArea { anchors.fill: parent; onClicked: {} }

                // Low-res placeholder (instant)
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
                }

                // Hi-res target image
                Image {
                    id: hiResImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: GlobalStates.imageLightboxData?.url ?? ""
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    cache: true
                    // Decode to a generous size so zooming/HiDPI stays sharp
                    sourceSize.width: panelWindow.width
                    sourceSize.height: panelWindow.height
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
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
