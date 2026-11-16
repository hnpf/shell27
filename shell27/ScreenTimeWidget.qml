import QtQuick 2.15

Item {
    id: root
    implicitWidth: 260
    implicitHeight: 128

    property string totalText: "2h 14m"
    property var values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    function effectiveValues() {
        var arr = root.values && root.values.length ? root.values.slice() : [];
        if (arr.length === 0) return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        while (arr.length < 12) arr.push(0);
        for (var i = 0; i < arr.length; i++) arr[i] = Number(arr[i]) || 0;
        return arr;
    }

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
            const values = root.effectiveValues();
            const maxVal = Math.max(1, ...values);
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
            values.forEach(function (v, i) {
                const x = padX + (i / (values.length - 1)) * (w - padX * 2);
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
            values.forEach(function (v, i) {
                const x = padX + (i / (values.length - 1)) * (w - padX * 2);
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
