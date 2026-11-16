// macOS Reminders widget for desktop
import QtQuick
import QtQuick.Effects

Item {
    id: w

    property string style: "liquid"
    property string size: "medium"
    property real scaleF: 1.0
    property string fam: "Inter"
    property real screenX: x
    property real screenY: y
    property bool preview: false
    property bool editing: false
    property bool adding: false

    // host / hub
    property var host: null
    property var remindersModel: null
    property int openCount: 0

    signal openRemindersApp()
    signal addReminder(string text)
    signal toggleReminder(int line)
    signal deleteReminder(int line)

    // liquid glass inputs
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

    width: (isSmall ? 158 : (isMedium ? 338 : 358)) * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    height: (isLarge ? 354 : 168) * scaleF

    readonly property real radiusPx: 28 * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1))
    readonly property bool glassOn: style === "liquid" && glassReady && !preview && wallUrl != ""
    readonly property bool dark: style === "dark" || (style === "liquid" && darkGlass)

    readonly property color fg: dark ? "white" : "#1D1D1F"
    readonly property color fg2: dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color blue: "#0A84FF"
    // Match Weather's glass grading exactly.
    readonly property real tint: Math.min(0.92, dark ? 0.06 + glassOpacity * 0.5
                                                     : 0.45 + glassOpacity * 0.9)

    // ── background ──
    Rectangle {
        anchors.fill: parent
        visible: w.style !== "liquid"
        radius: w.radiusPx
        color: w.dark ? "#1C1C1E" : "#F2F2F7"
        border.width: 1
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
    }

    Rectangle {
        anchors.fill: parent
        visible: w.style === "liquid" && !w.glassOn
        radius: w.radiusPx
        color: w.dark ? Qt.rgba(0.18, 0.18, 0.20, 0.85) : Qt.rgba(0.96, 0.96, 0.98, 0.90)
        border.width: 1
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
    }

    Loader {
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            // This is intentionally the same capture lifecycle as WeatherWidget.
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
                    if (gl.capStep === 0) backdropSource.scheduleUpdate(); else blurred.scheduleUpdate();
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
                    width: w.screenW
                    height: w.screenH
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

            // The wallpaper crop is a texture source only.  Keeping it hidden is essential:
            // otherwise its oversized capture rectangle paints over neighbouring widgets.
            ShaderEffectSource {
                id: backdropSource
                sourceItem: backdrop
                hideSource: true
                live: gl.streaming
                visible: false
                textureSize: Qt.size(Math.max(1, Math.round(backdrop.width * gl.ds)),
                                     Math.max(1, Math.round(backdrop.height * gl.ds)))
            }
            MultiEffect {
                id: blurFx
                source: backdropSource
                width: backdrop.width * gl.ds
                height: backdrop.height * gl.ds
                blurEnabled: true
                blurMax: 64
                blur: gl.bn
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource {
                id: blurred
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
                property real rimTint: 1
                property real ringW: 0
                property real flatInner: 1
            }
        }
    }

    // Same edge treatment as Weather's liquid-glass widget.
    CornerBorder {
        z: 2
        anchors.fill: parent
        cornerR: w.radiusPx
        dark: w.dark
        tint: w.borderTint
        lineW: 0.8
    }

    // ── content ──
    Item {
        anchors.fill: parent
        anchors.margins: 16

        Item {
            id: rHead
            width: parent.width
            height: cnt.height

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - cnt.width - addBtn.width - 14
                elide: Text.ElideRight
                text: "Reminders"
                color: w.blue
                font.family: w.fam
                font.pixelSize: 14
                font.weight: Font.Bold
            }

            Text {
                id: cnt
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "" + w.openCount
                color: w.blue
                font.family: w.fam
                font.pixelSize: 22
                font.weight: Font.Bold
            }

            Rectangle {
                id: addBtn
                anchors.right: cnt.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                visible: opacity > 0.01
                opacity: w.editing ? 0 : ((headHover.hovered || w.adding) ? 1 : 0)
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                color: addMa.containsMouse ? Qt.rgba(w.blue.r, w.blue.g, w.blue.b, 0.22) : "transparent"
                rotation: w.adding ? 45 : 0
                Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                scale: addMa.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                Rectangle { anchors.centerIn: parent; width: 11; height: 1.7; radius: 1; color: w.blue }
                Rectangle { anchors.centerIn: parent; width: 1.7; height: 11; radius: 1; color: w.blue }

                MouseArea {
                    id: addMa
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { w.adding = !w.adding; if (w.adding) newInput.forceActiveFocus(); }
                }
            }

            HoverHandler { id: headHover }

            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: addBtn.width + 12
                enabled: !w.editing
                cursorShape: Qt.PointingHandCursor
                onClicked: w.openRemindersApp()
            }
        }

        Flickable {
            id: remFlick
            y: rHead.height + 6
            width: parent.width
            height: parent.height - y
            clip: true
            contentHeight: remCol.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: !w.editing && contentHeight > height + 2

            Column {
                id: remCol
                width: parent.width
                spacing: 7

                Item {
                    width: parent.width
                    height: w.adding ? 22 : 0
                    clip: true
                    opacity: w.adding ? 1 : 0
                    Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 220 } }

                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"; border.width: 1.5; border.color: w.fg2
                    }
                    TextInput {
                        id: newInput
                        x: 24; width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        color: w.fg; font.family: w.fam; font.pixelSize: 13
                        selectByMouse: false
                        onAccepted: { w.addReminder(text); text = ""; }
                        Keys.onEscapePressed: { text = ""; w.adding = false; }
                        Text { visible: parent.text === ""; text: "New Reminder"; color: w.fg2; font: parent.font }
                    }
                }

                Repeater {
                    model: w.remindersModel
                    delegate: Row {
                        id: remRow
                        required property int index
                        required property int line
                        required property bool done
                        required property string text
                        spacing: 8
                        width: parent.width
                        property real inT: 1
                        opacity: inT

                        Rectangle {
                            id: tick
                            width: 16; height: 16; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property bool done: remRow.done
                            property real fill: done ? 1 : 0
                            Behavior on fill { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                            color: Qt.rgba(w.blue.r, w.blue.g, w.blue.b, fill)
                            border.width: 1.5
                            border.color: done ? w.blue : w.fg2
                            Behavior on border.color { ColorAnimation { duration: 240 } }

                            property real press: 0
                            scale: (0.86 + 0.14 * Math.max(fill, 1 - fill * 0)) * (1 - 0.18 * press)
                            SequentialAnimation {
                                id: tickPop
                                NumberAnimation { target: tick; property: "press"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                                NumberAnimation { target: tick; property: "press"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                            }

                            Canvas {
                                id: tickMark
                                anchors.centerIn: parent
                                width: 11; height: 11
                                property real draw: tick.fill
                                onDrawChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.reset();
                                    if (draw <= 0.01) return;
                                    c.strokeStyle = "white"; c.lineWidth = 1.9; c.lineCap = "round"; c.lineJoin = "round";
                                    var p = [[1.6, 5.6], [4.3, 8.4], [9.4, 2.6]];
                                    var d = Math.max(0, Math.min(1, (draw - 0.15) / 0.85));
                                    c.beginPath(); c.moveTo(p[0][0], p[0][1]);
                                    var t1 = Math.min(1, d / 0.4);
                                    c.lineTo(p[0][0] + (p[1][0] - p[0][0]) * t1, p[0][1] + (p[1][1] - p[0][1]) * t1);
                                    if (d > 0.4) {
                                        var t2 = (d - 0.4) / 0.6;
                                        c.lineTo(p[1][0] + (p[2][0] - p[1][0]) * t2, p[1][1] + (p[2][1] - p[1][1]) * t2);
                                    }
                                    c.stroke();
                                }
                            }

                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                enabled: !w.editing; cursorShape: Qt.PointingHandCursor
                                onClicked: { tickPop.restart(); w.toggleReminder(remRow.line); }
                            }
                        }

                        Item {
                            width: parent.width - 24
                            height: Math.max(rowTxt.implicitHeight, 18)
                            anchors.verticalCenter: parent.verticalCenter
                            HoverHandler { id: rowHover; enabled: !w.editing }

                            Text {
                                id: rowTxt
                                width: parent.width - (rowHover.hovered ? 20 : 0)
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: remRow.text
                                font.strikeout: remRow.done
                                color: remRow.done ? w.fg2 : w.fg
                                font.family: w.fam
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent; anchors.rightMargin: 22
                                enabled: !w.editing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: w.openRemindersApp()
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u00D7"
                                color: w.fg2
                                font.family: w.fam
                                font.pixelSize: 15
                                opacity: rowHover.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }

                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -5
                                    enabled: rowHover.hovered
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: w.deleteReminder(remRow.line)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

