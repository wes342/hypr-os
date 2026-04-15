import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: config.bg

    property string accent: config.accent
    property string accentDim: config.accent_dim
    property string fg: config.fg
    property string fgDim: config.fg_dim
    property string bg: config.bg
    property string bgHighlight: config.bg_highlight
    property string uiFont: config.font

    // ── Background wallpaper ──
    Image {
        id: wallpaper
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        visible: source != ""
        asynchronous: true
        smooth: true
    }

    // Dim overlay for readability
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.5
    }

    // ── Centered login card ──
    Rectangle {
        id: card
        width: 420
        anchors.centerIn: parent
        radius: 14
        color: Qt.rgba(
            parseInt(root.bg.substr(1, 2), 16) / 255,
            parseInt(root.bg.substr(3, 2), 16) / 255,
            parseInt(root.bg.substr(5, 2), 16) / 255,
            0.88
        )
        border.width: 2
        border.color: root.accentDim
        implicitHeight: cardColumn.implicitHeight + 56

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 28
            spacing: 18

            Text {
                text: "hypr-os"
                color: root.fgDim
                font.family: root.uiFont
                font.pixelSize: 13
                Layout.alignment: Qt.AlignHCenter
            }

            ComboBox {
                id: userBox
                Layout.fillWidth: true
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
                font.family: root.uiFont
                font.pixelSize: 15

                background: Rectangle {
                    color: root.bgHighlight
                    radius: 8
                }
                contentItem: Text {
                    leftPadding: 14
                    rightPadding: 32
                    text: userBox.displayText
                    font: userBox.font
                    color: root.fg
                    verticalAlignment: Text.AlignVCenter
                }
                popup.background: Rectangle {
                    color: root.bgHighlight
                    radius: 8
                    border.color: root.accentDim
                    border.width: 1
                }
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "Password"
                font.family: root.uiFont
                font.pixelSize: 15
                color: root.fg
                placeholderTextColor: root.fgDim
                leftPadding: 14
                rightPadding: 14
                topPadding: 10
                bottomPadding: 10

                background: Rectangle {
                    color: root.bgHighlight
                    radius: 8
                    border.width: 1
                    border.color: passwordField.activeFocus ? root.accent : "transparent"
                }

                Keys.onReturnPressed: loginButton.clicked()
                Keys.onEnterPressed: loginButton.clicked()
                focus: true
            }

            Button {
                id: loginButton
                Layout.fillWidth: true
                font.family: root.uiFont
                font.pixelSize: 15
                font.bold: true

                background: Rectangle {
                    color: loginButton.pressed ? root.accentDim : root.accent
                    radius: 8
                }
                contentItem: Text {
                    text: "Sign in"
                    color: root.bg
                    font: loginButton.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: sddm.login(userBox.currentText, passwordField.text, sessionBox.currentIndex)
            }

            // Session selector
            ComboBox {
                id: sessionBox
                Layout.fillWidth: true
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
                font.family: root.uiFont
                font.pixelSize: 13

                background: Rectangle {
                    color: "transparent"
                    border.color: root.accentDim
                    border.width: 1
                    radius: 6
                }
                contentItem: Text {
                    leftPadding: 12
                    rightPadding: 30
                    text: "Session: " + sessionBox.displayText
                    font: sessionBox.font
                    color: root.fgDim
                    verticalAlignment: Text.AlignVCenter
                }
                popup.background: Rectangle {
                    color: root.bgHighlight
                    radius: 8
                }
            }

            Text {
                id: errorLabel
                Layout.alignment: Qt.AlignHCenter
                color: "#e06c75"
                font.family: root.uiFont
                font.pixelSize: 12
                text: ""
                opacity: text == "" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }
    }

    // ── Power controls (bottom right) ──
    Row {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 24
        spacing: 18

        component PowerIcon: Text {
            property string glyph: ""
            property var action
            text: glyph
            color: root.fgDim
            font.family: root.uiFont
            font.pixelSize: 22

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: parent.color = root.fg
                onExited: parent.color = root.fgDim
                onClicked: action()
            }
        }

        PowerIcon {
            glyph: "󰜉"
            action: function() { sddm.reboot() }
        }
        PowerIcon {
            glyph: "⏻"
            action: function() { sddm.powerOff() }
        }
    }

    // ── Clock (bottom left) ──
    Text {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 24
        color: root.fgDim
        font.family: root.uiFont
        font.pixelSize: 14
        text: Qt.formatDateTime(clock.currentTime, "dddd, MMMM d  •  HH:mm")

        Timer {
            id: clock
            property date currentTime: new Date()
            interval: 1000
            repeat: true
            running: true
            onTriggered: currentTime = new Date()
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorLabel.text = "Login failed"
            passwordField.text = ""
            passwordField.focus = true
        }
        function onLoginSucceeded() {
            errorLabel.text = ""
        }
    }
}
