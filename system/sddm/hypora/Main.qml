import QtQuick
import QtQuick.Window

// Hypora login screen (SDDM): time, date and password field, coloured from theme.conf.
Rectangle {
    id: root
    // Fill whatever monitor SDDM uses at its own resolution; binding to Screen keeps mixed-DPI setups right.
    width: Screen.width
    height: Screen.height
    // theme.conf is root-owned but read before login, so accept only #rrggbb and a simple font name, else the built-in value.
    function colour(v, fallback) {
        return /^#[0-9a-fA-F]{6}$/.test(String(v || "")) ? String(v) : fallback
    }
    function fontName(v, fallback) {
        const t = String(v || "")
        return /^[A-Za-z0-9 _.-]{1,64}$/.test(t) ? t : fallback
    }

    color: colour(config.bg, "#2e3440")

    // SDDM makes this once per screen, so the theme picks the panel's screen from `primary` in theme.conf.
    readonly property string wantScreen:
        /^[A-Za-z][A-Za-z0-9-]{0,31}$/.test(String(config.primary || "")) ? String(config.primary) : ""

    // Use the application's full screen list: a name matching nothing (monitor unplugged) must not hide the panel everywhere.
    readonly property bool wantScreenPresent: {
        if (wantScreen === "") return false
        const all = Qt.application.screens
        for (let i = 0; i < all.length; i++)
            if (all[i].name === wantScreen) return true
        return false
    }

    // Show here when a main display was chosen and this is it; otherwise show on every screen.
    readonly property bool showPanel: !wantScreenPresent || Screen.name === wantScreen

    readonly property color surface: colour(config.surface, "#3b4252")
    readonly property color fg: colour(config.fg, "#eceff4")
    readonly property color dim: colour(config.dim, "#7b88a1")
    readonly property color accent: colour(config.accent, "#88c0d0")
    readonly property color error: colour(config.error, "#bf616a")
    readonly property string font: fontName(config.font, "JetBrainsMono Nerd Font")

    // UserModel roles: name = UserRole + 1, realName = UserRole + 2
    readonly property int userCount: userModel.rowCount()
    property int userIndex: Math.max(0, userModel.lastIndex)
    readonly property string userName: userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 1) || ""
    readonly property string realName: userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 2) || ""

    // Prefer the uwsm-managed Hyprland session. SessionModel roles: file = UserRole + 2, name = UserRole + 4;
    // it has no DisplayRole, which read "" for every row, so with GNOME installed the first session won.
    readonly property int sessionIndex: {
        let fallback = sessionModel.lastIndex
        for (let i = 0; i < sessionModel.rowCount(); i++) {
            const file = String(sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 2) || "")
            const name = String(sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 4) || "")
            const text = (file + " " + name).toLowerCase()
            if (text.indexOf("hyprland") === -1) continue
            if (text.indexOf("uwsm") !== -1) return i
            fallback = i
        }
        return fallback
    }

    property bool failed: false
    // Login lockout (faillock, deny = 5) makes even the right password fail, so say so instead of "Wrong password"
    property int failures: 0
    property bool busy: false
    property date now: new Date()

    function cycleUser(step) {
        if (userCount > 1) userIndex = (userIndex + step + userCount) % userCount
        password.text = ""
        failures = 0
    }

    function login() {
        if (busy || password.text === "" || userName === "") return
        busy = true
        sddm.login(userName, password.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failed = true
            root.failures++
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    Column {
        anchors.centerIn: parent
        spacing: 0
        // Secondary screens keep the themed background and nothing else.
        visible: root.showPanel

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            font.family: root.font; font.pixelSize: 80; font.weight: Font.Light
            color: root.fg
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font.family: root.font; font.pixelSize: 15
            color: root.dim
        }

        Item { width: 1; height: 48 }

        // Only on multi-user machines: click it or press Up/Down to switch
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.userCount > 1
            bottomPadding: 12
            text: root.realName || root.userName
            font.family: root.font; font.pixelSize: 15
            color: root.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleUser(1)
            }
        }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300; height: 44
            radius: height / 2
            color: root.surface
            border.width: 1
            border.color: root.failed ? root.error : (password.activeFocus ? root.accent : "transparent")
            opacity: root.busy ? 0.6 : 1
            Behavior on border.color { ColorAnimation { duration: 150 } }

            transform: Translate { id: offset }
            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: offset; property: "x"; to: -8; duration: 40 }
                NumberAnimation { target: offset; property: "x"; to: 8; duration: 80 }
                NumberAnimation { target: offset; property: "x"; to: 0; duration: 40 }
            }

            Text {
                anchors.centerIn: parent
                visible: password.text === ""
                text: "Password"
                font.family: root.font; font.pixelSize: 14
                color: root.dim
            }

            TextInput {
                id: password
                anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                font.family: root.font; font.pixelSize: 16; font.letterSpacing: 3
                color: root.fg
                selectionColor: root.accent
                clip: true
                focus: true
                enabled: !root.busy

                onTextChanged: if (text !== "") root.failed = false
                onAccepted: root.login()
                Keys.onUpPressed: root.cycleUser(-1)
                Keys.onDownPressed: root.cycleUser(1)
            }
        }

        // Fixed-height slot so the layout doesn't jump when the message appears
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: field.width; height: 32
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                visible: root.failed
                text: root.failures >= 5 ? "Too many attempts: locked for 10 minutes"
                      : root.failures === 4 ? "Wrong password. One more locks it for 10 minutes"
                      : "Wrong password"
                font.family: root.font; font.pixelSize: 13
                color: root.error
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
