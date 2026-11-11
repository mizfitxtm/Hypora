import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects

// Left click = activate (menu for menu-only apps), middle = secondary action, right = menu
Row {
    id: root
    required property var window
    spacing: 8

    // Names plugins asked to hide (see docs/plugins.md, widget.hide_tray), from plugins.json
    property var hidden: []
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypora/plugins.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const all = JSON.parse(text())
                // reduce, not flatMap: the QML JS engine has no flatMap
                root.hidden = (Array.isArray(all) ? all : []).reduce((acc, e) => Array.isArray(e?.hide_tray) ? acc.concat(e.hide_tray) : acc, [])
                    .filter(h => typeof h === "string" && h !== "")
            } catch (e) {
                root.hidden = []
            }
        }
        onLoadFailed: root.hidden = []
    }

    Repeater {
        model: SystemTray.items

        Item {
            id: entry
            required property var modelData
            readonly property string tag: ((modelData.id ?? "") + " " + (modelData.title ?? "")).toLowerCase()
            visible: !root.hidden.some(h => entry.tag.includes(h))
            width: 18
            height: 18

            IconImage {
                id: icon
                anchors.fill: parent
                source: entry.modelData.icon
                // App-drawn pictures (Wine, Battle.net) keep their own colours; tinting turns them into blobs
                readonly property bool themed: String(source).startsWith("image://icon/")
                visible: !themed
            }
            // Icon-theme tray icons take the theme's hue; colorization keeps their light and dark parts
            MultiEffect {
                visible: icon.themed
                anchors.fill: parent
                source: icon
                colorization: 1
                colorizationColor: area.containsMouse || drop.open ? Theme.accent : Theme.fg
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: m => {
                    const d = entry.modelData
                    // Menu-only apps (libappindicator: Steam, Discord) ignore activate()
                    if (d.hasMenu && (m.button === Qt.RightButton || (m.button === Qt.LeftButton && d.onlyMenu)))
                        drop.open = true
                    else if (m.button === Qt.LeftButton)
                        d.activate()
                    else if (m.button === Qt.MiddleButton)
                        d.secondaryActivate()
                }
            }

            Dropdown {
                id: drop
                screen: root.window.screen
                barHeight: root.window.height
                anchorItem: entry
                onVisibleChanged: if (visible) menu.reset()

                TrayMenu {
                    id: menu
                    menu: entry.modelData.menu
                    onCloseRequested: drop.open = false
                }
            }
        }
    }
}
