// macOS Stocks & Crypto Widget (Apple Sonoma / Tahoe style)
// sizes: Small (168x168), Medium (358x168)
// styles: "liquid" | "normal"

import QtQuick
import "../components"
import QtQuick.Effects
import Quickshell.Io

Item {
    id: w

    property string style: "liquid"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Inter"
    property real screenX: x
    property real screenY: y
    property bool editing: false

    // Liquid Glass properties
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

    signal glassFailed()

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"
    readonly property real s: scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    readonly property real u: s
    readonly property real radiusPx: 28 * s

    readonly property bool dark: style === "dark" || (style === "liquid" && darkGlass)
    readonly property bool glassOn: style === "liquid" && glassReady && wallUrl != ""

    width: (isSmall ? 158 : (isLarge ? 358 : 338)) * s
    height: (isLarge ? 354 : 168) * scaleF

    // Active selected index for small view
    property int selectedIndex: 0
    QtObject {
        id: stockButtonWd
        readonly property bool hasPlayer: true
        readonly property bool dark: w.dark
        readonly property bool preview: false
        readonly property bool editing: w.editing
        readonly property string fam: w.fam
    }

    function cycleAsset() {
        if (!stockList || stockList.length < 2) return;
        selectedIndex = (selectedIndex + 1) % stockList.length;
        sCanvas.requestPaint();
    }

    // Assets data
    property var stockList: []
    property bool dataLoaded: false

    readonly property var currentAsset: (stockList && stockList.length > selectedIndex)
        ? stockList[selectedIndex]
        : (stockList && stockList.length > 0 ? stockList[0] : { "symbol": "—", "name": "Market data unavailable", "price": null, "change24h": 0, "currency": "$", "sparkline": [] })

    readonly property string stocksScript: decodeURIComponent(Qt.resolvedUrl("../scripts/stocks_fetcher.py").toString().replace(/^file:\/\//, ""))
    readonly property string stocksLibDir: decodeURIComponent(Qt.resolvedUrl("../lib/").toString().replace(/^file:\/\//, ""))

    function formatPrice(val, curr) {
        if (val === undefined || val === null) return "—";
        var n = Number(val);
        var parts = n.toFixed(2).split(".");
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return (curr || "$") + parts.join(".");
    }

    function drawSpark(ctx, pts, W, H, pad, lw, col, fillCol, fillR) {
        var min = Math.min.apply(null, pts), max = Math.max.apply(null, pts);
        var range = (max - min) || 1, n = pts.length, xs = [], ys = [];
        for (var i = 0; i < n; i++) {
            xs.push(i / (n - 1) * W);
            ys.push(H - ((pts[i] - min) / range) * (H - 2 * pad) - pad);
        }
        function clampY(y, a, b) { return Math.max(Math.min(a, b), Math.min(Math.max(a, b), y)); }
        function trace() {
            ctx.moveTo(xs[0], ys[0]);
            for (var j = 0; j < n - 1; j++) {
                var a = Math.max(0, j - 1), b = Math.min(n - 1, j + 2);
                var c1x = xs[j] + (xs[j + 1] - xs[a]) / 6;
                var c1y = clampY(ys[j] + (ys[j + 1] - ys[a]) / 6, ys[j], ys[j + 1]);
                var c2x = xs[j + 1] - (xs[b] - xs[j]) / 6;
                var c2y = clampY(ys[j + 1] - (ys[b] - ys[j]) / 6, ys[j], ys[j + 1]);
                ctx.bezierCurveTo(c1x, c1y, c2x, c2y, xs[j + 1], ys[j + 1]);
            }
        }
        if (fillCol) {
            var r = Math.min(fillR, H / 2, W / 2);
            ctx.save();
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(W, 0);
            ctx.lineTo(W, H - r);
            ctx.arcTo(W, H, W - r, H, r);
            ctx.lineTo(r, H);
            ctx.arcTo(0, H, 0, H - r, r);
            ctx.closePath();
            ctx.clip();
            ctx.beginPath();
            trace();
            ctx.lineTo(W, H);
            ctx.lineTo(0, H);
            ctx.closePath();
            ctx.fillStyle = fillCol;
            ctx.fill();
            ctx.restore();
        }
        ctx.beginPath();
        trace();
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.lineWidth = lw;
        ctx.strokeStyle = col;
        ctx.stroke();
    }

    // Process for fetching live stock and crypto data
    Process {
        id: stockProc
        command: ["env", "LD_LIBRARY_PATH=" + w.stocksLibDir, "python3", w.stocksScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var s = text.trim();
                    if (s.indexOf("[") >= 0) {
                        var parsed = JSON.parse(s);
                        if (Array.isArray(parsed)) w.stockList = parsed;
                    }
                } catch (e) {}
                w.dataLoaded = true;
            }
        }
    }

    Text {
        anchors.centerIn: parent
        z: 10
        visible: w.stockList.length === 0
        text: w.dataLoaded ? "Market data unavailable" : "Loading markets…"
        color: w.dark ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0, 0, 0, 0.62)
        font.family: w.fam
        font.pixelSize: 13 * w.scaleF
        horizontalAlignment: Text.AlignHCenter
    }

    Timer {
        interval: 180000 // Refresh every 3 minutes to save bandwidth and CPU
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!stockProc.running) stockProc.running = true;
        }
    }

    // ───────────── Backdrop ─────────────
    // Normal / Solid style
    Rectangle {
        anchors.fill: parent
        visible: !w.glassOn
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.style === "liquid" ? (w.dark ? Qt.rgba(0.22, 0.22, 0.25, 0.82) : Qt.rgba(1.0, 1.0, 1.0, 0.88)) : (w.dark ? Qt.rgba(0.18, 0.18, 0.22, 0.92) : Qt.rgba(1.0, 1.0, 1.0, 0.92)) }
            GradientStop { position: 1.0; color: w.style === "liquid" ? (w.dark ? Qt.rgba(0.13, 0.13, 0.15, 0.82) : Qt.rgba(0.92, 0.92, 0.95, 0.88)) : (w.dark ? Qt.rgba(0.11, 0.11, 0.14, 0.92) : Qt.rgba(0.93, 0.93, 0.96, 0.92)) }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: w.style === "liquid"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, w.dark ? 0.10 : 0.35) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

	readonly property real tint: Math.min(0.92, dark ? 0.06 + glassOpacity * 0.5 : 0.45 + glassOpacity * 0.9)

    // Liquid Glass backdrop
    Loader {
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            readonly property real margin: 72
            readonly property real padPx: 10
            property bool moving: false
            readonly property bool streaming: w.wallVideo !== "" || moving
            readonly property string captureSignature: [w.wallUrl, w.wallVideo, w.screenW, w.screenH, w.width, w.height, w.glassBlur, w.shaderUrl].join("|")
            onCaptureSignatureChanged: { moving = true; settle.restart(); }
            Connections {
                target: w
                function onScreenXChanged() { gl.recapture(); }
                function onScreenYChanged() { gl.recapture(); }
            }
            property int captureStep: 0
            function recapture() { captureStep = 0; captureTimer.restart(); }
            Timer { id: settle; interval: 450; onTriggered: { gl.moving = false; gl.recapture(); } }
            Timer {
                id: captureTimer
                interval: 60
                onTriggered: {
                    if (gl.captureStep === 0) sourceCapture.scheduleUpdate();
                    else frosted.scheduleUpdate();
                    gl.captureStep++;
                    if (gl.captureStep < 2) captureTimer.restart();
                }
            }
            Component.onCompleted: recapture()
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
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: w.screenW
                    smooth: true
                    onStatusChanged: if (status === Image.Ready) { gl.moving = true; settle.restart(); }
                }
                LiveWall {
                    x: -(w.screenX - gl.padPx - gl.margin)
                    y: -(w.screenY - gl.padPx - gl.margin)
                    width: w.screenW
                    height: w.screenH
                    video: w.wallVideo
                    live: w.wallVideo !== ""
                    paused: w.wallPaused
                }
            }

            ShaderEffectSource {
                id: sourceCapture
                sourceItem: backdrop
                hideSource: true
                live: gl.streaming
                visible: false
                textureSize: Qt.size(Math.max(1, Math.round(backdrop.width * gl.ds)), Math.max(1, Math.round(backdrop.height * gl.ds)))
            }

            MultiEffect {
                id: blurFx
                source: sourceCapture
                width: backdrop.width * gl.ds
                height: backdrop.height * gl.ds
                blurEnabled: gl.bn > 0.001
                blur: gl.bn
                blurMax: 64
                autoPaddingEnabled: false
                saturation: 0.15
                contrast: 0.05
                visible: false
            }

            ShaderEffectSource {
                id: frosted
                sourceItem: blurFx
                live: gl.streaming
                visible: false
            }

            ShaderEffect {
                x: -gl.padPx
                y: -gl.padPx
                width: w.width + 2 * gl.padPx
                height: w.height + 2 * gl.padPx
                fragmentShader: w.shaderUrl
                onStatusChanged: if (status === ShaderEffect.Error) w.glassFailed()

                property variant src: frosted
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
        cornerR: w.radiusPx
        dark: w.dark
        tint: w.borderTint
        lineW: 0.8
    }

    // ───────────── Content UI ─────────────
    // SMALL SIZE: Single asset highlight with Sparkline chart
    Item {
        id: smallContent
        anchors.fill: parent
        anchors.leftMargin: 18 * w.s
        anchors.rightMargin: 18 * w.s
        anchors.topMargin: 16 * w.s
        anchors.bottomMargin: 14 * w.s
        visible: w.isSmall

        // Top Row: Symbol, Name, and Next switcher button
        Item {
            id: sTopRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28 * w.s

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: w.currentAsset.symbol
                    font.family: w.fam
                    font.pixelSize: 14 * w.u
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }
                Text {
                    text: w.currentAsset.name
                    font.family: w.fam
                    font.pixelSize: 9.5 * w.u
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                    elide: Text.ElideRight
                }
            }

            PlayerBtn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30 * w.u
                height: width
                wd: stockButtonWd
                kind: "swap"
                col: w.dark ? "white" : "#1C1C1E"
                gw: 16 * w.u
                gh: 16 * w.u
                idleFill: true
                enabledBtn: true
                onClicked: w.cycleAsset()
            }
        }

        // Middle: Price & Percentage Change Pill
        Row {
            id: sPriceRow
            anchors.top: sTopRow.bottom
            anchors.topMargin: 4 * w.u
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28 * w.u
            spacing: 6 * w.u

            Text {
                id: sPriceTxt
                anchors.verticalCenter: parent.verticalCenter
                text: w.formatPrice(w.currentAsset.price, w.currentAsset.currency)
                font.family: w.fam
                font.pixelSize: 15 * w.u
                font.weight: Font.Bold
                color: w.dark ? "white" : "#1C1C1E"
            }

            Rectangle {
                id: sPill
                anchors.verticalCenter: parent.verticalCenter
                height: 18 * w.u
                width: sPillTxt.implicitWidth + 8 * w.u
                radius: 5 * w.u
                color: (w.currentAsset.change24h >= 0) ? "#34C759" : "#FF3B30"

                Text {
                    id: sPillTxt
                    anchors.centerIn: parent
                    text: (w.currentAsset.change24h >= 0 ? "+" : "") + w.currentAsset.change24h + "%"
                    font.family: w.fam
                    font.pixelSize: 9.5 * w.u
                    font.weight: Font.Bold
                    color: "white"
                }
            }
        }

        // Bottom Sparkline Chart (Canvas)
        Canvas {
            id: sCanvas
            anchors.top: sPriceRow.bottom
            anchors.topMargin: 4 * w.u
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            antialiasing: true

            readonly property var pts: w.currentAsset.sparkline || []
            readonly property bool isUp: w.currentAsset.change24h >= 0

            onPtsChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                    ctx.reset();
                    if (!pts || pts.length < 2) return;
                    w.drawSpark(ctx, pts, width, height, 4, 2.2,
                        isUp ? "#34C759" : "#FF3B30",
                        isUp ? "rgba(52, 199, 89, 0.18)" : "rgba(255, 59, 48, 0.18)",
                        14 * w.s);
                

                var min = Math.min.apply(null, pts);
                var max = Math.max.apply(null, pts);
                var range = (max - min) || 1;

                var strokeCol = isUp ? "#34C759" : "#FF3B30";
                var fillCol = isUp ? "rgba(52, 199, 89, 0.18)" : "rgba(255, 59, 48, 0.18)";

                ctx.beginPath();
                for (var i = 0; i < pts.length; i++) {
                    var x = (i / (pts.length - 1)) * W;
                    var y = H - ((pts[i] - min) / range) * (H - 8) - 4;
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }

                // Line stroke
                ctx.lineWidth = 2.2;
                ctx.strokeStyle = strokeCol;
                ctx.stroke();

                // Fill gradient under curve
                ctx.lineTo(W, H);
                ctx.lineTo(0, H);
                ctx.closePath();
                ctx.fillStyle = fillCol;
                ctx.fill();
            }
        }
    }

    // MEDIUM SIZE: Watchlist of 4-5 Assets with mini sparklines
    Item {
        id: medContent
        anchors.fill: parent
        anchors.leftMargin: 20 * w.s
        anchors.rightMargin: 20 * w.s
        anchors.topMargin: 16 * w.s
        anchors.bottomMargin: 14 * w.s
        visible: w.isMedium

        Column {
            anchors.fill: parent
            spacing: 2 * w.s

            // Header row
            Item {
                width: parent.width
                height: 20 * w.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Watchlist"
                    font.family: w.fam
                    font.pixelSize: 12 * w.s
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Today's Markets"
                    font.family: w.fam
                    font.pixelSize: 10 * w.s
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                }
            }

            // Asset Rows (up to 4)
            Column {
                width: parent.width
                spacing: 4 * w.s

                Repeater {
                    model: Math.min(4, w.stockList.length)
                    delegate: Item {
                        id: rowItem
                        required property int index
                        readonly property var ast: w.stockList[index]
                        width: parent.width
                        height: 27 * w.s

                        // Click to cycle
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                        }

                        // Symbol & Name (Apple Stocks style Column)
                        Column {
                            id: astCol
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 68 * w.s
                            spacing: 1 * w.s

                            Text {
                                text: rowItem.ast.symbol
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Text {
                                text: rowItem.ast.name
                                font.family: w.fam
                                font.pixelSize: 9 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Mini Sparkline Canvas in center (responsive width)
                        Canvas {
                            id: mSpark
                            anchors.left: astCol.right
                            anchors.leftMargin: 8 * w.s
                            anchors.right: priceRow.left
                            anchors.rightMargin: 12 * w.s
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18 * w.s
                            antialiasing: true

                            readonly property var pts: rowItem.ast.sparkline || []
                            readonly property bool isUp: rowItem.ast.change24h >= 0

                            onPtsChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                    ctx.reset();
                                    if (!pts || pts.length < 2) return;
                                    w.drawSpark(ctx, pts, width, height, 2, 1.6, isUp ? "#34C759" : "#FF3B30", "", 0);
                                
                                var W = width, H = height;
                                var min = Math.min.apply(null, pts);
                                var max = Math.max.apply(null, pts);
                                var range = (max - min) || 1;

                                ctx.beginPath();
                                for (var i = 0; i < pts.length; i++) {
                                    var x = (i / (pts.length - 1)) * W;
                                    var y = H - ((pts[i] - min) / range) * (H - 4) - 2;
                                    if (i === 0) ctx.moveTo(x, y);
                                    else ctx.lineTo(x, y);
                                }
                                ctx.lineWidth = 1.6;
                                ctx.strokeStyle = isUp ? "#34C759" : "#FF3B30";
                                ctx.stroke();
                            }
                        }

                        // Right: Price & % pill
                        Row {
                            id: priceRow
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.formatPrice(rowItem.ast.price, rowItem.ast.currency)
                                font.family: w.fam
                                font.pixelSize: 11.5 * w.s
                                font.weight: Font.DemiBold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18 * w.s
                                width: 52 * w.s
                                radius: 4.5 * w.s
                                color: (rowItem.ast.change24h >= 0) ? "#34C759" : "#FF3B30"

                                Text {
                                    anchors.centerIn: parent
                                    text: (rowItem.ast.change24h >= 0 ? "+" : "") + rowItem.ast.change24h + "%"
                                    font.family: w.fam
                                    font.pixelSize: 9.5 * w.s
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // LARGE SIZE: Featured Hero Asset + Watchlist
    Item {
        id: largeContent
        anchors.fill: parent
        anchors.leftMargin: 20 * w.s
        anchors.rightMargin: 20 * w.s
        anchors.topMargin: 18 * w.s
        anchors.bottomMargin: 18 * w.s
        visible: w.isLarge

        Column {
            anchors.fill: parent
            spacing: 12 * w.s

            // Top Hero Card
            Rectangle {
                width: parent.width
                height: 150 * w.s
                radius: 14 * w.s
                color: w.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)

                Column {
                    anchors.fill: parent
                    anchors.margins: 12 * w.s
                    spacing: 6 * w.s

                    // Symbol, Name & Change Pill
                    Item {
                        width: parent.width
                        height: 28 * w.s

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                text: w.currentAsset.symbol
                                font.family: w.fam
                                font.pixelSize: 16 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.currentAsset.name
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.formatPrice(w.currentAsset.price, w.currentAsset.currency)
                                font.family: w.fam
                                font.pixelSize: 15 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 20 * w.s
                                width: lHeroPillTxt.implicitWidth + 10 * w.s
                                radius: 5 * w.s
                                color: (w.currentAsset.change24h >= 0) ? "#34C759" : "#FF3B30"

                                Text {
                                    id: lHeroPillTxt
                                    anchors.centerIn: parent
                                    text: (w.currentAsset.change24h >= 0 ? "+" : "") + w.currentAsset.change24h + "%"
                                    font.family: w.fam
                                    font.pixelSize: 10 * w.s
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                        }
                    }

                    // Large Sparkline
                    Canvas {
                        width: parent.width
                        height: 84 * w.s
                        antialiasing: true

                        readonly property var pts: w.currentAsset.sparkline || []
                        readonly property bool isUp: w.currentAsset.change24h >= 0

                        onPtsChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
							    ctx.reset();
							    if (!pts || pts.length < 2) return;
							    w.drawSpark(ctx, pts, width, height, 5, 2.4,
							        isUp ? "#34C759" : "#FF3B30",
							        isUp ? "rgba(52, 199, 89, 0.15)" : "rgba(255, 59, 48, 0.15)",
							        10 * w.s);
                            var min = Math.min.apply(null, pts);
                            var max = Math.max.apply(null, pts);
                            var range = (max - min) || 1;

                            var strokeCol = isUp ? "#34C759" : "#FF3B30";
                            var fillCol = isUp ? "rgba(52, 199, 89, 0.15)" : "rgba(255, 59, 48, 0.15)";

                            ctx.beginPath();
                            for (var i = 0; i < pts.length; i++) {
                                var x = (i / (pts.length - 1)) * W;
                                var y = H - ((pts[i] - min) / range) * (H - 10) - 5;
                                if (i === 0) ctx.moveTo(x, y);
                                else ctx.lineTo(x, y);
                            }

                            ctx.lineWidth = 2.4;
                            ctx.strokeStyle = strokeCol;
                            ctx.stroke();

                            ctx.lineTo(W, H);
                            ctx.lineTo(0, H);
                            ctx.closePath();
                            ctx.fillStyle = fillCol;
                            ctx.fill();
                        }
                    }
                }
            }

            // Watchlist Section Header
            Item {
                width: parent.width
                height: 18 * w.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Markets Watchlist"
                    font.family: w.fam
                    font.pixelSize: 12 * w.s
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }
            }

            // Watchlist Rows
            Column {
                width: parent.width
                spacing: 5 * w.s

                Repeater {
                    model: Math.min(4, w.stockList.length)
                    delegate: Item {
                        id: lRowItem
                        required property int index
                        readonly property var ast: w.stockList[index]
                        width: parent.width
                        height: 28 * w.s

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: w.selectedIndex = lRowItem.index
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                text: lRowItem.ast.symbol
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: lRowItem.ast.name
                                font.family: w.fam
                                font.pixelSize: 10 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.formatPrice(lRowItem.ast.price, lRowItem.ast.currency)
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                font.weight: Font.DemiBold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18 * w.s
                                width: 52 * w.s
                                radius: 4.5 * w.s
                                color: (lRowItem.ast.change24h >= 0) ? "#34C759" : "#FF3B30"

                                Text {
                                    anchors.centerIn: parent
                                    text: (lRowItem.ast.change24h >= 0 ? "+" : "") + lRowItem.ast.change24h + "%"
                                    font.family: w.fam
                                    font.pixelSize: 9.5 * w.s
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

