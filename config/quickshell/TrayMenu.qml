import Quickshell
import Quickshell.Widgets
import QtQuick

// One tray app's menu, drawn in the theme; submenus open in place with a Back row.
Rectangle {
    id: root
    required property var menu
    signal closeRequested()

    property var stack: []    // submenus opened, newest last
    function reset() { stack = [] }

    // Fit the widest row, within sane bounds
    implicitWidth: Math.min(480, Math.max(160, col.widest + 12))
    implicitHeight: col.height + 12
    radius: 12
    color: Theme.bg

    QsMenuOpener {
        id: opener
        menu: root.stack.length ? root.stack[root.stack.length - 1] : root.menu
    }

    Column {
        id: col
        x: 6; y: 6
        width: parent.width - 12
        // implicitWidth, not width, so this does not loop back through col.width
        readonly property real widest: {
            let w = 0
            for (const c of children) if (c.visible) w = Math.max(w, c.implicitWidth)
            return w
        }

        MenuRow {
            visible: root.stack.length > 0
            label: "‹  Back"
            onClicked: root.stack = root.stack.slice(0, -1)
        }

        Repeater {
            model: opener.children

            Loader {
                id: slot
                required property var modelData
                width: col.width
                sourceComponent: modelData.isSeparator ? sep : row

                Component {
                    id: sep
                    Item {
                        width: slot.width
                        height: 9
                        Rectangle { anchors.centerIn: parent; width: parent.width - 8; height: 1; color: Theme.surface }
                    }
                }
                Component {
                    id: row
                    MenuRow {
                        entry: slot.modelData
                        onClicked: {
                            if (entry.hasChildren) {
                                root.stack = root.stack.concat([entry])
                            } else {
                                entry.triggered()
                                root.closeRequested()
                            }
                        }
                    }
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: r
        property var entry: null
        property string label: entry?.text ?? ""
        signal clicked()
        readonly property bool on: entry ? entry.enabled : true

        width: col.width
        // From the label's natural width, so a cut-off label never shrinks the menu
        readonly property real chrome: 8 + 12 + 8 + (icon.visible ? 16 + 8 : 0) + 28
        implicitWidth: chrome + label.implicitWidth
        height: 28
        radius: 6
        color: area.containsMouse && on ? Theme.surface : "transparent"

        Row {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 8
            // Check or radio mark; the space is kept so labels line up
            Text {
                width: 12
                text: r.entry && r.entry.buttonType !== QsMenuButtonType.None && r.entry.checkState === Qt.Checked
                      ? (r.entry.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓") : ""
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            IconImage {
                id: icon
                visible: (r.entry?.icon ?? "") !== ""
                source: r.entry?.icon ?? ""
                implicitSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: label
                text: r.label.replace(/_(?!_)/g, "")    // strip dbusmenu mnemonic underscores
                // Past the width cap, cut long labels instead of spilling over the edge
                width: Math.min(implicitWidth, r.width - r.chrome)
                elide: Text.ElideRight
                color: r.on ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
        Text {
            visible: r.entry?.hasChildren ?? false
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: "›"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: r.on
            cursorShape: Qt.PointingHandCursor
            onClicked: r.clicked()
        }
    }
}
