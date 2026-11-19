import QtQuick
import "../components"
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../Fonts.js" as Fonts
import "../modules"

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string home: Quickshell.env("HOME")
    property var chats: []
    property var pendingIntelligenceMessages: []
    property string activeChat: ""
    property string deletingChatId: ""
    property string newChatId: ""
    property string filter: "all"
    property string chatSearch: ""
    property string messageSearch: ""
    property bool temporaryMode: false
    property bool gridView: true
    property bool voiceActive: false
    property bool isThinking: false
    property bool inputFocused: false
    property real animTime: 0
    property int editingMessageIndex: -1
    property string pendingImage: ""
    property string queryingChat: ""
    property string initialChatId: ""
    property bool openOnStart: false
    property string instanceId: ""
    property bool loaded: false
    readonly property color bg: "#11141D"
    readonly property color side: "#171B25"
    readonly property color bar: "#171B25"
    readonly property color panel: "#1A1F2A"
    readonly property color text: "#F5F7FF"
    readonly property color muted: "#A1A8B5"
    readonly property color line: Qt.rgba(1, 1, 1, 0.11)
    readonly property color accent: "#4285F4"

    Component.onCompleted: {
        if (instanceId === "") instanceId = uid();
        Quickshell.execDetached(["hyprctl", "eval", "siri_window_rule = siri_window_rule or hl.window_rule({ name = \"shell27-siri-window\", match = { title = \"^Siri - .+$\" }, float = true, center = true, border_size = 0, blur = true, ignore_alpha = 0.1 })"]);
    }

    FrameAnimation {
        running: root.isThinking && win.visible
        onTriggered: root.animTime += 0.016
    }
    Timer {
        id: deleteChatTimer
        interval: 210
        onTriggered: {
            var id = root.deletingChatId;
            root.deletingChatId = "";
            if (id !== "") root.removeChat(id);
        }
    }
    Timer { id: clearNewChatTimer; interval: 650; onTriggered: root.newChatId = "" }

    function uid() { return Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36); }
    function currentChat() {
        for (var i = 0; i < chats.length; i++) if (chats[i].id === activeChat) return chats[i];
        return null;
    }
    function visibleChats() {
        var q = chatSearch.trim().toLowerCase();
        return chats.filter(function (chat) {
            if (filter === "pinned" && !chat.pinned) return false;
            if (filter === "temporary" && !chat.temporary) return false;
            return q === "" || String(chat.title).toLowerCase().indexOf(q) >= 0;
        }).sort(function (a, b) { return Number(b.updated || 0) - Number(a.updated || 0); });
    }
    function listEntries() {
        var entries = [], group = "";
        var items = visibleChats();
        for (var i = 0; i < items.length; i++) {
            var nextGroup = activityGroup(items[i].updated);
            if (nextGroup !== group) { group = nextGroup; entries.push({ kind: "date", title: group }); }
            entries.push({ kind: "chat", chat: items[i] });
        }
        return entries;
    }
    function lastAssistant(chat) {
        if (!chat || !chat.messages) return "";
        for (var i = chat.messages.length - 1; i >= 0; i--) {
            if (chat.messages[i].role === "assistant") return String(chat.messages[i].text || "");
        }
        return "No reply yet";
    }
    function activityLabel(timestamp) {
        return activityGroup(timestamp);
    }
    function activityGroup(timestamp) {
        var then = new Date(Number(timestamp) || Date.now());
        var now = new Date();
        var age = Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(then.getFullYear(), then.getMonth(), then.getDate())) / 86400000);
        if (age === 0) return "Today";
        if (age === 1) return "Yesterday";
        if (age > 1 && age < 7) return Qt.formatDateTime(then, "dddd");
        return Qt.formatDateTime(then, "MMM d, yyyy");
    }
    function save() {
        if (!loaded) return;
        var saved = chats.filter(function (chat) { return !chat.temporary; });
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/shell27\" && printf '%s\\n' \"$1\" > \"$HOME/.config/shell27/siri-chats.json.tmp\" && mv -f \"$HOME/.config/shell27/siri-chats.json.tmp\" \"$HOME/.config/shell27/siri-chats.json\"", "sh", JSON.stringify(saved, null, 2)]);
    }
    function createChat(temp) {
        var chat = { id: uid(), title: "New Chat", messages: [], pinned: false, temporary: !!temp, updated: Date.now() };
        newChatId = chat.id;
        clearNewChatTimer.restart();
        chats = [chat].concat(chats);
        activeChat = chat.id;
        temporaryMode = !!temp;
        save();
    }
    function claimNewChatAnimation(id) {
        if (newChatId !== id) return false;
        newChatId = "";
        clearNewChatTimer.stop();
        return true;
    }
    function updateChat(id, update) {
        chats = chats.map(function (chat) {
            if (chat.id !== id) return chat;
            var next = Object.assign({}, chat, update);
            next.updated = Date.now();
            return next;
        });
        save();
    }
    function appendMessage(id, role, text, image) {
        var chat = null;
        for (var i = 0; i < chats.length; i++) if (chats[i].id === id) chat = chats[i];
        if (!chat) return;
        var messages = chat.messages.slice();
        messages.push({ role: role, text: text || "", imagePath: image || "", showImage: !!image });
        var title = chat.title;
        if (role === "user" && title === "New Chat") title = (text || "Image").slice(0, 40);
        updateChat(id, { messages: messages, title: title });
    }
    function appendIntelligenceMessage(role, text) {
        var cleanText = String(text || "").trim();
        if (cleanText === "") return;
        if (!loaded) {
            pendingIntelligenceMessages = pendingIntelligenceMessages.concat([{ role: role, text: cleanText }]);
            return;
        }
        var chat = chats.filter(function (item) { return item.source === "apple-intelligence"; })[0];
        if (!chat) {
            chat = { id: uid(), title: "Apple Intelligence", messages: [], pinned: false, temporary: false, source: "apple-intelligence", updated: Date.now() };
            chats = [chat].concat(chats);
        }
        var messages = chat.messages.slice();
        messages.push({ role: role, text: cleanText, imagePath: "", showImage: false });
        updateChat(chat.id, { messages: messages, title: "Apple Intelligence", source: "apple-intelligence" });
        activeChat = chat.id;
    }
    function renameChat(id, title) {
        if (!title || title.trim() === "") return;
        updateChat(id, { title: title.trim() });
    }
    function deleteChat(id) {
        if (deletingChatId !== "") return;
        deletingChatId = id;
        deleteChatTimer.restart();
    }
    function removeChat(id) {
        chats = chats.filter(function (chat) { return chat.id !== id; });
        if (activeChat === id) activeChat = chats.length ? chats[0].id : "";
        save();
    }
    function togglePin(id) {
        var chat = chats.filter(function (item) { return item.id === id; })[0];
        if (chat) updateChat(id, { pinned: !chat.pinned });
    }
    function openInNewWindow(id) {
        if (root.hub) Quickshell.execDetached(["qs", "-c", "shell27", "ipc", "call", "siri_app", "new_window", String(id)]);
        else Quickshell.execDetached(["qs", "-p", root.home + "/.config/quickshell/shell27/apps/SiriApp.qml"]);
    }
    function receiveResponse(id, text) {
        appendMessage(id, "assistant", text, "");
        if (queryingChat === id) { isThinking = false; queryingChat = ""; }
    }
    function setSources(id, value) {
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
        updateChat(id, { sources: valid });
    }
    function faviconUrl(url) {
        var host = String(url).replace(/^https:\/\//i, "").split(/[/?#]/)[0];
        return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(host) + "&sz=64";
    }
    function openSources() {
        var chat = currentChat();
        if (!chat || !chat.sources) return;
        for (var i = 0; i < chat.sources.length; i++) Qt.openUrlExternally(chat.sources[i]);
    }
    function copyMessage(text) { Quickshell.execDetached(["wl-copy", text]); }
    function receiveBackendEvent(line) {
        var prefix = "SIRI_APP_EVENT:";
        if (line.indexOf(prefix) !== 0) return;
        var event;
        try { event = JSON.parse(line.slice(prefix.length)); } catch (e) { return; }
        if (event.event === "response") receiveResponse(event.chatId, event.value);
        else if (event.event === "sources") setSources(event.chatId, event.value);
        else if (event.event === "user") { appendMessage(event.chatId, "user", event.value, ""); isThinking = true; }
        else if (event.event === "voice" && activeChat === event.chatId) voiceActive = !!event.value;
    }
    function messageIndexOf(message) {
        var chat = currentChat();
        if (!chat) return -1;
        for (var i = 0; i < chat.messages.length; i++) if (chat.messages[i] === message) return i;
        return -1;
    }
    function sendPrompt(text) {
        var chat = currentChat();
        var prompt = String(text || "").trim();
        if (!chat || (!prompt && pendingImage === "")) return;
        var id = chat.id;
        var image = pendingImage;
        pendingImage = "";
        if (editingMessageIndex >= 0 && editingMessageIndex < chat.messages.length) {
            var revised = chat.messages.slice(0, editingMessageIndex);
            revised.push({ role: "user", text: prompt, imagePath: image, showImage: !!image });
            updateChat(id, { messages: revised });
        } else {
            appendMessage(id, "user", prompt, image);
        }
        editingMessageIndex = -1;
        isThinking = true;
        queryingChat = id;
        var command = image
            ? ["python3", root.home + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--app-visual-query", image, prompt, String(id)]
            : ["python3", root.home + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--app-query", prompt, String(id)];
        if (!root.hub) command.push("--app-stdout");
        queryProc.command = command;
        queryProc.running = true;
        input.text = "";
    }
    function open() {
        if (chats.length === 0) createChat(false);
        win.visible = true;
        win.raise();
        win.requestActivate();
    }
    function windowSelector() { return 'window = "title:^(' + win.title + ')$"'; }
    function setView(grid) { gridView = grid; }
    function searchMessages() {
        if (messageSearch === "") return [];
        var chat = currentChat();
        if (!chat) return [];
        var q = messageSearch.toLowerCase();
        return chat.messages.filter(function (message) { return String(message.text).toLowerCase().indexOf(q) >= 0; });
    }

    FileView {
        id: store
        path: root.home + "/.config/shell27/siri-chats.json"
        printErrors: false
        onLoaded: {
            var storedChats = [];
            try {
                storedChats = JSON.parse(text()).filter(function (chat) { return !chat.temporary; }).map(function (chat) {
                    chat.messages = (chat.messages || []).map(function (message) {
                        if (message.imagePath !== undefined) return message;
                        return Object.assign({}, message, { imagePath: message.image || "", showImage: !!message.image });
                    });
                    return chat;
                });
            } catch (e) { storedChats = []; }
            for (var i = 0; i < root.chats.length; i++) {
                var exists = storedChats.some(function (chat) { return chat.id === root.chats[i].id; });
                if (!exists) storedChats.push(root.chats[i]);
            }
            root.chats = storedChats;
            root.loaded = true;
            var pendingMessages = root.pendingIntelligenceMessages;
            root.pendingIntelligenceMessages = [];
            for (var i = 0; i < pendingMessages.length; i++) root.appendIntelligenceMessage(pendingMessages[i].role, pendingMessages[i].text);
            if (root.initialChatId !== "" && root.chats.some(function (chat) { return chat.id === root.initialChatId; })) root.activeChat = root.initialChatId;
            else if (root.activeChat === "" && root.chats.length) root.activeChat = root.chats[0].id;
            if (!root.hub || root.openOnStart) root.open();
        }
        onLoadFailed: { root.loaded = true; if (!root.hub || root.openOnStart) root.open(); }
    }

    Process {
        id: queryProc
        stdout: SplitParser { onRead: line => root.receiveBackendEvent(line) }
    }
    FileDialog {
        id: attachmentPicker
        title: "Add an attachment"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif)"]
        onAccepted: root.pendingImage = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }

    Window {
        id: win
        title: "Siri - " + root.instanceId
        width: 868
        height: 715
        minimumWidth: 695
        minimumHeight: 560
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        property int floatTries: 0
        onVisibleChanged: if (visible) { floatTries = 0; floatTimer.restart(); }
        onClosing: close => { close.accepted = false; win.visible = false; }
        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: win.visible = false }
        Timer {
            id: floatTimer
            interval: 60
            repeat: true
            onTriggered: {
                var sel = root.windowSelector();
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "12", ' + sel + ' })');
                if (win.floatTries >= 2) {
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++win.floatTries >= 4) stop();
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.50)
            clip: true
            Rectangle {
                x: sidebar.width; y: 1
                width: parent.width - sidebar.width - 1; height: parent.height - 2
                color: "#1E1E20"
                z: -2
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: 18
                color: "transparent"
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
                z: 900
            }
            MouseArea { x: 12; y: 0; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.TopEdge) }
            MouseArea { x: 12; y: parent.height - 6; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }
            MouseArea { x: 0; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.LeftEdge) }
            MouseArea { x: parent.width - 6; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 0; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.TopEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 12; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: win.startSystemResize(Qt.TopEdge | Qt.RightEdge) }
            MouseArea { x: 0; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 12; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            Rectangle {
                id: sidebar
                width: 360
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    z: -1
                    color: Qt.rgba(0.17, 0.17, 0.18, 0.55)
                }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.08) }
                Item {
                    id: trafficLights
                    x: 16; y: 13; width: 58; height: 14
                    Row {
                        id: lightRow
                        property bool hovering: lightHover.containsMouse
                        property color offColor: Qt.rgba(1, 1, 1, 0.20)
                        spacing: 8
                        Repeater {
                            model: [{ c: "#FF5F57", g: "×", on: true }, { c: "#FEBC2E", g: "−", on: false }, { c: "#28C840", g: "↗", on: true }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: (modelData.on && (win.active || lightHover.containsMouse)) ? modelData.c : lightRow.offColor
                                border.width: 1
                                border.color: (modelData.on && (win.active || lightHover.containsMouse)) ? Qt.darker(modelData.c, 1.15) : "transparent"
                                Text { anchors.centerIn: parent; visible: lightHover.containsMouse && parent.modelData.on; text: parent.modelData.g; color: Qt.rgba(0, 0, 0, 0.62); font.pixelSize: 9; font.weight: Font.Bold }
                            }
                        }
                    }
                    MouseArea {
                        id: lightHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mouse => {
                            var selector = root.windowSelector();
                            if (mouse.x < 22) win.visible = false;
                            else if (mouse.x < 44) { }
                            else Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", ' + selector + ' })');
                        }
                    }
                }
                Rectangle {
                    id: filterButton
                    x: parent.width - width - 13; y: 6; width: 36; height: 36; radius: 18
                    color: filterHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.13)
                    scale: filterHover.hovered ? 1.07 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 140 } }
                    GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.dock ? root.dock.glassShaderUrl : ""; dark: true; baseColor: "#252528"; cornerR: 18; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: 0.48; flatInner: 1 }
                    Canvas {
                        anchors.centerIn: parent
                        width: 14; height: 10
                        property color ink: "#F5F7FF"
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                            ctx.fillStyle = ink;
                            var lines = [[0, 0, 14, 1.3], [1.5, 4, 11, 1.3], [3, 8, 8, 1.3]];
                            for (var i = 0; i < lines.length; i++) ctx.fillRect(lines[i][0], lines[i][1], lines[i][2], lines[i][3]);
                        }
                    }
                    ToolTip.visible: filterHover.hovered; ToolTip.text: "Filter chats"
                    HoverHandler { id: filterHover }
                    TapHandler { onTapped: filterMenu.popup() }
                    Menu {
                        id: filterMenu
                        topPadding: 6; bottomPadding: 6; leftPadding: 6; rightPadding: 6
                        background: Rectangle { implicitWidth: 216; color: "#29292B"; radius: 12; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                        SiriMenuItem { text: "All Chats"; onTriggered: root.filter = "all" }
                        SiriMenuItem { text: "Pinned"; onTriggered: root.filter = "pinned" }
                        SiriMenuItem { text: "Temporary"; onTriggered: root.filter = "temporary" }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 42
                    width: parent.width - 36
                    spacing: 12
                    visible: root.visibleChats().length === 0
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.chatSearch !== "" ? "No chats found" : "All done here!"
                        color: Qt.rgba(1, 1, 1, 0.72)
                        font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 46; height: 46
                        source: "file://" + root.home + "/.config/quickshell/shell27/assets/siri-app.png"
                        smooth: true; mipmap: true
                        opacity: 0.66
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.chatSearch !== "" ? "Try a different search" : "Your conversations will appear here"
                        color: Qt.rgba(1, 1, 1, 0.42)
                        font.family: root.fam
                        font.pixelSize: 11
                    }
                }

                GridView {
                    id: chatGrid
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 42
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                    cellWidth: 170; cellHeight: 229
                    contentHeight: Math.max(height, Math.ceil(count / 2) * cellHeight + (count % 2 === 0 ? 55 : 0))
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    clip: true; visible: root.gridView
                    model: root.visibleChats()
                    delegate: Item {
                        id: chatCard
                        required property var modelData
                        required property int index
                        property real entryScale: 1
                        readonly property bool deleting: modelData.id === root.deletingChatId
                        width: 170; height: 229
                        opacity: deleting ? 0 : 1
                        scale: entryScale * (deleting ? 0.76 : 1)
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Component.onCompleted: if (root.claimNewChatAnimation(modelData.id)) { entryScale = 1.13; entryBounce.restart(); }
                        SequentialAnimation {
                            id: entryBounce
                            NumberAnimation { target: chatCard; property: "entryScale"; to: 0.96; duration: 120; easing.type: Easing.InOutSine }
                            NumberAnimation { target: chatCard; property: "entryScale"; to: 1; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                        }
                        Rectangle {
                            id: cardSurface
                            x: 4; y: 4 + (chatCard.index % 2 === 1 ? 55 : 0); width: 166; height: 221; radius: 42
                            color: modelData.id === root.activeChat ? "#292B30" : "#242426"
                            border.width: modelData.id === root.activeChat ? 1.5 : 1
                            border.color: modelData.id === root.activeChat ? root.accent : Qt.rgba(1, 1, 1, 0.08)
                            Text { x: 18; y: 24; width: parent.width - 54; height: 14; text: root.activityLabel(chatCard.modelData.updated); color: Qt.rgba(1, 1, 1, 0.48); font.family: root.fam; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { x: 18; y: 44; width: parent.width - 36; height: 70; text: chatCard.modelData.title; color: root.text; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 18; font.weight: Font.DemiBold; lineHeight: 1.08; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; clip: true }
                            Text { x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 25; width: parent.width - 36; height: 68; verticalAlignment: Text.AlignBottom; text: root.lastAssistant(chatCard.modelData); color: Qt.rgba(1, 1, 1, 0.68); font.family: root.fam; font.pixelSize: 11; lineHeight: 1.2; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight; clip: true }
                            Text { visible: chatCard.modelData.pinned; anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: 18; anchors.topMargin: 16; text: "⌖"; color: root.accent; font.pixelSize: 15 }
                            TapHandler { onTapped: { root.activeChat = chatCard.modelData.id; root.temporaryMode = chatCard.modelData.temporary; } }
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: { root.contextChat = chatCard.modelData.id; chatMenu.popup(); } }
                            Menu {
                                id: chatMenu
                                topPadding: 6; bottomPadding: 6; leftPadding: 6; rightPadding: 6
                                background: Rectangle { implicitWidth: 216; color: "#29292B"; radius: 12; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                                SiriMenuItem { text: "Rename"; onTriggered: { root.renameTarget = chatCard.modelData.id; renameDialog.open(); } }
                                SiriMenuItem { text: "Open in New Window"; onTriggered: root.openInNewWindow(chatCard.modelData.id) }
                                SiriMenuItem { text: chatCard.modelData.pinned ? "Unpin" : "Pin"; onTriggered: root.togglePin(chatCard.modelData.id) }
                                MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Qt.rgba(1, 1, 1, 0.12) } }
                                SiriMenuItem { text: "Delete"; onTriggered: root.deleteChat(chatCard.modelData.id) }
                            }
                        }
                    }
                }
                ListView {
                    id: chatList
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 42
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    clip: true; spacing: 2
                    visible: !root.gridView
                    model: root.listEntries()
                    delegate: Item {
                        id: listRow
                        required property var modelData
                        property real entryScale: 1
                        readonly property bool deleting: modelData.kind === "chat" && modelData.chat.id === root.deletingChatId
                        width: chatList.width; height: modelData.kind === "date" ? 26 : (deleting ? 0 : 74)
                        opacity: deleting ? 0 : 1
                        scale: entryScale * (deleting ? 0.82 : 1)
                        visible: modelData.kind === "date" || !!modelData.chat
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                        Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Component.onCompleted: if (modelData.kind === "chat" && root.claimNewChatAnimation(modelData.chat.id)) { entryScale = 1.13; entryBounce.restart(); }
                        SequentialAnimation {
                            id: entryBounce
                            NumberAnimation { target: listRow; property: "entryScale"; to: 0.96; duration: 120; easing.type: Easing.InOutSine }
                            NumberAnimation { target: listRow; property: "entryScale"; to: 1; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                        }
                        Text {
                            visible: modelData.kind === "date"
                            anchors.left: parent.left; anchors.leftMargin: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                            text: modelData.kind === "date" ? modelData.title : ""; color: Qt.rgba(1, 1, 1, 0.55); font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            visible: modelData.kind === "chat"
                            anchors.fill: parent; anchors.margins: 2; radius: 16
                            color: modelData.chat && modelData.chat.id === root.activeChat ? "#272A30" : "#242426"
                            border.width: modelData.chat && modelData.chat.id === root.activeChat ? 1.5 : 1
                            border.color: modelData.chat && modelData.chat.id === root.activeChat ? root.accent : Qt.rgba(1, 1, 1, 0.07)
                            Column {
                                anchors.fill: parent; anchors.margins: 12; spacing: 4
                                Text { width: parent.width; text: modelData.chat ? modelData.chat.title : ""; color: root.text; elide: Text.ElideRight; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: modelData.chat ? root.lastAssistant(modelData.chat) : ""; color: Qt.rgba(1, 1, 1, 0.64); elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap; font.family: root.fam; font.pixelSize: 11; lineHeight: 1.15; clip: true }
                            }
                            TapHandler { onTapped: { root.activeChat = listRow.modelData.chat.id; root.temporaryMode = listRow.modelData.chat.temporary; } }
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: { root.contextChat = listRow.modelData.chat.id; listMenu.popup(); } }
                            Menu {
                                id: listMenu
                                topPadding: 6; bottomPadding: 6; leftPadding: 6; rightPadding: 6
                                background: Rectangle { implicitWidth: 216; color: "#29292B"; radius: 12; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                                SiriMenuItem { text: "Rename"; onTriggered: if (listRow.modelData.chat) { root.renameTarget = listRow.modelData.chat.id; renameDialog.open(); } }
                                SiriMenuItem { text: "Open in New Window"; onTriggered: if (listRow.modelData.chat) root.openInNewWindow(listRow.modelData.chat.id) }
                                SiriMenuItem { text: listRow.modelData.chat && listRow.modelData.chat.pinned ? "Unpin" : "Pin"; onTriggered: if (listRow.modelData.chat) root.togglePin(listRow.modelData.chat.id) }
                                MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Qt.rgba(1, 1, 1, 0.12) } }
                                SiriMenuItem { text: "Delete"; onTriggered: if (listRow.modelData.chat) root.deleteChat(listRow.modelData.chat.id) }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.left: sidebar.right; anchors.right: parent.right
                anchors.top: parent.top; anchors.bottom: parent.bottom
                MouseArea { x: 48; y: 0; width: parent.width - 96; height: 42; z: 1; acceptedButtons: Qt.LeftButton; onPressed: win.startSystemMove() }
                Rectangle {
                    id: messageSearchButton
                    anchors.right: parent.right; anchors.rightMargin: 13; y: 6; width: 36; height: 36; radius: 18
                    color: searchHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.13)
                    scale: searchHover.hovered ? 1.07 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 140 } }
                    GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.dock ? root.dock.glassShaderUrl : ""; dark: true; baseColor: "#252528"; cornerR: 18; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: 0.48; flatInner: 1 }
                    Canvas {
                        anchors.centerIn: parent; width: 14; height: 14
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = "#F5F7FF"; ctx.lineWidth = 1.15;
                            ctx.beginPath(); ctx.arc(4.8, 4.8, 4.1, 0, Math.PI * 2); ctx.stroke();
                            ctx.beginPath(); ctx.moveTo(7.8, 7.8); ctx.lineTo(11.5, 11.5); ctx.stroke();
                        }
                    }
                    ToolTip.visible: searchHover.hovered; ToolTip.text: "Search in chat"
                    HoverHandler { id: searchHover }
                    TapHandler { onTapped: { searchBar.visible = !searchBar.visible; if (searchBar.visible) messageSearchField.forceActiveFocus(); else root.messageSearch = ""; } }
                }
                Rectangle {
                    id: newChatButton
                    x: 14; y: 6 + bounceY; width: 36; height: 36; radius: 18
                    property real bounceY: 0
                    color: newChatHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.13)
                    scale: newChatHover.hovered ? 1.07 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 140 } }
                    GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.dock ? root.dock.glassShaderUrl : ""; dark: true; baseColor: "#252528"; cornerR: 18; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: 0.48; flatInner: 1 }
                    SequentialAnimation {
                        id: newChatBounce
                        NumberAnimation { target: newChatButton; property: "bounceY"; to: -3; duration: 90; easing.type: Easing.OutCubic }
                        NumberAnimation { target: newChatButton; property: "bounceY"; to: 0; duration: 160; easing.type: Easing.OutBounce }
                    }
                    Canvas {
                        anchors.centerIn: parent; width: 12; height: 12
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = "#F5F7FF"; ctx.fillStyle = "#F5F7FF"; ctx.lineWidth = 1;
                            ctx.beginPath(); ctx.moveTo(9.8, 1.4); ctx.lineTo(10.7, 2.3); ctx.lineTo(5.1, 7.9); ctx.lineTo(3.9, 8.4); ctx.lineTo(4.4, 7.2); ctx.closePath(); ctx.fill();
                            ctx.beginPath(); ctx.moveTo(8.9, 1.7); ctx.lineTo(10.2, 0.5); ctx.lineTo(11.5, 1.8); ctx.lineTo(10.3, 3.1); ctx.stroke();
                            ctx.beginPath(); ctx.moveTo(7.7, 3.0); ctx.lineTo(7.7, 1.1); ctx.lineTo(2.5, 1.1); ctx.quadraticCurveTo(0.7, 1.1, 0.7, 3); ctx.lineTo(0.7, 9); ctx.quadraticCurveTo(0.7, 11, 2.7, 11); ctx.lineTo(8, 11); ctx.quadraticCurveTo(10, 11, 10, 9); ctx.lineTo(10, 5); ctx.stroke();
                        }
                    }
                    ToolTip.visible: newChatHover.hovered; ToolTip.text: "New chat"
                    HoverHandler { id: newChatHover }
                    TapHandler { onTapped: { newChatBounce.restart(); root.createChat(false); } }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: newChatMenu.popup() }
                    Menu {
                        id: newChatMenu
                        topPadding: 6; bottomPadding: 6; leftPadding: 6; rightPadding: 6
                        background: Rectangle { implicitWidth: 216; color: "#29292B"; radius: 12; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                        SiriMenuItem { text: "New Chat"; onTriggered: root.createChat(false) }
                        SiriMenuItem { text: "New Temporary Chat"; onTriggered: root.createChat(true) }
                    }
                }
                Rectangle {
                    id: searchBar
                    visible: false; anchors.right: messageSearchButton.left; anchors.rightMargin: 8; y: 8; width: 190; height: 32; radius: 7
                    color: "#28282A"; border.color: Qt.rgba(1, 1, 1, 0.14)
                    TextField {
                        id: messageSearchField
                        anchors.fill: parent
                        leftPadding: 9
                        placeholderText: "Find in this chat"
                        color: root.text
                        placeholderTextColor: root.muted
                        font.family: root.fam
                        font.pixelSize: 12
                        background: Item {}
                        onTextChanged: root.messageSearch = text
                    }
                }

                ListView {
                    id: messagesView
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 48; anchors.bottom: sourceAction.top
                    anchors.margins: 18; spacing: 14; clip: true
                    model: root.currentChat() ? (root.messageSearch === "" ? root.currentChat().messages : root.searchMessages()) : []
                    onCountChanged: Qt.callLater(function () { messagesView.positionViewAtEnd(); })
                    delegate: Item {
                        id: messageRow
                        required property var modelData
                        width: messagesView.width
                        readonly property real messageHeight: modelData.role === "user"
                            ? (modelData.imagePath && modelData.showImage ? userImageFrame.implicitHeight : userBubble.implicitHeight)
                            : assistantResponse.implicitHeight
                        height: messageHeight + messageActions.height
                        HoverHandler { id: messageHover }

                        Item {
                            width: messageRow.width
                            height: messageRow.messageHeight
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
                                    fill: "#26252A"
                                    ink: "#F5F7FF"
                                }
                                Rectangle {
                                    id: userImageFrame
                                    visible: modelData.role === "user" && !!modelData.imagePath && !!modelData.showImage
                                    anchors.right: parent.right
                                    width: Math.min(parent.width, 260)
                                    height: visible ? 170 : 0
                                    implicitHeight: height
                                    radius: 16
                                    color: "#141720"
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
                                        model: String(modelData.text || "").split(/\n\s*\n/)
                                        delegate: Item {
                                            required property string modelData
                                            required property int index
                                            width: assistantResponse.width
                                            height: paragraph.implicitHeight
                                            opacity: 0
                                            Component.onCompleted: opacity = 1
                                            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                            Text {
                                                id: paragraph
                                                width: parent.width
                                                text: parent.modelData
                                                color: "#F5F7FF"
                                                font.family: "Open Runde"
                                                font.pixelSize: 14
                                                lineHeight: 1.35
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            id: messageActions
                            anchors.top: parent.top
                            anchors.topMargin: messageRow.messageHeight + 2
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
                                width: 24; height: 24; radius: 12
                                property bool copied: false
                                color: copied ? Qt.rgba(0.35, 0.82, 0.58, 0.28) : (copyHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07))
                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                WGlyph { anchors.centerIn: parent; width: 13; height: 13; kind: copyButton.copied ? "check" : "clipboard"; color: copyButton.copied ? "#75E0A7" : Qt.rgba(1, 1, 1, 0.84) }
                                HoverHandler {
                                    id: copyHover
                                    onHoveredChanged: if (hovered) messageTooltip.show(copyButton, copyButton.copied ? "Copied" : "Copy")
                                }
                                TapHandler {
                                    onTapped: {
                                        root.copyMessage(modelData.text);
                                        copyButton.copied = true;
                                        messageTooltip.show(copyButton, "Copied");
                                        copiedReset.restart();
                                    }
                                }
                                Timer { id: copiedReset; interval: 1400; onTriggered: copyButton.copied = false }
                            }
                            Rectangle {
                                id: moreButton
                                width: 24; height: 24; radius: 12
                                color: moreHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                                Row {
                                    anchors.centerIn: parent; spacing: 2
                                    Repeater { model: 3; delegate: Rectangle { width: 3; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.86) } }
                                }
                                HoverHandler { id: moreHover }
                                TapHandler { onTapped: messageMenu.open() }
                                Menu {
                                    id: messageMenu
                                    topPadding: 6; bottomPadding: 6; leftPadding: 6; rightPadding: 6
                                    background: Rectangle { implicitWidth: 172; color: "#24242B"; radius: 16; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16) }
                                    MenuItem {
                                        id: copyMenuItem
                                        text: "Copy"; implicitWidth: 172; implicitHeight: 34; hoverEnabled: true
                                        contentItem: Text { x: 12; width: parent.width - 24; text: copyMenuItem.text; color: "#F5F7FF"; font.family: "Open Runde"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { radius: 13; color: copyMenuItem.highlighted ? Qt.rgba(1, 1, 1, 0.19) : "transparent" }
                                        onTriggered: root.copyMessage(modelData.text)
                                    }
                                    MenuItem {
                                        id: followUpMenuItem
                                        text: modelData.role === "user" ? "Edit message" : "Use as follow-up"
                                        implicitWidth: 172; implicitHeight: 34; hoverEnabled: true
                                        contentItem: Text { x: 12; width: parent.width - 24; text: followUpMenuItem.text; color: "#F5F7FF"; font.family: "Open Runde"; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { radius: 13; color: followUpMenuItem.highlighted ? Qt.rgba(1, 1, 1, 0.19) : "transparent" }
                                        onTriggered: {
                                            root.editingMessageIndex = modelData.role === "user" ? root.messageIndexOf(modelData) : -1;
                                            input.text = modelData.text;
                                            input.forceActiveFocus();
                                            input.selectAll();
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        visible: !root.currentChat() || root.currentChat().messages.length === 0
                        Image { anchors.horizontalCenter: parent.horizontalCenter; width: 48; height: 48; source: "file://" + root.home + "/.config/quickshell/shell27/assets/siri-app.png"; smooth: true; mipmap: true; opacity: 0.94 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.temporaryMode ? "Temporary chat" : "What can I help with?"; color: root.muted; font.family: "Open Runde"; font.pixelSize: 16 }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                        spacing: 5; visible: root.isThinking
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: 5; height: 5; radius: 2.5
                                color: Qt.rgba(1, 1, 1, 0.85)
                                opacity: 0.3 + 0.7 * (0.5 + 0.5 * Math.sin(root.animTime * 6 - index * 1.25))
                            }
                        }
                    }
                }
                Row {
                    id: sourceAction
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: composer.top; anchors.leftMargin: 22; anchors.rightMargin: 22
                    height: root.currentChat() && root.currentChat().sources && root.currentChat().sources.length >= 2 ? 28 : 0
                    spacing: 8
                    visible: height > 0
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Show Results"; color: "#DCEBFF"; font.family: "Open Runde"; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Item {
                        width: 42; height: 24
                        readonly property var sources: root.currentChat() ? (root.currentChat().sources || []) : []
                        Rectangle { x: 15; width: 24; height: 24; radius: 12; color: "#424650"; border.color: Qt.rgba(1, 1, 1, 0.35); border.width: 1 }
                        Image { x: 20; y: 5; width: 14; height: 14; z: 1; asynchronous: true; fillMode: Image.PreserveAspectFit; source: parent.sources.length > 1 ? root.faviconUrl(parent.sources[1]) : "" }
                        Rectangle { width: 24; height: 24; radius: 12; color: "#30343D"; border.color: Qt.rgba(1, 1, 1, 0.52); border.width: 1 }
                        Image { x: 5; y: 5; width: 14; height: 14; z: 2; asynchronous: true; fillMode: Image.PreserveAspectFit; source: parent.sources.length > 0 ? root.faviconUrl(parent.sources[0]) : "" }
                        TapHandler { onTapped: root.openSources() }
                        HoverHandler { id: resultsHover }
                    }
                }
                Rectangle {
                    id: composer
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 15
                    width: Math.min(parent.width - 30, root.inputFocused ? 340 : 270)
                    height: 58; radius: 29
                    color: "#29292B"
                    border.width: 1; border.color: root.inputFocused ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.14)
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Row {
                        id: composerControls
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        height: 38
                        spacing: 4
                        Rectangle {
                            id: attachButton
                            width: 38; height: 38; radius: 19
                            color: attachHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                            scale: attachHover.hovered ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }
                            GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.dock ? root.dock.glassShaderUrl : ""; dark: true; baseColor: "#29292B"; cornerR: 19; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: 0.48; flatInner: 1 }
                            Text { anchors.centerIn: parent; text: "+"; color: root.text; font.pixelSize: 22; font.weight: Font.Light }
                            HoverHandler { id: attachHover }
                            TapHandler { onTapped: attachmentPicker.open() }
                            ToolTip.visible: attachHover.hovered; ToolTip.text: "Add attachment"
                        }
                        TextField {
                            id: input
                            width: Math.max(90, composer.width - 16 - 38 - 38 - 12 - (sendButton.visible ? 38 : 0))
                            height: 38
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: "Ask Siri"
                            color: root.text; placeholderTextColor: Qt.rgba(1, 1, 1, 0.48)
                            font.family: root.fam; font.pixelSize: 14
                            leftPadding: 8; rightPadding: 6
                            background: Item {}
                            onActiveFocusChanged: root.inputFocused = activeFocus
                            onAccepted: root.sendPrompt(text)
                        }
                        Rectangle {
                            id: voiceButton
                            width: 38; height: 38; radius: 19
                            color: root.voiceActive ? Qt.rgba(1, 0.27, 0.32, 0.22) : (voiceHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                            scale: voiceHover.hovered ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }
                            GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.dock ? root.dock.glassShaderUrl : ""; dark: true; baseColor: "#29292B"; cornerR: 19; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: 0.48; flatInner: 1 }
                            WGlyph { anchors.centerIn: parent; width: 17; height: 17; kind: root.voiceActive ? "stoprec" : "mic"; color: root.text }
                            HoverHandler { id: voiceHover }
                            TapHandler { onTapped: root.toggleVoice() }
                            ToolTip.visible: voiceHover.hovered; ToolTip.text: root.voiceActive ? "Stop voice mode" : "Voice mode"
                        }
                        Rectangle {
                            id: sendButton
                            visible: input.text.trim() !== "" || root.pendingImage !== ""
                            width: visible ? 38 : 0; height: 38; radius: 19
                            color: root.accent
                            scale: sendHover.hovered ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Text { anchors.centerIn: parent; y: -1; text: "↑"; color: "white"; font.pixelSize: 21; font.weight: Font.DemiBold }
                            HoverHandler { id: sendHover }
                            TapHandler { enabled: input.text.trim() !== "" || root.pendingImage !== ""; onTapped: root.sendPrompt(input.text) }
                            ToolTip.visible: sendHover.hovered; ToolTip.text: "Send"
                        }
                    }
                    Text {
                        visible: root.pendingImage !== ""
                        anchors.left: parent.left; anchors.leftMargin: 49
                        anchors.bottom: parent.top; anchors.bottomMargin: 4
                        text: "Image attached"; color: Qt.rgba(1, 1, 1, 0.58); font.family: root.fam; font.pixelSize: 10
                    }
                }
            }
        }
    }

    property string renameTarget: ""
    property string contextChat: ""
    property bool renaming: false
    Dialog {
        id: renameDialog
        title: "Rename Chat"
        width: 322
        padding: 18
        anchors.centerIn: Overlay.overlay
        modal: true
        background: Rectangle { color: "#29292B"; radius: 14; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16) }
        contentItem: TextField {
            id: renameDialogField
            text: ""
            placeholderText: "Chat name"
            color: root.text
            placeholderTextColor: root.muted
            font.family: root.fam
            font.pixelSize: 13
            selectionColor: root.accent
            background: Rectangle { color: "#1E1E20"; radius: 8; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12) }
        }
        footer: Row {
            spacing: 8
            layoutDirection: Qt.RightToLeft
            Rectangle {
                width: 82; height: 32; radius: 8
                color: renameActionHover.hovered ? Qt.lighter(root.accent, 1.12) : root.accent
                Text { anchors.centerIn: parent; text: "Rename"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                HoverHandler { id: renameActionHover }
                TapHandler { onTapped: { root.renameChat(root.renameTarget, renameDialogField.text); renameDialog.close(); } }
            }
            Rectangle {
                width: 72; height: 32; radius: 8
                color: cancelHover.hovered ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.07)
                Text { anchors.centerIn: parent; text: "Cancel"; color: root.text; font.family: root.fam; font.pixelSize: 12 }
                HoverHandler { id: cancelHover }
                TapHandler { onTapped: renameDialog.close() }
            }
        }
        onOpened: {
            for (var i = 0; i < root.chats.length; i++) if (root.chats[i].id === root.renameTarget) renameDialogField.text = root.chats[i].title;
            renameDialogField.forceActiveFocus();
        }
    }

    function toggleVoice() {
        var chat = currentChat();
        if (!chat) return;
        if (voiceActive) {
            voiceProc.running = false;
            voiceActive = false;
            return;
        }
        voiceActive = true;
        var command = ["python3", root.home + "/.config/quickshell/shell27/scripts/siri_daemon.py", "--app-voice", String(chat.id)];
        if (!root.hub) command.push("--app-stdout");
        voiceProc.command = command;
        voiceProc.running = true;
    }
    Process {
        id: voiceProc
        stdout: SplitParser { onRead: line => root.receiveBackendEvent(line) }
        onExited: root.voiceActive = false
    }
}