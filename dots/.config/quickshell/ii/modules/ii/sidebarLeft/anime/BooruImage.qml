import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.common.widgets
import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Button {
    id: root
    property var imageData
    property var rowHeight
    property bool manualDownload: false

    // Click anywhere on the image (except the menu button) to open the
    // fullscreen lightbox with the high-res sample.
    onClicked: {
        const fullUrl = root.imageData.file_url ?? root.imageData.sample_url ?? root.imageData.preview_url
        const sampleUrl = root.imageData.sample_url ?? fullUrl
        GlobalStates.imageLightboxData = {
            url: sampleUrl,                   // shown in the lightbox (medium-res, fast)
            fallbackUrl: root.imageData.preview_url,
            saveUrl: fullUrl,                 // saved to disk = highest available
            shareUrl: fullUrl,                // shared link = highest available
            tags: root.imageData.tags ?? "",
            fileLink: fullUrl,                // "Open original" → same as fullUrl
            referer: root.imageData.source ?? "",  // some boorus need referer to download
        }
        GlobalStates.imageLightboxOpen = true
    }
    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath
    property string fileName: decodeURIComponent((imageData.file_url).substring((imageData.file_url).lastIndexOf('/') + 1))
    property string filePath: `${root.previewDownloadPath}/${root.fileName}`
    property int maxTagStringLineLength: 50
    property real imageRadius: Appearance.rounding.small

    property bool showActions: false
    ImageDownloaderProcess {
        id: imageDownloader
        running: root.manualDownload
        filePath: root.filePath
        // For manual-download providers (danbooru / waifu.im / t.alcy.cc) prefer
        // sample_url so the cached file is high-res, not a 150px thumbnail.
        sourceUrl: root.imageData.sample_url ?? root.imageData.preview_url
        onDone: (path, width, height) => {
            imageObject.source = ""
            imageObject.source = path
            if (!modelData.width || !modelData.height) {
                modelData.width = width
                modelData.height = height
                modelData.aspect_ratio = width / height
            }
        }
    }

    StyledToolTip {
        text: `${StringUtils.wordWrap(root.imageData.tags, root.maxTagStringLineLength)}`
    }

    padding: 0
    implicitWidth: root.rowHeight * modelData.aspect_ratio
    implicitHeight: root.rowHeight

    background: Rectangle {
        implicitWidth: root.rowHeight * modelData.aspect_ratio
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        // Progressive loading: a low-res preview shows instantly, then the
        // higher-res sample fades in once it finishes downloading. Decode
        // size is doubled to account for HiDPI fractional scaling (1.25x /
        // 1.5x / 2x) so the rendered image stays sharp.
        Item {
            id: imageWrapper
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * modelData.aspect_ratio
                    height: root.rowHeight
                    radius: imageRadius
                }
            }

            StyledImage {
                id: previewImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: modelData.preview_url
                sourceSize.width: root.rowHeight * modelData.aspect_ratio
                sourceSize.height: root.rowHeight
                smooth: true
                asynchronous: true
                visible: imageObject.status !== Image.Ready
            }

            StyledImage {
                id: imageObject
                anchors.fill: parent
                width: root.rowHeight * modelData.aspect_ratio
                height: root.rowHeight
                fillMode: Image.PreserveAspectFit
                source: modelData.sample_url ?? modelData.preview_url
                // Decode at 2x logical size to stay crisp under HiDPI scaling.
                sourceSize.width: root.rowHeight * modelData.aspect_ratio * 2
                sourceSize.height: root.rowHeight * 2
                smooth: true
                mipmap: true
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        RippleButton {
            id: menuButton
            anchors.top: parent.top
            anchors.right: parent.right
            property real buttonSize: 30
            anchors.margins: Math.max(root.imageRadius - buttonSize / 2, 8)
            implicitHeight: buttonSize
            implicitWidth: buttonSize

            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
            colBackgroundHover: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.8), 0.2)
            colRipple: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.6), 0.1)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3onSurface
                text: "more_vert"
            }

            onClicked: {
                root.showActions = !root.showActions
            }
        }

        Loader {
            id: contextMenuLoader
            active: root.showActions
            anchors.top: menuButton.bottom
            anchors.right: parent.right
            anchors.margins: 8

            sourceComponent: Item {
                width: contextMenu.width
                height: contextMenu.height

                StyledRectangularShadow {
                    target: contextMenu
                }
                Rectangle {
                    id: contextMenu
                    anchors.centerIn: parent
                    opacity: root.showActions ? 1 : 0
                    visible: opacity > 0
                    radius: Appearance.rounding.small
                    color: Appearance.m3colors.m3surfaceContainer
                    implicitHeight: contextMenuColumnLayout.implicitHeight + radius * 2
                    implicitWidth: contextMenuColumnLayout.implicitWidth

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    ColumnLayout {
                        id: contextMenuColumnLayout
                        anchors.centerIn: parent
                        spacing: 0

                        MenuButton {
                            id: openFileLinkButton
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Open file link")
                            onClicked: {
                                root.showActions = false
                                Hyprland.dispatch("keyword cursor:no_warps true")
                                Qt.openUrlExternally(root.imageData.file_url)
                                Hyprland.dispatch("keyword cursor:no_warps false")
                            }
                        }
                        MenuButton {
                            id: sourceButton
                            visible: root.imageData.source && root.imageData.source.length > 0
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Go to source (%1)").arg(StringUtils.getDomain(root.imageData.source))
                            enabled: root.imageData.source && root.imageData.source.length > 0
                            onClicked: {
                                root.showActions = false
                                Hyprland.dispatch("keyword cursor:no_warps true")
                                Qt.openUrlExternally(root.imageData.source)
                                Hyprland.dispatch("keyword cursor:no_warps false")
                            }
                        }
                        MenuButton {
                            id: downloadButton
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Download")
                            onClicked: {
                                root.showActions = false;
                                const targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath;
                                Quickshell.execDetached(["bash", "-c", 
                                    `mkdir -p '${targetPath}' && curl '${root.imageData.file_url}' -o '${targetPath}/${root.fileName}' && notify-send '${Translation.tr("Download complete")}' '${root.downloadPath}/${root.fileName}' -a 'Shell'`
                                ])
                            }
                        }
                    }
                }
            }
        }
    }
}