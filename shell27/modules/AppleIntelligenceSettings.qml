import QtQuick
import Quickshell
import Quickshell.Io
import "../I18n.js" as I18n

Item {
    id: root

    // Settings state
    property bool siriEnabled: true
    property bool wakeWordEnabled: true
    property bool liveVoiceStreaming: true
    property string preferredResponseType: "spoken"
    property string language: "en-US"
    property string voice: "en-US-JennyNeural"
    property string ttsVoiceEn: "en-US-JennyNeural"
    property int speechRate: 165
    property real edgeGlowIntensity: 1.0
    property string geminiModel: "gemini-3.8-flash"
    property string apiKey: ""
    property bool visualIntelligenceEnabled: true
    property bool visualTextSelectionEnabled: true
    property string visualSearchProvider: "google-lens"
    property bool visualImageInChat: true
    property string visualModel: ""
    property bool deleteVisualImageAfterResponse: true
    property bool isLoaded: false

    readonly property var voiceOptions: [
        { id: "en-US-JennyNeural", label: "Voice 1 (American · Jenny)" },
        { id: "en-US-GuyNeural",   label: "Voice 2 (American · Guy)" },
        { id: "en-US-AriaNeural",  label: "Voice 3 (American · Aria)" },
        { id: "en-GB-SoniaNeural", label: "Voice 4 (British · Sonia)" },
        { id: "en-GB-RyanNeural",  label: "Voice 5 (British · Ryan)" },
        { id: "en-AU-NatashaNeural", label: "Voice 6 (Australian · Natasha)" }
    ]

    readonly property var geminiModels: [
        { id: "gemini-3.8-flash",       label: "Gemini 3.8 Flash (Latest & Fast)" },
        { id: "gemini-3.1-flash-lite",  label: "Gemini 3.1 Flash-Lite (Low Latency)" },
        { id: "gemini-3.7-flash",       label: "Gemini 3.7 Flash" },
        { id: "gemini-3.6-flash",       label: "Gemini 3.6 Flash" },
        { id: "gemini-3.5-flash",       label: "Gemini 3.5 Flash" }
    ]
    readonly property var visualSearchProviders: [
        { id: "google-lens", label: "Google Lens" },
        { id: "google-images", label: "Google Images" }
    ]

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string settingsPath: root.configHome + "/quickshell/shell27/siri_settings.json"
    readonly property string geminiConfigPath: root.configHome + "/quickshell/shell27/gemini_config.json"
    readonly property string daemonScriptPath: root.configHome + "/quickshell/shell27/scripts/siri_daemon.py"

    property alias testVoiceProc: testVoiceProc
    property alias testApiProc: testApiProc

    // FileView for settings persistence
    FileView {
        id: siriStore
        path: root.settingsPath
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.enabled !== undefined) root.siriEnabled = o.enabled;
                if (o.wake_word_enabled !== undefined) root.wakeWordEnabled = o.wake_word_enabled;
                if (o.live_voice_streaming !== undefined) root.liveVoiceStreaming = o.live_voice_streaming;
                if (o.preferred_response_type !== undefined) root.preferredResponseType = o.preferred_response_type;
                if (o.voice !== undefined) root.voice = o.voice;
                if (o.tts_voice_en !== undefined) root.ttsVoiceEn = o.tts_voice_en;
                if (o.speech_rate !== undefined) root.speechRate = o.speech_rate;
                if (o.edge_glow_intensity !== undefined) root.edgeGlowIntensity = o.edge_glow_intensity;
                if (o.model !== undefined) root.geminiModel = o.model;
                if (o.api_key !== undefined) root.apiKey = o.api_key;
                if (o.visual_intelligence_enabled !== undefined) root.visualIntelligenceEnabled = o.visual_intelligence_enabled;
                if (o.visual_text_selection_enabled !== undefined) root.visualTextSelectionEnabled = o.visual_text_selection_enabled;
                if (o.visual_search_provider !== undefined) root.visualSearchProvider = o.visual_search_provider;
                if (o.visual_image_in_chat !== undefined) root.visualImageInChat = o.visual_image_in_chat;
                if (o.visual_model !== undefined) root.visualModel = o.visual_model;
                if (o.delete_visual_image_after_response !== undefined) root.deleteVisualImageAfterResponse = o.delete_visual_image_after_response;
            } catch (e) {
                console.log("[SiriSettings] Parse error:", e);
            }
            root.isLoaded = true;
            root.syncWakeWordDaemon();
        }
        onLoadFailed: {
            root.isLoaded = true;
            root.saveSettings();
            root.syncWakeWordDaemon();
        }
    }

    Timer {
        id: saveDebounce
        interval: 350
        repeat: false
        onTriggered: root.writeToDisk()
    }

    function saveSettings() {
        if (!root.isLoaded) return;
        saveDebounce.restart();
    }

    function saveApiKeyImmediately() {
        if (!root.isLoaded) return;
        root.writeToDisk(false);
        saveDebounce.restart();
    }

    function syncWakeWordDaemon() {
        if (!root.isLoaded) return;
        if (daemonControlProc.running) {
            daemonControlProc.syncPending = true;
            return;
        }
        daemonControlProc.command = [
            "python3",
            root.daemonScriptPath,
            root.siriEnabled && root.wakeWordEnabled ? "--start-daemon" : "--stop-daemon"
        ];
        daemonControlProc.running = true;
    }

    Process {
        id: daemonControlProc
        running: false
        property bool syncPending: false
        onExited: {
            if (syncPending) {
                syncPending = false;
                root.syncWakeWordDaemon();
            }
        }
    }

    function writeToDisk(notify) {
        var o = {
            enabled: root.siriEnabled,
            wake_word_enabled: root.wakeWordEnabled,
            live_voice_streaming: root.liveVoiceStreaming,
            preferred_response_type: root.preferredResponseType,
            wake_words: ["hey siri", "siri"],
            language: "en-US",
            voice: root.ttsVoiceEn,
            tts_voice_en: root.ttsVoiceEn,
            speech_rate: root.speechRate,
            edge_glow_intensity: root.edgeGlowIntensity,
            model: root.geminiModel,
            api_key: root.apiKey,
            visual_intelligence_enabled: root.visualIntelligenceEnabled,
            visual_text_selection_enabled: root.visualTextSelectionEnabled,
            visual_search_provider: root.visualSearchProvider,
            visual_image_in_chat: root.visualImageInChat,
            visual_model: root.visualModel,
            delete_visual_image_after_response: root.deleteVisualImageAfterResponse
        };
        siriStore.setText(JSON.stringify(o, null, 2));

        // Sync with gemini_config.json
        geminiStore.setText(JSON.stringify({
            api_key: root.apiKey !== "" ? root.apiKey : "YOUR_GEMINI_API_KEY_HERE",
            model: root.geminiModel
        }, null, 2));

        if (notify !== false) {
            reloadProc.command = ["qs", "-c", "shell27", "ipc", "call", "siri", "state", "idle"];
            reloadProc.running = true;
        }
    }

    Process {
        id: reloadProc
        running: false
    }

    FileView {
        id: geminiStore
        path: root.geminiConfigPath
        printErrors: false
    }

    // Process to test TTS Voice
    Process {
        id: testVoiceProc
        property bool speaking: false
        onExited: speaking = false
    }

    readonly property var voicePreviewPhrases: [
        "Hi, I'm Siri. Choose the voice you'd like me to use.",
        "Hi, I'm Siri. What can I help you with?",
        "Hi, I'm Siri. I can help you get things done.",
        "Hi, I'm Siri. How can I help you today?"
    ]

    function runVoiceTest() {
        if (testVoiceProc.speaking) return;
        testVoiceProc.speaking = true;
        var phrase = voicePreviewPhrases[Math.floor(Math.random() * voicePreviewPhrases.length)];
        testVoiceProc.command = [
            "python3",
            root.daemonScriptPath,
            "--test-tts",
            phrase
        ];
        testVoiceProc.running = true;
    }

    // Process to test API
    Process {
        id: testApiProc
        property string statusMsg: ""
        property bool testing: false

        stdout: StdioCollector {
            onStreamFinished: {
                testApiProc.testing = false;
                if (text.indexOf("Error") >= 0 || text.indexOf("error") >= 0) {
                    testApiProc.statusMsg = I18n.tr("API Connection Failed");
                } else {
                    testApiProc.statusMsg = I18n.tr("API Connected Successfully!");
                }
            }
        }
        onExited: {
            testApiProc.testing = false;
        }
    }

    function runApiTest() {
        testApiProc.statusMsg = I18n.tr("Testing connection...");
        testApiProc.testing = true;
        testApiProc.command = [
            "python3",
            root.daemonScriptPath,
            "--test-api"
        ];
        testApiProc.running = true;
    }
}
