import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string text: "Your message goes here"
    property color fill: "#26252A"
    property color ink: "white"
    property real maxWidth: Infinity
    property int fontPixelSize: 14

    // right edge of the body, svg had 330.585 for this exact string
    readonly property real contentWidth: Math.max(45, maxWidth - 53.98)
    readonly property real r: 20.06 + Math.min(label.implicitWidth, contentWidth) + 25.28
    readonly property real t: r - 330.585

    implicitWidth: Math.min(maxWidth, r + 8.7)
    // 10 px above and below keeps wrapped text clear of the outline.
    implicitHeight: Math.max(40, label.implicitHeight + 20)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.fill
            strokeColor: root.fill
            strokeWidth: 0.806

            PathSvg {
                path: {
                    const f = x => (x + root.t).toFixed(3)
                    const d = root.implicitHeight - 60
                    const y = n => n <= 20.0556 ? n.toFixed(3) : (n + d).toFixed(3)
                    return `M20.0556 0.4029 H${f(310.933)}
                        A19.6526 19.6526 0 0 1 ${f(330.585)} 20.0556
                        V${y(39.7609)}
                        C${f(330.586)} ${y(41.0422)} ${f(330.463)} ${y(42.2948)} ${f(330.229)} ${y(43.5077)}
                        L${f(330.327)} ${y(43.3812)}
                        C${f(330.068)} ${y(52.6903)} ${f(337.05)} ${y(57.3449)} ${f(338.86)} ${y(58.1207)}
                        C${f(332.288)} ${y(59.3156)} ${f(326.849)} ${y(57.1673)} ${f(323.456)} ${y(54.9073)}
                        C${f(320.056)} ${y(57.722)} ${f(315.692)} ${y(59.4136)} ${f(310.933)} ${y(59.4136)}
                        H20.0556
                        A19.6526 19.6526 0 0 1 0.4029 ${y(39.7609)}
                        V20.0556
                        A19.6526 19.6526 0 0 1 20.0556 0.4029 Z`
                }
            }
        }
    }

    Text {
        id: label
        x: 20.06
        y: (root.implicitHeight - implicitHeight) / 2
        width: root.contentWidth
        text: root.text
        color: root.ink
        font.family: "Open Runde"
        font.pixelSize: root.fontPixelSize
        wrapMode: Text.WordWrap
    }
}
