// LiquidScrollBar — macOS-style overlay scroller for any Flickable / ListView / GridView.
// Supports both vertical (default) and horizontal (horizontal: true) orientation.
import QtQuick

Item {
    id: sb
    property Flickable flick: null
    property string material: "liquid"
    property bool dark: true
    property bool alwaysVisible: false
    property bool compact: false
    property bool horizontal: false

    width: horizontal ? undefined : (compact ? 12 : 16)
    height: horizontal ? (compact ? 12 : 16) : undefined

    readonly property real viewLen: flick ? (horizontal ? flick.width : flick.height) : 1
    readonly property real contentLen: flick ? Math.max(horizontal ? flick.contentWidth : flick.contentHeight, 1) : 1
    readonly property real originPos: flick ? (horizontal ? flick.originX : flick.originY) : 0
    readonly property real scrollPos: flick ? (horizontal ? flick.contentX : flick.contentY) : 0
    readonly property real trackLen: horizontal ? width : height

    readonly property real ratio: flick ? Math.min(1, viewLen / contentLen) : 1
    readonly property real thumbLen: Math.max(compact ? 24 : 36, ratio * Math.max(1, trackLen - 8))
    readonly property real travel: Math.max(1, contentLen - viewLen)
    readonly property real frac: flick ? Math.max(0, Math.min(1, (scrollPos - originPos) / travel)) : 0

    visible: flick !== null && flick.visible && ratio < 0.999

    readonly property bool hot: ma.containsMouse || ma.pressed
    property bool awake: false
    opacity: awake || hot ? 1 : (alwaysVisible ? 0.65 : 0)
    Behavior on opacity { NumberAnimation { duration: sb.opacity < 0.5 ? 160 : 380; easing.type: Easing.OutCubic } }
    Timer { id: sleep; interval: 950; onTriggered: sb.awake = false }

    Connections {
        target: sb.flick
        function onContentYChanged() { if (!sb.horizontal) { sb.awake = true; sleep.restart(); } }
        function onContentXChanged() { if (sb.horizontal) { sb.awake = true; sleep.restart(); } }
    }

    property real glass: hot ? 1 : 0
    Behavior on glass { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    readonly property bool liquid: material === "liquid" || material === "custom"
    readonly property real lens: material === "opaque" ? 0 : glass

    // Subtle frosted glass track capsule on hover
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.min(width, height) / 2
        opacity: sb.glass * 0.75
        color: sb.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
        border.width: 1
        border.color: sb.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
        visible: opacity > 0.01
    }

    // Liquid Glass Thumb
    Rectangle {
        id: thumb
        readonly property real thick: (sb.compact ? 4 : 6) + (sb.compact ? 3 : 4) * sb.glass
        x: sb.horizontal ? (4 + sb.frac * Math.max(0, sb.width - 8 - sb.thumbLen)) : (sb.width - thick - 2.5)
        y: sb.horizontal ? (sb.height - thick - 2.5) : (4 + sb.frac * Math.max(0, sb.height - 8 - sb.thumbLen))
        width: sb.horizontal ? sb.thumbLen : thick
        height: sb.horizontal ? thick : sb.thumbLen
        radius: thick / 2

        readonly property real ink: sb.dark ? 1 : 0
        color: sb.liquid
               ? Qt.rgba(ink, ink, ink, (sb.dark ? 0.30 : 0.24) + (sb.dark ? 0.16 : 0.18) * sb.lens)
               : Qt.rgba(ink, ink, ink, 0.40 + 0.15 * sb.glass)
        border.width: 0.8 + 0.4 * sb.lens
        border.color: sb.dark
                      ? Qt.rgba(1, 1, 1, 0.22 + 0.38 * sb.lens)
                      : Qt.rgba(1, 1, 1, 0.45 + 0.35 * sb.lens)

        // Specular glass highlight strip
        Rectangle {
            visible: sb.liquid
            opacity: 0.35 + 0.5 * sb.lens
            x: sb.horizontal ? 4 : 1.2
            y: sb.horizontal ? 1.2 : 4
            width: sb.horizontal ? Math.max(0, parent.width - 8) : Math.max(1.5, parent.width * 0.38)
            height: sb.horizontal ? Math.max(1.5, parent.height * 0.38) : Math.max(0, parent.height - 8)
            radius: Math.min(width, height) / 2
            gradient: Gradient {
                orientation: sb.horizontal ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.55) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: containsMouse || pressed ? Qt.PointingHandCursor : Qt.ArrowCursor
        property real grab: 0

        function scrollTo(pos) {
            if (!sb.flick) return;
            var maxSpan = Math.max(1, sb.trackLen - 8 - sb.thumbLen);
            var f = Math.max(0, Math.min(1, (pos - 4 - grab) / maxSpan));
            if (sb.horizontal) sb.flick.contentX = sb.originPos + f * sb.travel;
            else sb.flick.contentY = sb.originPos + f * sb.travel;
        }

        onPressed: mouse => {
            if (sb.horizontal) {
                grab = (mouse.x >= thumb.x && mouse.x <= thumb.x + thumb.width) ? (mouse.x - thumb.x) : (sb.thumbLen / 2);
                scrollTo(mouse.x);
            } else {
                grab = (mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height) ? (mouse.y - thumb.y) : (sb.thumbLen / 2);
                scrollTo(mouse.y);
            }
        }
        onPositionChanged: mouse => {
            if (pressed) scrollTo(sb.horizontal ? mouse.x : mouse.y);
        }
        onWheel: wheel => { wheel.accepted = false; }
    }
}
