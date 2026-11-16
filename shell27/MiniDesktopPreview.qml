import QtQuick

Item {
    id: preview
    property bool dark: false
    width: 84
    height: 56

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: preview.dark ? "#141416" : "#D9DDE6"
    }
    Rectangle {
        x: 14; y: 9
        width: 56; height: 32
        radius: 4
        color: preview.dark ? "#2C2C2E" : "#FFFFFF"
        Rectangle { x: 0; y: 0; width: 15; height: parent.height; radius: 4; color: preview.dark ? "#3A3A3C" : "#E9E9EE" }
        Rectangle { x: 20; y: 7; width: 28; height: 3; radius: 1.5; color: preview.dark ? "#5A5A5E" : "#C8C8CE" }
        Rectangle { x: 20; y: 14; width: 20; height: 3; radius: 1.5; color: preview.dark ? "#48484A" : "#DADADF" }
        Rectangle { x: 20; y: 21; width: 24; height: 3; radius: 1.5; color: preview.dark ? "#48484A" : "#DADADF" }
    }
    Rectangle {
        x: 26; y: 46
        width: 32; height: 6
        radius: 3
        color: preview.dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.75)
    }
}
