import QtQuick 2.15
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

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.5
    }

    // ── Centered login card ──
    Rectangle {
        id: card
        width: 420
        height: cardColumn.implicitHeight + 56
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

        Column {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 28
            spacing: 18

            Text {
                text: "hypr-os"
                color: root.fgDim
                font.family: root.uiFont
                font.pixelSize: 13
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                id: userLabel
                text: userModel.lastUser !== "" ? userModel.lastUser : "user"
                color: root.accent
                font.family: root.uiFont
                font.pixelSize: 22
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // ── Password box ──
            Rectangle {
                id: pwWrap
                width: parent.width
                height: 42
                color: root.bgHighlight
                radius: 8
                border.width: 1
                border.color: pwInput.activeFocus ? root.accent : "transparent"

                Text {
                    visible: pwInput.text.length === 0
                    text: "Password"
                    color: root.fgDim
                    font.family: root.uiFont
                    font.pixelSize: 15
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                }

                TextInput {
                    id: pwInput
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    color: root.fg
                    selectionColor: root.accentDim
                    selectedTextColor: root.fg
                    font.family: root.uiFont
                    font.pixelSize: 15
                    focus: true
                    clip: true
                    Keys.onReturnPressed: root.doLogin()
                    Keys.onEnterPressed: root.doLogin()
                }
            }

            // ── Sign in button ──
            Rectangle {
                id: signInBtn
                width: parent.width
                height: 42
                radius: 8
                color: signInArea.pressed ? root.accentDim : root.accent

                Text {
                    anchors.centerIn: parent
                    text: "Sign in"
                    color: root.bg
                    font.family: root.uiFont
                    font.pixelSize: 15
                    font.bold: true
                }

                MouseArea {
                    id: signInArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.doLogin()
                }
            }

            Text {
                id: errorLabel
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#e06c75"
                font.family: root.uiFont
                font.pixelSize: 12
                text: ""
                opacity: text == "" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }
    }

    function doLogin() {
        sddm.login(userLabel.text, pwInput.text, sessionModel.lastIndex)
    }

    // ── Power controls (bottom right) ──
    Row {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 24
        spacing: 22

        Component {
            id: powerIcon
            Text {
                property string glyph: ""
                property var onClicked
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
                    onClicked: parent.onClicked()
                }
            }
        }

        Loader {
            sourceComponent: powerIcon
            onLoaded: {
                item.glyph = "󰜉"
                item.onClicked = function() { sddm.reboot() }
            }
        }
        Loader {
            sourceComponent: powerIcon
            onLoaded: {
                item.glyph = "⏻"
                item.onClicked = function() { sddm.powerOff() }
            }
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
            pwInput.text = ""
            pwInput.focus = true
        }
        function onLoginSucceeded() {
            errorLabel.text = ""
        }
    }
}
