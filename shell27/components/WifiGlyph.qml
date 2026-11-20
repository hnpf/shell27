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
        opacity: root.flag ? 0.45 : 1
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
            var scale = Math.min(width / 14, height / 10);
            ctx.translate((width - 14 * scale) / 2, (height - 10 * scale) / 2);
            ctx.scale(scale, scale);
            ctx.strokeStyle = strokeColor;
            ctx.lineWidth = 1.2;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(1, 0.6);
            ctx.lineTo(13, 9.4);
            ctx.stroke();
        }
    }
}