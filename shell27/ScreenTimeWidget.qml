import QtQuick
import QtQuick.Effects
import "Fonts.js" as Fonts

Item {
    id: w

    property string style: "liquid"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Open Runde"
    property real screenX: x
    property real screenY: y
    property string totalText: "0m"
    property var hourlyValues: Array(24).fill(0)
    property var categories: []
    property var topApps: []
    property bool trackingEnabled: false

    property bool glassReady: false
    property url shaderUrl: ""
    property url wallUrl: ""
    property string wallVideo: ""
    property bool wallPaused: false
    property real screenW: 1920
    property real screenH: 1080
    property real glassOpacity: 0.42
    property real glassBlur: 5
    property real glassLiquid: 1.0
    property real glassRim: 0.45
    property color borderTint: "#8A9AB5"
    property real glassGrain: 0.03
    property bool darkGlass: true
    property bool preview: false
    property bool flat: false
    signal glassFailed()

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"
    readonly property real s: scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    readonly property real radiusPx: 28 * s
    readonly property bool glassOn: style === "liquid" && glassReady && !preview && wallUrl != ""
    readonly property bool dark: darkGlass
    readonly property color fg: dark ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0, 0, 0, 0.86)
    readonly property color fgSub: dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.52)
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    readonly property real tint: Math.min(0.92, dark ? 0.06 + glassOpacity * 0.5 : 0.45 + glassOpacity * 0.9)
    readonly property real pad: 15 * s

    width: (isSmall ? 168 : (isLarge ? 358 : 338)) * s
    height: (isLarge ? 354 : 168) * scaleF

    function safeValues() {
        var values = Array.isArray(hourlyValues) ? hourlyValues.slice(0, 24) : [];
        while (values.length < 24) values.push(0);
        return values.map(function(value) { return Math.max(0, Number(value) || 0); });
    }
    function formatSeconds(value) {
        var seconds = Math.max(0, Number(value) || 0);
        var minutes = Math.floor(seconds / 60);
        if (minutes < 1) return Math.floor(seconds) + "s";
        if (minutes < 60) return minutes + "m";
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m";
    }

    Rectangle {
        anchors.fill: parent
        visible: !w.flat && w.style === "normal"
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.dark ? "#3A3A3D" : "#FFFFFF" }
            GradientStop { position: 1.0; color: w.dark ? "#2A2A2D" : "#EFEFF3" }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !w.flat && w.style === "liquid" && !w.glassOn
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.dark ? Qt.rgba(0.22, 0.22, 0.25, 0.82) : Qt.rgba(1.0, 1.0, 1.0, 0.88) }
            GradientStop { position: 1.0; color: w.dark ? Qt.rgba(0.13, 0.13, 0.15, 0.82) : Qt.rgba(0.92, 0.92, 0.95, 0.88) }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, w.dark ? 0.10 : 0.35) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            property bool moving: false
            readonly property bool streaming: w.wallVideo !== "" || moving
            readonly property string capSig: [w.wallUrl, w.screenX, w.screenY, w.screenW, w.screenH, w.width, w.height, w.glassBlur, w.shaderUrl].join("|")
            onCapSigChanged: { moving = true; settle.restart(); }
            property int capStep: 0
            function recap() { capStep = 0; capTimer.restart(); }
            Timer { id: settle; interval: 450; onTriggered: { gl.moving = false; gl.recap(); } }
            Timer {
                id: capTimer
                interval: 60
                onTriggered: {
                    if (gl.capStep === 0) bsrc.scheduleUpdate(); else blurred.scheduleUpdate();
                    gl.capStep++;
                    if (gl.capStep < 2) capTimer.restart();
                }
            }
            Component.onCompleted: recap()
            readonly property real margin: 72
            readonly property real padPx: 10
            readonly property real ds: w.glassBlur >= 8 ? 0.5 : 1.0
            readonly property real bn: Math.min(1.0, w.glassBlur * 1.4 * ds / 64.0)
            Item {
                id: backdrop
                width: w.width + 2 * (gl.padPx + gl.margin)
                height: w.height + 2 * (gl.padPx + gl.margin)
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#2f6bff" }
                        GradientStop { position: 0.5; color: "#b44cff" }
                        GradientStop { position: 1.0; color: "#ff8a3d" }
                    }
                }
                Image {
                    x: -(w.screenX - gl.padPx - gl.margin)
                    y: -(w.screenY - gl.padPx - gl.margin)
                    width: w.screenW; height: w.screenH
                    source: w.wallUrl
                    onStatusChanged: if (status === Image.Ready) { gl.moving = true; settle.restart(); }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: w.screenW
                    smooth: true
                }
                LiveWall {
                    x: -(w.screenX - gl.padPx - gl.margin)
                    y: -(w.screenY - gl.padPx - gl.margin)
                    width: w.screenW; height: w.screenH
                    video: w.wallVideo
                    live: w.wallVideo !== ""
                    paused: w.wallPaused
                }
            }
            ShaderEffectSource {
                id: bsrc
                sourceItem: backdrop; hideSource: true; live: gl.streaming; visible: false
                textureSize: Qt.size(Math.max(1, Math.round(backdrop.width * gl.ds)), Math.max(1, Math.round(backdrop.height * gl.ds)))
            }
            MultiEffect {
                id: blurFx
                source: bsrc
                width: backdrop.width * gl.ds; height: backdrop.height * gl.ds
                blurEnabled: true; blurMax: 64; blur: gl.bn; autoPaddingEnabled: false; visible: false
            }
            ShaderEffectSource { id: blurred; sourceItem: blurFx; live: gl.streaming; visible: false }
            ShaderEffect {
                x: -gl.padPx; y: -gl.padPx
                width: w.width + 2 * gl.padPx; height: w.height + 2 * gl.padPx
                fragmentShader: w.shaderUrl
                onStatusChanged: if (status === ShaderEffect.Error) w.glassFailed()
                property variant src: blurred
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(w.width, w.height)
                property vector2d srcSize: Qt.vector2d(backdrop.width, backdrop.height)
                property vector2d srcOffset: Qt.vector2d(gl.margin, gl.margin)
                property real pad: gl.padPx
                property real radius: w.radiusPx
                property real bezel: Math.min(Math.min(w.width, w.height) * 0.36, 26)
                property real thickness: 30 * w.glassLiquid
                property real dispersion: 0.06 * w.glassLiquid
                property real magnify: 0.08 * w.glassLiquid * Math.min(1, 90 / w.height)
                property real rim: w.glassRim
                property real grain: w.glassGrain * 0.15
                property real blurPx: 1.0
                property real tintMix: w.tint
                property real saturation: 1.25
                property real dark: w.dark ? 1 : 0
                property real debug: 0
                property real shadowAmt: 0
                property real flatInner: 1
                property real rimTint: 1
                property real ringW: 0
            }
        }
    }

    CornerBorder {
        z: 2
        anchors.fill: parent
        visible: !w.flat
        cornerR: w.radiusPx
        dark: w.dark
        tint: w.borderTint
        lineW: 0.8
    }

    Text {
        x: w.pad; y: 12 * w.s
        text: "Screen Time"
        color: w.fgSub
        font.family: Fonts.forWeight(Font.DemiBold, w.fam)
        font.pixelSize: 13 * w.s
        font.weight: Font.DemiBold
    }
    Text {
        x: w.pad - 1 * w.s; y: 30 * w.s
        width: w.isMedium ? Math.max(0, graph.x - x - 8 * w.s) : undefined
        text: w.totalText
        color: w.fg
        font.family: Fonts.forWeight(Font.DemiBold, w.fam)
        font.pixelSize: (w.isSmall ? 34 : (w.isMedium ? 39 : 44)) * w.s
        fontSizeMode: w.isMedium ? Text.Fit : Text.FixedSize
        minimumPixelSize: 28 * w.s
        font.weight: Font.DemiBold
    }
    Text {
        x: w.pad; y: (w.isSmall ? 72 : 76) * w.s
        width: w.isMedium ? Math.max(0, graph.x - x - 8 * w.s) : undefined
        text: w.trackingEnabled ? "Today" : "Tracking off"
        color: w.fgSub
        font.family: w.fam
        font.pixelSize: 12 * w.s
        elide: Text.ElideRight
    }

    Canvas {
        id: graph
        x: w.isSmall ? w.pad : (w.isMedium ? 152 * w.s : w.pad)
        y: w.isSmall ? 96 * w.s : (w.isMedium ? 30 * w.s : 100 * w.s)
        width: w.isSmall ? w.width - 2 * w.pad : (w.isMedium ? w.width - 168 * w.s : w.width - 2 * w.pad)
        height: w.isSmall ? 52 * w.s : (w.isMedium ? 92 * w.s : 124 * w.s)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            var values = w.safeValues();
            var maxVal = Math.max(60, Math.max.apply(null, values));
            var left = 2, right = width - 2, top = 2;
            var labelH = 13 * w.s, bottom = height - labelH;
            var plotH = Math.max(1, bottom - top);
            var slot = (right - left) / 24;
            var barW = Math.max(2, slot * (w.isSmall ? 0.52 : 0.58));
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = w.line;
            ctx.lineWidth = 1;
            for (var line = 1; line <= 3; line++) {
                var gy = top + plotH * line / 3;
                ctx.beginPath(); ctx.moveTo(left, gy); ctx.lineTo(right, gy); ctx.stroke();
            }
            for (var i = 0; i < values.length; i++) {
                var bh = values[i] > 0 ? Math.max(2, plotH * values[i] / maxVal) : 1;
                var bx = left + slot * i + (slot - barW) / 2;
                var by = bottom - bh;
                var r = Math.min(barW / 2, 3 * w.s);
                ctx.fillStyle = values[i] > 0 ? "#B9A8FF" : Qt.rgba(1, 1, 1, w.dark ? 0.20 : 0.18);
                ctx.beginPath();
                ctx.moveTo(bx, bottom); ctx.lineTo(bx, by + r);
                ctx.quadraticCurveTo(bx, by, bx + r, by);
                ctx.lineTo(bx + barW - r, by);
                ctx.quadraticCurveTo(bx + barW, by, bx + barW, by + r);
                ctx.lineTo(bx + barW, bottom); ctx.closePath(); ctx.fill();
            }
            ctx.fillStyle = w.fgSub;
            ctx.font = (10 * w.s) + "px " + w.fam;
            ctx.textBaseline = "bottom";
            [[0, "00"], [6, "06"], [12, "12"], [18, "18"]].forEach(function(tick) {
                var tx = left + slot * tick[0];
                ctx.fillText(tick[1], tx, height);
            });
        }
        Connections {
            target: w
            function onHourlyValuesChanged() { graph.requestPaint(); }
            function onDarkChanged() { graph.requestPaint(); }
        }
    }

    Rectangle {
        visible: w.isMedium
        x: 140 * w.s; y: 19 * w.s
        width: 1; height: w.height - 38 * w.s
        color: w.line
    }
    Row {
        visible: w.isMedium
        x: w.pad; y: w.height - 18 * w.s
        spacing: 12 * w.s
        Repeater {
            model: w.categories.slice(0, 3)
            delegate: Text {
                required property var modelData
                text: modelData.name + "  " + w.formatSeconds(modelData.seconds)
                color: w.fgSub
                font.family: w.fam
                font.pixelSize: 10 * w.s
                elide: Text.ElideRight
            }
        }
    }

    Text {
        visible: w.isLarge
        x: w.pad; y: 239 * w.s
        text: "Most Used"
        color: w.fgSub
        font.family: Fonts.forWeight(Font.DemiBold, w.fam)
        font.pixelSize: 12 * w.s
        font.weight: Font.DemiBold
    }
    Column {
        visible: w.isLarge
        x: w.pad; y: 260 * w.s
        width: w.width - 2 * w.pad
        Repeater {
            model: w.topApps.slice(0, 3)
            delegate: Item {
                required property var modelData
                width: parent.width; height: 27 * w.s
                Text {
                    anchors.left: parent.left; anchors.right: timeLabel.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: w.fg
                    font.family: w.fam; font.pixelSize: 12 * w.s
                    elide: Text.ElideRight
                }
                Text {
                    id: timeLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: w.formatSeconds(modelData.seconds)
                    color: w.fgSub
                    font.family: w.fam; font.pixelSize: 12 * w.s
                }
            }
        }
    }
}
