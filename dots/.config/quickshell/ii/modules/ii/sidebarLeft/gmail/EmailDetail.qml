import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

/**
 * Modal email detail view. Sits on top of the GmailTab; when shown,
 * lazy-loads the body via Gmail.fetchBody(msgId) and renders it as
 * plain text (mutate.py's HTML→text fallback handles HTML emails).
 *
 * Required: pass the message via `setMessage(msg)`.
 *
 * Closes on Esc or close button.
 */
Item {
    id: root
    signal closed()

    property var currentMessage: null
    property string bodyText: ""
    property bool loading: false

    // Reactive look-up of the currently-open message in Gmail's live list,
    // so the action buttons (and any other UI bound to is_unread/labels)
    // reflect the post-mutation state instead of the snapshot taken on open.
    property var liveMessage: {
        if (!currentMessage) return null
        const arr = Gmail.messages || []
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id === currentMessage.id) return arr[i]
        }
        return currentMessage
    }
    readonly property bool currentIsUnread: liveMessage ? !!liveMessage.is_unread : false

    function setMessage(msg) {
        if (!msg) return
        currentMessage = msg
        bodyText = ""
        loading = true
        Gmail.fetchBody(msg.id)
        // If it was unread, mark it read once we open it (Gmail web semantics).
        if (msg.is_unread) {
            Gmail.markRead(msg.id)
        }
    }

    Connections {
        target: Gmail
        function onBodyReady(msgId, path) {
            if (!root.currentMessage || root.currentMessage.id !== msgId) return
            root.loading = false
            // Read the cached body file
            bodyReader.path = Qt.resolvedUrl(path)
            bodyReader.reload()
        }
    }

    FileView {
        id: bodyReader
        onLoaded: {
            root.bodyText = bodyReader.text() || ""
        }
        onLoadFailed: {
            root.bodyText = "(无法读取邮件正文)"
        }
    }

    // Backdrop — fully opaque so the inbox underneath doesn't bleed through
    // when the user has the global "透明度" toggle on (which makes
    // colLayer1 semi-transparent).
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3background
        MouseArea {
            anchors.fill: parent
            onClicked: root.closed()
        }
    }

    // Detail panel — m3surfaceContainer is a hard-coded opaque tone, so it
    // won't go translucent when the user has 透明度 enabled.
    Rectangle {
        id: panel
        anchors.fill: parent
        anchors.margins: 6
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainer

        // Eat clicks so they don't bubble to the backdrop
        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
            anchors.fill: parent
            focus: root.visible
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.closed()
                    event.accepted = true
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header: subject + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.WordWrap
                    text: root.currentMessage ? (root.currentMessage.subject || "(无主题)") : ""
                }
                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 18
                        text: "close"
                        color: Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closed()
                    }
                }
            }

            // Sender + time
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                        text: root.currentMessage && root.currentMessage.from
                              ? (root.currentMessage.from.name || root.currentMessage.from.email || "")
                              : ""
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        text: root.currentMessage && root.currentMessage.from
                              ? (root.currentMessage.from.email || "")
                              : ""
                    }
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.currentMessage ? (root.currentMessage.date_header || "") : ""
                }
            }

            // Action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    leftPadding: 10
                    rightPadding: 10
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            iconSize: 14
                            // currentIsUnread tracks the live Gmail.messages
                            // entry, so toggling reflects what the next
                            // action will do, not the snapshot from open.
                            text: root.currentIsUnread ? "mark_email_read" : "mark_email_unread"
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            text: root.currentIsUnread ? "标已读" : "标未读"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.currentMessage) return
                            if (root.currentIsUnread) Gmail.markRead(root.currentMessage.id)
                            else Gmail.markUnread(root.currentMessage.id)
                        }
                    }
                }
                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    leftPadding: 10
                    rightPadding: 10
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            iconSize: 14
                            text: "archive"
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            text: "归档"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.currentMessage) return
                            Gmail.archive(root.currentMessage.id)
                            root.closed()
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    leftPadding: 10
                    rightPadding: 10
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            iconSize: 14
                            text: "open_in_new"
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            text: "网页打开"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.currentMessage) return
                            const url = "https://mail.google.com/mail/u/0/#inbox/" + root.currentMessage.id
                            Quickshell.execDetached(["xdg-open", url])
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colLayer2
            }

            // Body — Flickable + Text gives us reliable wrap-to-width that
            // ScrollView fights with (its contentItem can exceed the
            // viewport, so width: parent.width grew unbounded).
            Flickable {
                id: bodyFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyText.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds

                StyledText {
                    id: bodyText
                    width: bodyFlick.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    text: root.loading
                          ? "正在加载邮件正文..."
                          : (root.bodyText || (root.currentMessage ? root.currentMessage.snippet : ""))
                }
            }
        }
    }
}
