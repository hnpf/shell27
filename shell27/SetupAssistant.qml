import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    property bool completed: false
    property bool checked: false
    property bool welcomeUpdate: false
    property bool appearancePreviewChanged: false

    function setAppearance(mode) {
        if (bar && bar.appearanceMode === mode) return;
        if (bar && bar.setAppearance) {
            bar.setAppearance(mode, false);
            appearancePreviewChanged = true;
        }
        else if (hub && hub.dock && hub.dock.setAppearance) hub.dock.setAppearance(mode);
        else if (bar) {
            bar.appearanceMode = mode;
            if (mode === "auto") bar.darkMode = bar.autoIsDark ? bar.autoIsDark() : (new Date().getHours() < 7 || new Date().getHours() >= 19);
            else bar.darkMode = mode === "dark";
        }
    }

    function registerWelcomeRule(force) {
        var rule = 'hl.window_rule({ name = "shell27-welcome-float", match = { title = "^(Welcome to shell27|shell27 Update)$" }, float = true, center = true, border_size = 0 })';
        Quickshell.execDetached(["hyprctl", "eval", force ? ("shell27_welcome_rule = " + rule) : ("shell27_welcome_rule = shell27_welcome_rule or " + rule)]);
    }

    function open() {
        welcomeUpdate = false;
        appearancePreviewChanged = false;
        win.visibility = Window.Windowed;
        win.visible = true;
        win.raise();
        win.requestActivate();
    }
    function finish() {
        if (appearancePreviewChanged && bar) {
            bar.setAppearance(bar.appearanceMode);
            if (bar.wallpaperAppearance === "auto" && bar.wpApplyAppearance) bar.wpApplyAppearance();
        }
        appearancePreviewChanged = false;
        completed = true;
        welcomeUpdate = false;
        win.visible = false;
        completeFile.setText("completed\n");
    }
    function showUpdate(version) {
        welcomeUpdate = true;
        appearancePreviewChanged = false;
        updateVersion = version || "new version";
        win.visibility = Window.Windowed;
        win.visible = true;
        win.raise();
        win.requestActivate();
    }

    property string updateVersion: ""
    FileView {
        id: completeFile
        path: Quickshell.env("HOME") + "/.config/shell27/.setup-completed"
        printErrors: false
        onLoaded: {
            root.completed = text().trim() === "completed";
            root.checked = true;
            if (!root.completed) Qt.callLater(root.open);
        }
        onLoadFailed: {
            root.completed = false;
            root.checked = true;
            Qt.callLater(root.open);
        }
    }
    Timer { id: ruleReload; interval: 400; onTriggered: root.registerWelcomeRule(true) }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") ruleReload.restart(); }
    }
    Component.onCompleted: root.registerWelcomeRule(false)

    IpcHandler {
        target: "welcome"
        function open() { root.open(); }
        function reset() { root.completed = false; completeFile.setText(""); root.open(); }
        function update(version: string) { root.showUpdate(version); }
    }

    Window {
        id: win
        title: root.welcomeUpdate ? "shell27 Update" : "Welcome to shell27"
        width: 540
        height: 470
        minimumWidth: 480
        minimumHeight: 440
        visible: false
        color: "transparent"
        visibility: Window.Windowed
        flags: Qt.Window | Qt.FramelessWindowHint
        onClosing: close => { close.accepted = false; root.finish(); }

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: root.bar && !root.bar.darkMode ? "#F5F5F7" : "#202023"
            border.width: 1
            border.color: root.bar && !root.bar.darkMode ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(1, 1, 1, 0.16)

            Item {
                id: titlebar
                anchors.top: parent.top
                width: parent.width
                height: 38
                Row {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Repeater {
                        model: [
                            { color: "#FF5F57", glyph: "×" },
                            { color: "#FEBC2E", glyph: "−" },
                            { color: "#28C840", glyph: "↗" }
                        ]
                        delegate: Rectangle {
                            id: control
                            required property var modelData
                            required property int index
                            width: 14
                            height: 14
                            radius: 7
                            color: (win.active || controlMouse.containsMouse) ? modelData.color : (root.bar && !root.bar.darkMode ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.2))
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.16)
                            Text {
                                anchors.centerIn: parent
                                text: control.modelData.glyph
                                color: Qt.rgba(0, 0, 0, 0.58)
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                opacity: controlMouse.containsMouse ? 1 : 0
                            }
                            MouseArea {
                                id: controlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (control.index === 0) root.finish();
                                    else if (control.index === 1) win.showMinimized();
                                    else win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen();
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: win.title
                    color: root.bar && !root.bar.darkMode ? "#55555A" : Qt.rgba(1, 1, 1, 0.66)
                    font.family: root.bar ? root.bar.fontFamily : "Open Runde"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onPressed: win.startSystemMove()
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.bar && !root.bar.darkMode ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.09)
                }
            }

            Column {
                anchors.top: titlebar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 34
                anchors.rightMargin: 34
                anchors.topMargin: 24
                spacing: 13

                Text {
                    text: root.welcomeUpdate ? "Updated to " + root.updateVersion : "Welcome to shell27"
                    color: root.bar && !root.bar.darkMode ? "#1D1D1F" : "#F5F5F7"
                    font.family: root.bar ? root.bar.fontFamily : "Open Runde"
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.welcomeUpdate
                        ? "The update is ready. Your settings and personal files were kept."
                        : "A macOS-inspired desktop shell for Hyprland. Choose a starting appearance, then personalize the rest in System Settings."
                    color: root.bar && !root.bar.darkMode ? "#55555A" : Qt.rgba(1, 1, 1, 0.65)
                    font.family: root.bar ? root.bar.fontFamily : "Open Runde"
                    font.pixelSize: 14
                    lineHeight: 1.3
                }
                Text {
                    text: "Appearance"
                    color: root.bar && !root.bar.darkMode ? "#1D1D1F" : "#F5F5F7"
                    font.family: root.bar ? root.bar.fontFamily : "Open Runde"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14
                    Repeater {
                        model: [
                            { mode: "light", label: "Light" },
                            { mode: "dark", label: "Dark" },
                            { mode: "auto", label: "Auto" }
                        ]
                        delegate: ThemePreview {
                            required property var modelData
                            mode: modelData.mode
                            label: modelData.label
                            selected: root.bar && root.bar.appearanceMode === mode
                            accent: root.bar ? root.bar.accent : "#0A84FF"
                            labelColor: root.bar && !root.bar.darkMode ? "#1D1D1F" : "#F5F5F7"
                            fontFamily: root.bar ? root.bar.fontFamily : "Open Runde"
                            onChosen: root.setAppearance(mode)
                        }
                    }
                }
                Text {
                    text: "Accent color"
                    color: root.bar && !root.bar.darkMode ? "#1D1D1F" : "#F5F5F7"
                    font.family: root.bar ? root.bar.fontFamily : "Open Runde"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Row {
                    spacing: 10
                    Repeater {
                        model: ["#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2", "#8E8E93"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 25
                            height: 25
                            radius: 13
                            color: modelData
                            border.width: root.bar && root.bar.accent.toString().toLowerCase() === modelData.toLowerCase() ? 3 : 1
                            border.color: "white"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.bar) root.bar.accent = parent.modelData }
                        }
                    }
                }
            }

            Item {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                height: 38
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Rectangle {
                        width: 170; height: 38; radius: 10
                        color: root.bar ? root.bar.accent : "#0A84FF"
                        Text { anchors.centerIn: parent; text: "Open Settings"; color: "white"; font.family: root.bar ? root.bar.fontFamily : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.finish(); if (root.bar && root.hub.dock) root.hub.dock.openPrefs("general"); } }
                    }
                    Rectangle {
                        width: 110; height: 38; radius: 10
                        color: root.bar && !root.bar.darkMode ? "#E5E5EA" : Qt.rgba(1, 1, 1, 0.12)
                        Text { anchors.centerIn: parent; text: "Done"; color: root.bar && !root.bar.darkMode ? "#1D1D1F" : "#F5F5F7"; font.family: root.bar ? root.bar.fontFamily : "Open Runde"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.finish() }
                    }
                }
            }
        }
    }
}