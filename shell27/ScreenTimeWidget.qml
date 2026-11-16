import QtQuick 2.15

Item {
    id: root
    implicitWidth: 260
    implicitHeight: 128

    property string totalText: "2h 14m"
    property var values: [8, 18, 26, 36, 52, 70, 62, 48, 33, 18, 10, 6]

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.rgba(0.13, 0.14, 0.18, 0.82)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    Text {
        x: 14
        y: 10
        text: root.totalText
        color: "#F5F5F7"
        font.family: "SF Pro Display"
        font.pixelSize: 16
        font.weight: Font.DemiBold
    }

    Canvas {
        id: graph
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 20
        onPaint: {
            const ctx = getContext("2d");
            const w = width;
            const h = height;
            const maxVal = 90;
            const padX = 8;
            const padY = 8;

            ctx.clearRect(0, 0, w, h);
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12);
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let i = 0; i <= 4; i++) {
                const y = padY + (i / 4) * (h - padY * 2);
                ctx.moveTo(padX, y);
                ctx.lineTo(w - padX, y);
            }
            ctx.stroke();

            ctx.strokeStyle = "#8C7BFF";
            ctx.lineWidth = 4;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.beginPath();
            root.values.forEach(function (v, i) {
                const x = padX + (i / (root.values.length - 1)) * (w - padX * 2);
                const y = h - padY - (v / maxVal) * (h - padY * 2);
                if (i === 0) {
                    ctx.moveTo(x, y);
                } else {
                    ctx.lineTo(x, y);
                }
            });
            ctx.stroke();

            ctx.fillStyle = Qt.rgba(140, 123, 255, 0.18);
            ctx.beginPath();
            const firstX = padX + 0 * (w - padX * 2);
            const firstY = h - padY;
            root.values.forEach(function (v, i) {
                const x = padX + (i / (root.values.length - 1)) * (w - padX * 2);
                const y = h - padY - (v / maxVal) * (h - padY * 2);
                if (i === 0) {
                    ctx.moveTo(x, y);
                } else {
                    ctx.lineTo(x, y);
                }
            });
            ctx.lineTo(w - padX, firstY);
            ctx.lineTo(firstX, firstY);
            ctx.closePath();
            ctx.fill();
        }
    }
}
