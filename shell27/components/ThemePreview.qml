import QtQuick
import "../desktop"

Item {
    id: tile
    property string mode: "light"
    property string label: "Light"
    property bool selected: false
    property color accent: "#0A84FF"
    property color labelColor: "#1D1D1F"
    property string fontFamily: "Open Runde"
    signal chosen()

    width: 84
    height: 78
    readonly property bool dark: mode === "dark"
    readonly property bool split: mode === "auto"

    MiniDesktopPreview {
        width: 84
        height: 56
        dark: tile.dark
    }
    Item {
        x: 42
        width: 42
        height: 56
        clip: true
        visible: tile.split
        MiniDesktopPreview {
            x: -42
            width: 84
            height: 56
            dark: true
        }
    }
    Rectangle {
        width: 84
        height: 56
        radius: 8
        color: "transparent"
        border.width: tile.selected ? 3 : 1
        border.color: tile.selected ? tile.accent : Qt.rgba(0, 0, 0, 0.18)
    }
    Text {
        y: 60
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.label
        color: tile.labelColor
        font.family: tile.fontFamily
        font.pixelSize: 12
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.chosen()
    }
}
