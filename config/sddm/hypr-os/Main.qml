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

    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

    // Hidden repeaters materialize the models so we can read fields by index.
    Repeater {
        id: userRepeater
        model: userModel
        Item {
            property string userName: name
            property string userRealName: realName
            visible: false
        }
    }
    Repeater {
        id: sessionRepeater
        model: sessionModel
        Item {
            property string sessionName: name
            visible: false
        }
    }

    function currentUserName() {
        if (userRepeater.count === 0) return "user"
        var it = userRepeater.itemAt(userIndex)
        if (!it) return "user"
        return it.userRealName !== "" ? it.userRealName : it.userName
    }

    function currentUserLogin() {
        if (userRepeater.count === 0) return ""
        var it = userRepeater.itemAt(userIndex)
        return it ? it.userName : ""
    }

    function currentSessionName() {
        if (sessionRepeater.count === 0) return "default"
        var it = sessionRepeater.itemAt(sessionIndex)
        return it ? it.sessionName : "default"
    }

    // ── Background wallpaper ──
    Image {
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

    // Click-outside dismisser for any open popup
    MouseArea {
        anchors.fill: parent
        onClicked: {
            userPopup.visible = false
            sessionPopup.visible = false
        }
        z: 0
    }

    // ── Centered login card ──
    Rectangle {
        id: card
        width: 440
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
        z: 1

        Column {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            Text {
                text: "hypr-os"
                color: root.fgDim
                font.family: root.uiFont
                font.pixelSize: 13
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // ── User dropdown ──
            Rectangle {
                id: userDropdown
                width: parent.width
                height: 46
                color: root.bgHighlight
                radius: 8
                border.width: 1
                border.color: userTrigger.containsMouse || userPopup.visible
                              ? root.accent : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    text: root.currentUserName()
                    color: root.accent
                    font.family: root.uiFont
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    text: "▾"
                    color: root.fgDim
                    font.family: root.uiFont
                    font.pixelSize: 14
                }

                MouseArea {
                    id: userTrigger
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        sessionPopup.visible = false
                        userPopup.visible = !userPopup.visible
                    }
                }
            }

            // ── Password ──
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

            // ── Session selector (below button, compact) ──
            Rectangle {
                id: sessionDropdown
                width: parent.width
                height: 32
                color: "transparent"
                radius: 6
                border.width: 1
                border.color: sessionTrigger.containsMouse || sessionPopup.visible
                              ? root.accent : root.accentDim

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: "Session: " + root.currentSessionName()
                    color: root.fgDim
                    font.family: root.uiFont
                    font.pixelSize: 12
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    text: "▾"
                    color: root.fgDim
                    font.family: root.uiFont
                    font.pixelSize: 10
                }

                MouseArea {
                    id: sessionTrigger
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        userPopup.visible = false
                        sessionPopup.visible = !sessionPopup.visible
                    }
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

    // ── User popup (floating, anchored to the card) ──
    Rectangle {
        id: userPopup
        visible: false
        width: 440 - 56
        x: card.x + 28
        y: card.y + 28 + 13 + 16 + 46 + 4
        color: root.bgHighlight
        radius: 8
        border.color: root.accentDim
        border.width: 1
        height: userListCol.implicitHeight + 12
        z: 10

        Column {
            id: userListCol
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            Repeater {
                model: userModel
                delegate: Rectangle {
                    width: userListCol.width
                    height: 34
                    color: uiArea.containsMouse ? root.bg : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        text: realName !== "" ? realName + "  (" + name + ")" : name
                        color: index === root.userIndex ? root.accent : root.fg
                        font.family: root.uiFont
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: uiArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.userIndex = index
                            userPopup.visible = false
                            pwInput.focus = true
                        }
                    }
                }
            }
        }
    }

    // ── Session popup ──
    Rectangle {
        id: sessionPopup
        visible: false
        width: 440 - 56
        x: card.x + 28
        y: card.y + card.height - 28 - 32 - (sessionListCol.implicitHeight + 12) - 4
        color: root.bgHighlight
        radius: 8
        border.color: root.accentDim
        border.width: 1
        height: sessionListCol.implicitHeight + 12
        z: 10

        Column {
            id: sessionListCol
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            Repeater {
                model: sessionModel
                delegate: Rectangle {
                    width: sessionListCol.width
                    height: 30
                    color: sesArea.containsMouse ? root.bg : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        text: name
                        color: index === root.sessionIndex ? root.accent : root.fg
                        font.family: root.uiFont
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: sesArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sessionIndex = index
                            sessionPopup.visible = false
                            pwInput.focus = true
                        }
                    }
                }
            }
        }
    }

    function doLogin() {
        sddm.login(currentUserLogin(), pwInput.text, sessionIndex)
    }

    // ── Power controls (bottom right) ──
    Row {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 24
        spacing: 22
        z: 1

        Text {
            text: "󰜉"
            color: rebootArea.containsMouse ? root.fg : root.fgDim
            font.family: root.uiFont
            font.pixelSize: 22
            MouseArea {
                id: rebootArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.reboot()
            }
        }
        Text {
            text: "⏻"
            color: poweroffArea.containsMouse ? root.fg : root.fgDim
            font.family: root.uiFont
            font.pixelSize: 22
            MouseArea {
                id: poweroffArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.powerOff()
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
        z: 1

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
