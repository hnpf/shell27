import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property string mode: dock ? dock.screenCornerMode : "always"
    readonly property int radius: 14

    Binding {
        target: root.hub
        property: "cornerWantsGeo"
        value: root.mode === "windowed"
        when: root.hub !== null
    }

    function hasFullscreen(screenName) {
        if (!hub || !hub.monData || !hub.glassClients) return false;
        var monitor = null;
        for (var i = 0; i < hub.monData.length; i++) {
            if (hub.monData[i].name === screenName) { monitor = hub.monData[i]; break; }
        }
        if (!monitor) return false;
        for (var j = 0; j < hub.glassClients.length; j++) {
            var client = hub.glassClients[j];
            if (client.mapped && !client.hidden && client.monitor === monitor.id
                    && monitor.activeWorkspace && client.workspace
                    && client.workspace.id === monitor.activeWorkspace.id
                    && (client.fullscreen === true || client.fullscreen === 2)) return true;
        }
        return false;
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.mode !== "disabled" && !(root.hub && root.hub.startupSplashVisible)
                && !(root.mode === "windowed" && root.hasFullscreen(modelData.name))
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region { }
            WlrLayershell.namespace: "macscreen-corners"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    var r = Math.min(root.radius, width / 2, height / 2);
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = "#000000";
                    ctx.fillRect(0, 0, width, height);
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.beginPath();
                    ctx.moveTo(r, 0);
                    ctx.lineTo(width - r, 0);
                    ctx.arc(width - r, r, r, -Math.PI / 2, 0, false);
                    ctx.lineTo(width, height - r);
                    ctx.arc(width - r, height - r, r, 0, Math.PI / 2, false);
                    ctx.lineTo(r, height);
                    ctx.arc(r, height - r, r, Math.PI / 2, Math.PI, false);
                    ctx.lineTo(0, r);
                    ctx.arc(r, r, r, Math.PI, Math.PI * 1.5, false);
                    ctx.closePath();
                    ctx.fill();
                    ctx.globalCompositeOperation = "source-over";
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
        }
    }
}