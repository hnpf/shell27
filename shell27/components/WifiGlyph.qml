import QtQuick
import QtQuick.Effects

Item {
    id: root
    property color color: "white"
    property bool flag: false

    Image {
        id: sourceImage
        anchors.fill: parent
        source: "../assets/wifi-symbolic.svg"
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio * 4), Math.ceil(height * Screen.devicePixelRatio * 4))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: false
        visible: false
    }
    MultiEffect {
        anchors.fill: sourceImage
        source: sourceImage
        colorization: 1
        colorizationColor: root.color
    }
    Canvas {
        anchors.fill: parent
        property bool drawFlag: root.flag
        property color strokeColor: root.color
        visible: drawFlag
        onDrawFlagChanged: requestPaint()
        onStrokeColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var scale = Math.min(width, height) / 18;
            ctx.scale(scale, scale);
            ctx.strokeStyle = strokeColor;
            ctx.lineWidth = 1.7;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(3, 3);
            ctx.lineTo(15, 15);
            ctx.stroke();
        }
    }
}