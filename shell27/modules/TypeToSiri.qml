import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../I18n.js" as I18n

Scope {
    id: root

    // Reference to SiriEdgeGlow component
    property var edgeGlow: null
    property var hub: null

    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property var sources: []
    property bool glassFailed: false
    readonly property var dock: hub && hub.dock ? hub.dock : null
    readonly property bool liquidGlassReady: dock ? dock.settingsGlass && !glassFailed : false
    readonly property url liquidGlassShader: dock ? dock.glassShaderUrl : Qt.resolvedUrl("../shaders/liquidglass.frag.qsb")

    // State properties
    property bool isOpen: false
    property string prompt: ""
    property string response: ""
    property bool isThinking: false
    property var messages: []
    property string pendingPrompt: ""
    property int editingMessageIndex: -1
    property bool chatStarted: false
    property bool keyboardInputEnabled: false
    property bool speechMuted: false
    property bool keyboardModeVisible: false
    property bool voiceOnlyMode: false
    property real chatBackdropStrength: 1.0

    Behavior on chatBackdropStrength {
        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
    }

    Timer {
        id: chatBackdropSettle
        interval: 0
        onTriggered: root.chatBackdropStrength = 0.56
    }

    // Smooth open/close animation
    property real animProgress: 0.0
    Behavior on animProgress {
        NumberAnimation {
            duration: root.isOpen ? 280 : 220
            easing.type: Easing.OutCubic
        }
    }

    // Running clock for GLSL flowing border animation (Only runs when open)
    property real animTime: 0.0
    FrameAnimation {
        running: root.isOpen && root.animProgress > 0.001
        onTriggered: {
            root.animTime += 0.016;
            if (root.animTime > 10000.0) root.animTime = 0.0;
        }
    }

    onIsOpenChanged: {
        animProgress = isOpen ? 1.0 : 0.0;
        if (isOpen) {
            keyboardModeVisible = false;
            if (edgeGlow) {
                edgeGlow.active = true;
                if (edgeGlow.siriState === "idle") {
                    edgeGlow.siriState = "listening";
                }
            }
        } else {
            isThinking = false;
            dragOffsetX = 0;
            dragOffsetY = 0;
            sources = [];
            cleanupMessageImages();
            messages = [];
            pendingPrompt = "";
            chatStarted = false;
            editingMessageIndex = -1;
            keyboardInputEnabled = false;
            keyboardModeVisible = false;
            voiceOnlyMode = false;
        }
    }

    // Public functions
    function open() {
        dragOffsetX = 0;
        dragOffsetY = 0;
        keyboardModeVisible = false;
        isOpen = true;
    }

    function close() {
        isOpen = false;
        prompt = "";
        response = "";
        isThinking = false;
        sources = [];
        messages = [];
        pendingPrompt = "";
        chatStarted = false;
        editingMessageIndex = -1;
        keyboardInputEnabled = false;
        keyboardModeVisible = false;
        voiceOnlyMode = false;
        voiceProc.running = false;
        if (edgeGlow) edgeGlow.dismiss();
    }

    function openChat() {
        dragOffsetX = 0;
        dragOffsetY = 0;
        chatStarted = true;
        keyboardInputEnabled = false;
        keyboardModeVisible = false;
        isOpen = true;
    }

    function openKeyboardChat() {
        chatStarted = true;
        keyboardInputEnabled = true;
        keyboardModeVisible = true;
        isOpen = true;
    }

    function startVoiceChat() {
        chatStarted = true;
        keyboardInputEnabled = false;
        isOpen = true;
        if (!voiceProc.running) voiceProc.running = true;
    }

    function toggleVoiceOnly() {
        if (voiceOnlyMode) {
            voiceProc.running = false;
            voiceTimeout();
            return;
        }
        dragOffsetX = 0;
        dragOffsetY = 0;
        voiceOnlyMode = true;
        chatStarted = false;
        keyboardInputEnabled = false;
        keyboardModeVisible = false;
        isOpen = true;
        voiceProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--voice-only"];
        voiceProc.running = true;
    }

    function voiceTimeout(reason) {
        voiceOnlyMode = false;
        isThinking = false;
        chatStarted = true;
        keyboardInputEnabled = false;
        pendingPrompt = "";
        messages = [];
        if (reason && reason !== "") {
            prompt = "";
            response = "";
            appendMessage("assistant", reason);
            isOpen = true;
            if (edgeGlow) {
                edgeGlow.siriState = "idle";
                edgeGlow.active = true;
            }
        } else {
            prompt = "";
            response = "";
            if (edgeGlow) {
                edgeGlow.siriState = "idle";
                edgeGlow.active = false;
            }
        }
    }

    function isVoiceStatusPrompt(text: string) {
        return text === "Listening..."
            || text === "Processing speech..."
            || text === "Processing request..."
            || text === "Listening timed out. Press Space to type."
            || text === "Sorry, could not understand audio."
            || text.indexOf("No microphone was found.") === 0;
    }

    function receiveVoicePrompt(text: string) {
        var cleanText = text.trim();
        if (voiceOnlyMode && cleanText !== "" && !isVoiceStatusPrompt(cleanText)) {
            voiceOnlyMode = false;
            chatStarted = true;
            keyboardInputEnabled = false;
            pendingPrompt = cleanText;
            prompt = cleanText;
            return;
        }
        prompt = cleanText;
    }

    function toggleSpeechMute() {
        speechMuted = !speechMuted;
        muteProc.command = [
            "python3",
            Quickshell.env("HOME") + "/.config/quickshell/shell27/scripts/siri_daemon.py",
            "--set-voice-muted", speechMuted ? "true" : "false"
        ];
        muteProc.running = true;
    }

    function appendMessage(role, text) {
        if (!text || text.trim() === "") return;
        var last = messages.length > 0 ? messages[messages.length - 1] : null;
        if (last && last.role === role && String(last.text) === String(text)) return;
        messages = messages.concat([{ role: role, text: text }]);
    }

    function syncWithSiriApp(role, text) {
        if (hub && hub.siriApp && hub.siriApp.appendIntelligenceMessage)
            hub.siriApp.appendIntelligenceMessage(role, text);
    }

    function cleanupMessageImages(replaceWithNotice) {
        var nextMessages = messages.slice();
        var changed = false;
        for (var i = 0; i < messages.length; i++) {
            if (!messages[i].imagePath) continue;
            Quickshell.execDetached(["rm", "-f", String(messages[i].imagePath)]);
            nextMessages[i] = {
                role: "user",
                text: replaceWithNotice && messages[i].showImage ? "Image shared privately" : String(messages[i].text || ""),
                showImage: false
            };
            changed = true;
        }
        if (changed) messages = nextMessages;
    }

    function copyMessage(text) {
        Quickshell.execDetached(["wl-copy", text]);
    }

    function receiveResponse(text: string) {
        response = text;
        if (text === "Processing request...") return;
        if (pendingPrompt === "" && prompt !== "" && !isVoiceStatusPrompt(prompt)) {
            appendMessage("user", prompt);
            syncWithSiriApp("user", prompt);
        }
        if (text !== "" && text !== "Processing request...") {
            appendMessage("assistant", text);
            syncWithSiriApp("assistant", text);
        }
        if (hub && hub.aiSettings && hub.aiSettings.deleteVisualImageAfterResponse) cleanupMessageImages(true);
        pendingPrompt = "";
        isThinking = false;
    }

    function setSources(value) {
        var parsed = value;
        if (typeof value === "string") {
            try { parsed = JSON.parse(value); } catch (e) { parsed = []; }
        }
        var valid = [];
        if (Array.isArray(parsed)) {
            for (var i = 0; i < parsed.length && valid.length < 2; i++) {
                var url = String(parsed[i] || "").trim();
                if (url.indexOf("https://") === 0 && valid.indexOf(url) < 0) valid.push(url);
            }

        }
        sources = valid;
    }

    function faviconUrl(url) {
        var host = String(url).replace(/^https:\/\//i, "").split(/[/?#]/)[0];
        return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(host) + "&sz=64";
    }

    function openSources() {
        for (var i = 0; i < sources.length; i++) Qt.openUrlExternally(sources[i]);
    }

    function toggle() {
        if (isOpen) close();
        else open();
    }

    function ask(text: string) {
        if (!text || text.trim() === "") return;
        var cleanPrompt = text.trim();
        prompt = cleanPrompt;
        response = "";
        pendingPrompt = cleanPrompt;
        if (editingMessageIndex >= 0 && editingMessageIndex < messages.length) {
            var revisedMessages = messages.slice(0, editingMessageIndex);
            revisedMessages.push({ role: "user", text: cleanPrompt });
            messages = revisedMessages;
        } else {
            appendMessage("user", cleanPrompt);
        }
        syncWithSiriApp("user", cleanPrompt);
        editingMessageIndex = -1;
        sources = [];
        chatStarted = true;
        keyboardInputEnabled = false;
        isThinking = true;
        chatBackdropSettle.stop();
        chatBackdropStrength = 1.0;
        isOpen = true;

        if (edgeGlow) {
            edgeGlow.active = true;
            edgeGlow.siriState = "thinking";
            edgeGlow.userPrompt = cleanPrompt;
            edgeGlow.siriResponse = "";
        }

        queryProc.command = [
            "python3",
            Quickshell.env("HOME") + "/.config/quickshell/shell27/scripts/siri_daemon.py",
            "--query", cleanPrompt
        ];
        queryProc.running = true;
    }

    function askVisual(text: string, imagePath: string, showImage: bool) {
        if (!text || text.trim() === "" || !imagePath || imagePath.trim() === "") return;
        var cleanPrompt = text.trim();
        prompt = cleanPrompt;
        response = "";
        pendingPrompt = cleanPrompt;
        messages = messages.concat([{ role: "user", text: showImage ? "" : cleanPrompt, imagePath: imagePath, showImage: showImage }]);
        syncWithSiriApp("user", cleanPrompt || "Image shared");
        editingMessageIndex = -1;
        sources = [];
        chatStarted = true;
        keyboardInputEnabled = false;
        keyboardModeVisible = false;
        isThinking = true;
        chatBackdropSettle.stop();
        chatBackdropStrength = 1.0;
        isOpen = true;

        if (edgeGlow) {
            edgeGlow.active = true;
            edgeGlow.siriState = "thinking";
            edgeGlow.userPrompt = cleanPrompt;
            edgeGlow.siriResponse = "";
        }
    }

    // Background Process to execute query via siri_daemon.py
    Process {
        id: queryProc
        running: false
        onExited: {
            root.isThinking = false;
        }
    }

    Process {
        id: voiceProc
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--awake"]
        // Keep voice-only mode alive until the Python side explicitly calls SiriIPC.voice_timeout() or a spoken
        // command converts it back to the normal Siri chat UI. The process is intentionally one-shot; auto-closing
        // here makes it snap back immediately after the initial mic cycle.
    }

    Process { id: muteProc; running: false }
    Process {
        id: muteStateProc
        running: true
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--get-voice-muted"]
        stdout: StdioCollector {
            onStreamFinished: root.speechMuted = text.trim() === "true"
        }
    }
    Process {
        id: stopSpeechProc
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--stop-speech"]
    }

    // ══════════════════════════════════════════════════════════════════
    // FULLSCREEN OVERLAY ON EVERY SCREEN
    // ══════════════════════════════════════════════════════════════════
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            property bool copyHintVisible: false
            property string copyHintText: "Copy"
            property real copyHintX: 0
            property real copyHintY: 0

            function showCopyHint(button, text) {
                copyHintText = text;
                var point = button.mapToItem(null, button.width / 2, 0);
                copyHintX = Math.max(8, Math.min(win.width - copyHint.width - 8, point.x - copyHint.width / 2));
                copyHintY = Math.max(8, point.y - copyHint.height - 6);
                copyHintVisible = true;
            }

            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "type-to-siri"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Shortcut { sequence: "Escape"; onActivated: root.close() }

            visible: root.isOpen || root.animProgress > 0.001

            // Click-through everywhere EXCEPT the pill and response popup
            mask: Region {
                    item: root.isOpen ? (root.voiceOnlyMode ? voiceOrbContainer : pillContainer) : emptyMask
            }
            Item { id: emptyMask; width: 0; height: 0 }

            // Click outside pill to dismiss
            MouseArea {
                anchors.fill: parent
                z: 0
                onClicked: root.close()
            }

                // ── DRAGGABLE FLOATING CONTAINER (Top-Centered) ──
            Item {
                id: pillContainer
                z: 10

                width: root.isThinking && !root.chatStarted ? 142 : (root.chatStarted ? Math.min(393, win.width - 32) : Math.min(420, win.width - 32))
                height: root.isThinking && !root.chatStarted ? 50 : (root.chatStarted ? Math.min(562, win.height - 110) : 64)

                x: (win.width - width) / 2 + root.dragOffsetX
                y: 82 + root.dragOffsetY

                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 460; easing.type: Easing.OutCubic } }

                // Opacity & Scale entrance animation
                opacity: root.animProgress
                scale: 0.95 + 0.05 * root.animProgress
                visible: !root.voiceOnlyMode

                Rectangle {
                    id: glassBg
                    anchors.fill: parent
                    radius: !root.chatStarted ? height / 2 : 32
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(0.004, 0.005, 0.008, 0.93) }
                        GradientStop { position: 0.32; color: Qt.rgba(0.008, 0.01, 0.014, 0.68) }
                        GradientStop { position: 0.70; color: Qt.rgba(0.012, 0.016, 0.022, 0.25) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.018, 0.022, 0.03, 0.0) }
                    }
                }

                // Capture the desktop beneath this overlay so every Siri surface
                // uses real backdrop pixels for the glass blur.
                SafeCapture {
                    id: siriBackdrop
                    width: win.width
                    height: win.height
                    opacity: 0
                    want: root.isOpen && !(root.hub && root.hub.storm) ? win.modelData : null
                    wantLive: root.isOpen
                    paintCursor: false
                }

                ShaderEffectSource {
                    id: siriBackdropSource
                    sourceItem: siriBackdrop
                    hideSource: true
                    live: true
                    mipmap: true
                    visible: false
                }

                ShaderEffectSource {
                    id: glassGradientSource
                    sourceItem: glassBg
                    hideSource: false
                    live: true
                    mipmap: true
                    visible: false
                }

                GlassSlab {
                    anchors.fill: parent
                    z: 1
                    visible: root.liquidGlassReady
                    glass: true
                    shaderUrl: root.liquidGlassShader
                    src: siriBackdrop.hasContent ? siriBackdropSource : glassGradientSource
                    srcSize: siriBackdrop.hasContent ? Qt.size(win.width, win.height) : Qt.size(pillContainer.width, pillContainer.height)
                    origin: siriBackdrop.hasContent ? Qt.point(pillContainer.x, pillContainer.y) : Qt.point(0, 0)
                    baseColor: "#090B10"
                    dark: true
                    cornerR: !root.chatStarted ? pillContainer.height / 2 : 32
                    thickness: 13
                    strengthMul: 0.7
                    liquid: root.dock ? root.dock.glassLiquid : 1.0
                    rim: root.dock ? root.dock.glassRim * 0.25 : 0.12
                    grain: root.dock ? root.dock.glassGrain : 0.03
                    tint: root.dock ? root.dock.glassOpacity : 0.55
                    blurPx: root.dock ? root.dock.glassBlur + 10 : 14
                    flatInner: 1
                    opacity: 0.78 * (root.chatStarted && !root.isThinking ? root.chatBackdropStrength : 1.0)
                    onFailed: root.glassFailed = true
                }

                // This tint remains above the glass shader, which keeps the
                // black top-to-clear-bottom fade visible in chat and working.
                Rectangle {
                    anchors.fill: parent
                    z: 2
                    opacity: root.chatStarted && !root.isThinking ? root.chatBackdropStrength : 1.0
                    radius: root.isThinking || !root.chatStarted ? height / 2 : 32
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
                        GradientStop { position: 0.58; color: Qt.rgba(0, 0, 0, 0.10) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    }
                }

                component SiriControlGlass: GlassSlab {
                    property bool calm: root.chatStarted
                    anchors.fill: parent
                    z: 0
                    visible: root.liquidGlassReady
                    // Chat controls use the slab's quiet fallback instead of
                    // live refraction, so they do not echo the monitor ring.
                    glass: !calm
                    shaderUrl: root.liquidGlassShader
                    src: siriBackdrop.hasContent ? siriBackdropSource : glassGradientSource
                    srcSize: siriBackdrop.hasContent ? Qt.size(win.width, win.height) : Qt.size(pillContainer.width, pillContainer.height)
                    origin: mapToItem(null, 0, 0)
                    baseColor: "#141720"
                    dark: true
                    cornerR: parent.radius
                    thickness: calm ? 6 : 9
                    strengthMul: calm ? 0.18 : 0.55
                    liquid: calm ? 0.16 : (root.dock ? root.dock.glassLiquid : 1.0)
                    rim: root.dock ? root.dock.glassRim * 0.35 : 0.16
                    grain: root.dock ? root.dock.glassGrain : 0.03
                    tint: 0.42
                    blurPx: root.dock ? root.dock.glassBlur + 8 : 12
                    saturation: calm ? 0.24 : 1.0
                    flatInner: 1
                }

                // Compact working state: six dots orbit a circle while the label gently breathes.
                Row {
                    id: workingState
                    anchors.centerIn: parent
                    spacing: 11
                    visible: root.isThinking && !root.chatStarted
                    z: 10

                    Item {
                        id: circularSpinner
                        width: 26
                        height: 26
                        Repeater {
                            model: 6
                            delegate: Rectangle {
                                required property int index
                                width: 4.5
                                height: 4.5
                                radius: 2.25
                                x: circularSpinner.width / 2 + Math.cos(index * Math.PI / 3) * 8 - width / 2
                                y: circularSpinner.height / 2 + Math.sin(index * Math.PI / 3) * 8 - height / 2
                                color: "#F5F7FF"
                                scale: 0.62 + 0.62 * (0.5 + 0.5 * Math.sin(root.animTime * 5 - index * 0.9))
                                opacity: 0.28 + 0.72 * (0.5 + 0.5 * Math.sin(root.animTime * 5 - index * 0.9))
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Working…")
                        color: "white"
                        font.family: "Open Runde"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        opacity: 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(root.animTime * 2.2))
                    }
                }

                // Conversation history expands above the follow-up field after a response arrives.
                Item {
                    id: bubbleBox
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: pillBox.top
                    width: parent.width
                    visible: root.chatStarted
                    z: 4

                    Column {
                        id: bubbleCol
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        anchors.topMargin: 22
                        anchors.bottomMargin: 12
                        spacing: 14

                        Item {
                            width: parent.width
                            height: 24

                            Rectangle {
                                id: closeButton
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 14
                                color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                                SiriControlGlass { }
                                Text { anchors.centerIn: parent; text: "×"; color: Qt.rgba(1, 1, 1, 0.88); font.pixelSize: 20; font.weight: Font.Light }
                                HoverHandler { id: closeHover }
                                TapHandler {
                                    onTapped: root.close()
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "Siri"
                                color: Qt.rgba(1, 1, 1, 0.92)
                                font.family: "Open Runde"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: Math.max(80, bubbleCol.height - 24 - sourceAction.height - 54)
                            contentWidth: width
                            contentHeight: chatContent.height
                            clip: true
                            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                            Column {
                                id: chatContent
                                width: parent.width
                                height: implicitHeight
                                spacing: 12

                                Repeater {
                                    model: root.messages
                                    delegate: Item {
                                        required property var modelData
                                        required property int index
                                        width: chatContent.width
                                        readonly property real messageHeight: modelData.role === "user"
                                            ? (modelData.imagePath && modelData.showImage ? userImageFrame.implicitHeight : userBubble.implicitHeight)
                                            : assistantResponse.implicitHeight
                                        height: messageHeight + messageActions.height
                                        opacity: 0
                                        scale: 0.94
                                        HoverHandler { id: messageHover }
                                        Component.onCompleted: {
                                            opacity = 1;
                                            scale = 1;
                                        }
                                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

                                        Item {
                                            width: parent.width
                                            height: parent.messageHeight

                                            Item {
                                                id: messageBubble
                                                x: modelData.role === "user" ? parent.width - width : 0
                                                width: parent.width * (modelData.role === "user" ? 0.8 : 0.92)
                                                height: parent.height

                                                BubbleOut {
                                                    id: userBubble
                                                    visible: modelData.role === "user" && !(modelData.imagePath && modelData.showImage)
                                                    anchors.right: parent.right
                                                    text: modelData.text
                                                    maxWidth: parent.width
                                                    fontPixelSize: 14
                                                }

                                                Rectangle {
                                                    id: userImageFrame
                                                    visible: modelData.role === "user" && !!modelData.imagePath && !!modelData.showImage
                                                    anchors.right: parent.right
                                                    width: Math.min(parent.width, 260)
                                                    height: visible ? 170 : 0
                                                    implicitHeight: height
                                                    radius: 16
                                                    color: Qt.rgba(0.08, 0.09, 0.12, 0.92)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, 0.16)
                                                    clip: true
                                                    Image {
                                                        anchors.fill: parent
                                                        source: modelData.imagePath ? "file://" + modelData.imagePath : ""
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                        smooth: true
                                                    }
                                                }

                                                Column {
                                                    id: assistantResponse
                                                    visible: modelData.role !== "user"
                                                    width: parent.width
                                                    spacing: 8

                                                    Repeater {
                                                        id: assistantParagraphs
                                                        // Blank lines mark paragraphs. Each paragraph enters in
                                                        // sequence while the column already holds its final space.
                                                        model: modelData.text.split(/\n\s*\n/)

                                                        delegate: Item {
                                                            id: paragraphDelegate
                                                            required property string modelData
                                                            required property int index
                                                            width: assistantResponse.width
                                                            height: paragraph.implicitHeight
                                                            opacity: 0
                                                            property real cascadeOffset: 8

                                                            Component.onCompleted: {
                                                                opacity = 1;
                                                                cascadeOffset = 0;
                                                                if (index === assistantParagraphs.count - 1) {
                                                                    chatBackdropSettle.interval = index * 180 + 680;
                                                                    chatBackdropSettle.restart();
                                                                }
                                                            }

                                                            Behavior on opacity {
                                                                SequentialAnimation {
                                                                    PauseAnimation { duration: paragraphDelegate.index * 180 }
                                                                    NumberAnimation {
                                                                        duration: 420
                                                                        easing.type: Easing.OutCubic
                                                                    }
                                                                }
                                                            }
                                                            Behavior on cascadeOffset {
                                                                SequentialAnimation {
                                                                    PauseAnimation { duration: paragraphDelegate.index * 180 }
                                                                    NumberAnimation {
                                                                        duration: 520
                                                                        easing.type: Easing.OutCubic
                                                                    }
                                                                }
                                                            }

                                                            Text {
                                                                id: paragraph
                                                                width: parent.width
                                                                text: parent.modelData
                                                                color: "#F5F7FF"
                                                                font.family: "Open Runde"
                                                                font.pixelSize: 14
                                                                lineHeight: 1.35
                                                                wrapMode: Text.WordWrap
                                                                transform: Translate { y: parent.cascadeOffset }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Row {
                                            id: messageActions
                                            anchors.top: parent.top
                                            anchors.topMargin: parent.messageHeight + 2
                                            x: modelData.role === "user" ? parent.width - width : 0
                                            height: modelData.imagePath ? 0 : 24
                                            spacing: 5
                                            visible: height > 0
                                            opacity: modelData.role === "assistant" || messageHover.hovered ? 1 : 0
                                            scale: modelData.role === "assistant" || messageHover.hovered ? 1 : 0.94

                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                            Rectangle {
                                                id: copyButton
                                                width: 24
                                                height: 24
                                                radius: 12
                                                property bool copied: false
                                                scale: copyHover.hovered ? 1.08 : 1
                                                color: copied ? Qt.rgba(0.35, 0.82, 0.58, 0.28) : (copyHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07))
                                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                SiriControlGlass { calm: true }
                                                WGlyph {
                                                    anchors.centerIn: parent
                                                    width: 13
                                                    height: 13
                                                    kind: copyButton.copied ? "check" : "clipboard"
                                                    color: copyButton.copied ? "#75E0A7" : Qt.rgba(1, 1, 1, 0.84)
                                                }
                                                HoverHandler {
                                                    id: copyHover
                                                    onHoveredChanged: {
                                                        if (hovered) win.showCopyHint(copyButton, copyButton.copied ? I18n.tr("Copied") : I18n.tr("Copy"));
                                                        else if (!copyButton.copied) win.copyHintVisible = false;
                                                    }
                                                }
                                                TapHandler {
                                                    onTapped: {
                                                        root.copyMessage(modelData.text);
                                                        copyButton.copied = true;
                                                        win.showCopyHint(copyButton, I18n.tr("Copied"));
                                                        copiedReset.restart();
                                                    }
                                                }
                                                Timer {
                                                    id: copiedReset
                                                    interval: 1400
                                                    onTriggered: {
                                                        copyButton.copied = false;
                                                        if (copyHover.hovered) win.showCopyHint(copyButton, I18n.tr("Copy"));
                                                        else win.copyHintVisible = false;
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                id: messageMoreButton
                                                width: 24
                                                height: 24
                                                radius: 12
                                                scale: moreHover.hovered ? 1.08 : 1
                                                color: moreHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                SiriControlGlass { calm: true }
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Repeater {
                                                        model: 3
                                                        delegate: Rectangle {
                                                            width: 3
                                                            height: 3
                                                            radius: 1.5
                                                            color: Qt.rgba(1, 1, 1, 0.86)
                                                        }
                                                    }
                                                }
                                                HoverHandler { id: moreHover }
                                                TapHandler { onTapped: messageMenu.open() }

                                                Menu {
                                                    id: messageMenu
                                                    topPadding: 6
                                                    bottomPadding: 6
                                                    horizontalPadding: 6
                                                    background: Rectangle {
                                                        implicitWidth: 172
                                                        color: "#24242B"
                                                        radius: 16
                                                        border.width: 1
                                                        border.color: Qt.rgba(1, 1, 1, 0.16)
                                                    }
                                                    MenuItem {
                                                        id: copyMenuItem
                                                        text: I18n.tr("Copy")
                                                        hoverEnabled: true
                                                        implicitWidth: 172
                                                        implicitHeight: 34
                                                        contentItem: Text {
                                                            x: 12
                                                            width: parent.width - 24
                                                            text: copyMenuItem.text
                                                            color: "#F5F7FF"
                                                            font.family: "Open Runde"
                                                            font.pixelSize: 13
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                        background: Rectangle {
                                                            radius: 13
                                                            color: (copyMenuItem.highlighted || copyMenuItem.hovered) ? Qt.rgba(1, 1, 1, 0.19) : "transparent"
                                                            border.width: (copyMenuItem.highlighted || copyMenuItem.hovered) ? 1 : 0
                                                            border.color: Qt.rgba(1, 1, 1, 0.16)
                                                            Behavior on color { ColorAnimation { duration: 100 } }
                                                        }
                                                        onTriggered: root.copyMessage(modelData.text)
                                                    }
                                                    MenuItem {
                                                        id: followUpMenuItem
                                                        text: modelData.role === "user" ? I18n.tr("Edit message") : I18n.tr("Use as follow-up")
                                                        hoverEnabled: true
                                                        implicitWidth: 172
                                                        implicitHeight: 34
                                                        contentItem: Text {
                                                            x: 12
                                                            width: parent.width - 24
                                                            text: followUpMenuItem.text
                                                            color: "#F5F7FF"
                                                            font.family: "Open Runde"
                                                            font.pixelSize: 13
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                        background: Rectangle {
                                                            radius: 13
                                                            color: (followUpMenuItem.highlighted || followUpMenuItem.hovered) ? Qt.rgba(1, 1, 1, 0.19) : "transparent"
                                                            border.width: (followUpMenuItem.highlighted || followUpMenuItem.hovered) ? 1 : 0
                                                            border.color: Qt.rgba(1, 1, 1, 0.16)
                                                            Behavior on color { ColorAnimation { duration: 100 } }
                                                        }
                                                        onTriggered: {
                                                            root.keyboardModeVisible = true;
                                                            root.keyboardInputEnabled = true;
                                                            root.editingMessageIndex = modelData.role === "user" ? index : -1;
                                                            mainInput.text = modelData.text;
                                                            mainInput.forceActiveFocus();
                                                            mainInput.selectAll();
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                    }
                                }
                            }
                        }

                        Row {
                            id: sourceAction
                            width: parent.width
                            height: root.sources.length >= 2 ? 28 : 0
                            spacing: 8
                            visible: root.sources.length >= 2

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Show Results")
                                color: "#DCEBFF"
                                font.family: "Open Runde"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Item {
                                width: 42
                                height: 24
                                Rectangle { x: 15; width: 24; height: 24; radius: 12; color: "#424650"; border.color: Qt.rgba(1, 1, 1, 0.35); border.width: 1 }
                                Image { x: 20; y: 5; width: 14; height: 14; z: 1; asynchronous: true; cache: true; fillMode: Image.PreserveAspectFit; source: root.sources.length > 1 ? root.faviconUrl(root.sources[1]) : "" }
                                Rectangle { width: 24; height: 24; radius: 12; color: "#30343D"; border.color: Qt.rgba(1, 1, 1, 0.52); border.width: 1 }
                                Image { x: 5; y: 5; width: 14; height: 14; z: 2; asynchronous: true; cache: true; fillMode: Image.PreserveAspectFit; source: root.sources.length > 0 ? root.faviconUrl(root.sources[0]) : "" }
                            }

                            TapHandler { onTapped: root.openSources() }
                            HoverHandler { id: resultsHover }
                        }
                    }
                }

                // Follow-up prompt input stays docked to the bottom of the expanded conversation.
                Item {
                    id: pillBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: root.isThinking && !root.chatStarted ? parent.height : (root.chatStarted ? (root.keyboardInputEnabled ? 68 : 54) : parent.height)
                    z: 10

                    MouseArea {
                        id: dragHandler
                        anchors.fill: parent
                        z: 0

                        property real startMouseX: 0
                        property real startMouseY: 0
                        property real startOffsetX: 0
                        property real startOffsetY: 0
                        property bool isDragging: false

                        onPressed: mouse => {
                            isDragging = true;
                            startMouseX = mouse.x;
                            startMouseY = mouse.y;
                            startOffsetX = root.dragOffsetX;
                            startOffsetY = root.dragOffsetY;
                        }

                        onPositionChanged: mouse => {
                            if (isDragging) {
                                root.dragOffsetX = startOffsetX + (mouse.x - startMouseX);
                                root.dragOffsetY = startOffsetY + (mouse.y - startMouseY);
                            }
                        }

                        onReleased: isDragging = false
                        onCanceled: isDragging = false
                    }

                    Item {
                        id: launcher
                        anchors.fill: parent
                        visible: !root.chatStarted && !root.isThinking
                        z: 5

                        TextInput {
                            id: launcherInput
                            anchors.left: parent.left
                            anchors.right: microphoneButton.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 22
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            font.family: "Open Runde"
                            font.pixelSize: 15
                            color: "white"
                            selectionColor: Qt.rgba(0.35, 0.72, 1, 0.7)
                            selectedTextColor: "white"

                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Search or Ask")
                                color: Qt.rgba(1, 1, 1, 0.56)
                                font.family: "Open Runde"
                                font.pixelSize: 15
                                visible: launcherInput.text.length === 0
                            }

                            Keys.onReturnPressed: {
                                if (launcherInput.text.trim() !== "") {
                                    var q = launcherInput.text;
                                    launcherInput.clear();
                                    root.ask(q);
                                }
                            }
                            Keys.onEscapePressed: event => {
                                event.accepted = true;
                                root.close();
                            }
                        }

                        Rectangle {
                            id: microphoneButton
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: 19
                            color: microphoneHover.hovered ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.07)
                            SiriControlGlass { }

                            WGlyph {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                kind: "mic"
                                color: Qt.rgba(1, 1, 1, 0.88)
                            }
                            HoverHandler { id: microphoneHover }
                            TapHandler { onTapped: root.toggleVoiceOnly() }
                            ToolTip.visible: microphoneHover.hovered
                            ToolTip.text: I18n.tr("Speak to Siri")
                        }
                    }

                    Item {
                        id: chatFooter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 8
                        height: 54
                        visible: root.chatStarted
                        z: 10

                        Rectangle {
                            id: micFooterButton
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: 19
                            color: micFooterHover.hovered ? Qt.rgba(0.18, 0.24, 0.34, 0.92) : Qt.rgba(0.025, 0.035, 0.055, 0.84)
                            SiriControlGlass { }
                            WGlyph {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                kind: "mic"
                                color: Qt.rgba(1, 1, 1, 0.88)
                            }
                            HoverHandler { id: micFooterHover }
                            TapHandler { onTapped: root.startVoiceChat() }
                        }

                        Rectangle {
                            id: kbFooterButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: 19
                            color: kbFooterHover.hovered ? Qt.rgba(0.18, 0.24, 0.34, 0.92) : Qt.rgba(0.025, 0.035, 0.055, 0.84)
                            SiriControlGlass { }
                            WGlyph {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                kind: "keyboard"
                                color: Qt.rgba(1, 1, 1, 0.9)
                            }
                            HoverHandler { id: kbFooterHover }
                            TapHandler { onTapped: { root.keyboardModeVisible = !root.keyboardModeVisible; root.keyboardInputEnabled = root.keyboardModeVisible; if (root.keyboardModeVisible) mainInput.forceActiveFocus(); } }
                        }

                        Rectangle {
                            id: inputCapsule
                            anchors.centerIn: parent
                            width: Math.min(260, parent.width - 120)
                            height: 42
                            radius: 21
                            color: Qt.rgba(0.025, 0.035, 0.055, 0.86)
                            border.color: Qt.rgba(1, 1, 1, 0.34)
                            border.width: 1
                            visible: root.chatStarted && (root.keyboardModeVisible || root.isThinking)

                            SiriControlGlass { }

                            Row {
                                anchors.centerIn: parent
                                spacing: 5
                                visible: root.isThinking

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        required property int index
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: Qt.rgba(1, 1, 1, 0.85)
                                        opacity: 0.3 + 0.7 * (0.5 + 0.5 * Math.sin(root.animTime * 6 - index * 1.25))
                                        scale: 0.72 + 0.28 * (0.5 + 0.5 * Math.sin(root.animTime * 6 - index * 1.25))
                                    }
                                }
                            }

                            TextInput {
                                id: mainInput
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                visible: !root.isThinking
                                font.family: "Open Runde"
                                font.pixelSize: 15
                                color: Qt.rgba(1, 1, 1, 0.96)
                                selectionColor: Qt.rgba(0.35, 0.72, 1, 0.7)
                                selectedTextColor: "white"

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 0
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.editingMessageIndex >= 0 ? I18n.tr("Edit message") : I18n.tr("Ask Siri")
                                    font.family: "Open Runde"
                                    font.pixelSize: 15
                                    color: Qt.rgba(1, 1, 1, 0.68)
                                    visible: mainInput.text.length === 0
                                }

                                Keys.onReturnPressed: {
                                    if (mainInput.text.trim() !== "") {
                                        var q = mainInput.text;
                                        mainInput.clear();
                                        root.ask(q);
                                    }
                                }
                                Keys.onEscapePressed: event => {
                                    event.accepted = true;
                                    root.close();
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    root.keyboardInputEnabled = true;
                                    root.keyboardModeVisible = true;
                                    mainInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

            }
            Rectangle {
                id: copyHint
                x: win.copyHintX
                y: win.copyHintY
                width: copyHintLabel.implicitWidth + 20
                height: 30
                radius: 9
                z: 100
                visible: win.copyHintVisible && root.isOpen && root.chatStarted && !root.voiceOnlyMode
                color: "#17191F"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.24)
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Text {
                    id: copyHintLabel
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: win.copyHintText
                    color: "#F5F7FF"
                    font.family: "Open Runde"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            Item {
                id: voiceOrbContainer
                width: 106
                height: 106
                x: (win.width - width) / 2
                y: 82
                visible: root.voiceOnlyMode
                opacity: root.animProgress
                scale: 0.9 + root.animProgress * 0.1

                SiriOrb {
                    anchors.fill: parent
                    active: root.voiceOnlyMode
                    audioLevel: root.edgeGlow ? root.edgeGlow.effectiveAudioLevel : 0
                    isProcessing: root.edgeGlow && root.edgeGlow.siriState === "thinking"
                }
        }
    }
}
}
