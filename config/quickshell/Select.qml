import QtQuick
import QtQuick.Controls.Basic as C

// A themed dropdown for picking one value; model is a list of { label, value }.
C.ComboBox {
    id: box
    textRole: "label"
    valueRole: "value"
    implicitHeight: 36
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    // Set to Theme.bg when the dropdown sits on a surface-coloured row
    property color fill: Theme.surface

    background: Rectangle {
        radius: 10
        color: box.hovered ? Qt.lighter(box.fill, 1.2) : box.fill
    }
    contentItem: Text {
        leftPadding: 14
        rightPadding: 30
        text: box.displayText
        font: box.font
        color: Theme.fg
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Icon {
        x: box.width - width - 12
        y: (box.height - height) / 2
        name: "chevron"
        rotation: 90
        size: 14
        color: Theme.dim
    }
    delegate: C.ItemDelegate {
        id: item
        required property var modelData
        required property int index
        width: box.width - 8
        x: 4
        highlighted: box.highlightedIndex === index
        contentItem: Text {
            text: item.modelData.label
            font: box.font
            color: item.highlighted ? Theme.accent : Theme.fg
        }
        background: Rectangle {
            radius: 6
            color: item.highlighted ? Theme.surface : "transparent"
        }
    }
    popup.background: Rectangle {
        radius: 10
        color: Theme.bg
        border.width: 1
        border.color: Theme.surface
    }
}
