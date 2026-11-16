import QtQuick
import QtQuick.Controls

MenuItem {
    id: item
    implicitWidth: 204
    implicitHeight: 34
    hoverEnabled: true
    property color accentColor: "#4285F4"
    property color foreground: "#F5F7FF"

    contentItem: Text {
        leftPadding: 12
        text: item.text
        color: item.highlighted ? "white" : item.foreground
        font.family: "Open Runde"
        font.pixelSize: 13
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 8
        color: item.highlighted ? item.accentColor : "transparent"
    }
}
