import QtQuick
import QtQuick.Effects
import "../components"
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../scripts/js/Fonts.js" as Fonts
import "../modules"

Scope {
    id: root
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    readonly property var dock: hub ? hub.dock : null
    property bool darkMode: true
    property bool configLoaded: false

    // ── Appearance sync: bar/dock (in-shell) OR gsettings (standalone) ──
    Connections {
        target: root.bar
        function onDarkModeChanged() { if (root.bar) root.darkMode = root.bar.darkMode; }
    }
    Connections {
        target: root.dock
        function onDarkModeChanged() { if (!root.bar && root.dock) root.darkMode = root.dock.darkMode; }
    }

    // Poll gsettings color-scheme so standalone Finder follows system appearance
    Process {
        id: gsettingsProc
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser {
            onRead: line => {
                var s = line.trim();
                if (s.indexOf("prefer-light") >= 0 && root.darkMode) root.darkMode = false;
                else if (s.indexOf("prefer-dark") >= 0 && !root.darkMode) root.darkMode = true;
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: false
        onTriggered: { gsettingsProc.running = false; gsettingsProc.running = true; }
    }

    // Also pick up bar/dock on first availability
    onBarChanged: if (bar) darkMode = bar.darkMode;
    onDockChanged: if (!bar && dock) darkMode = dock.darkMode;
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string home: Quickshell.env("HOME")
    readonly property url glassShaderUrl: dock && dock.glassShaderUrl ? dock.glassShaderUrl : Qt.resolvedUrl("../shaders/liquidglass.frag.qsb")

    property string instanceId: ""
    property bool openOnStart: Quickshell.env("FINDER_OPEN_ON_START") === "1"
    property string initialPath: Quickshell.env("FINDER_INITIAL_PATH") || ""
    property string pickerMode: Quickshell.env("FINDER_PICK_MODE") || ""   // "" | "open" | "open-multiple" | "folder" | "save"
    property string pickerTitle: Quickshell.env("FINDER_PICK_TITLE") || ""
    property string pickerSaveName: Quickshell.env("FINDER_PICK_SAVE_NAME") || ""
    property string pickerOutFile: Quickshell.env("FINDER_PICK_OUT") || ""
    readonly property bool isPickerMode: pickerMode !== ""
    property bool isDefaultFileManager: false

    // Visual theme tokens (adapts to Light & Dark Mode)
    readonly property color windowBg: darkMode ? "#1C1C1F" : "#FFFFFF"
    readonly property color sidebarBg: darkMode ? Qt.rgba(0.10, 0.11, 0.14, 0.72) : Qt.rgba(0.90, 0.91, 0.93, 0.92)
    readonly property color surfaceAlt: darkMode ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.04)
    readonly property color pillBase: darkMode ? "#252528" : "#D8DAE0"
    readonly property color pillBg: darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color pillHoverBg: darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color textPrimary: darkMode ? "#F5F7FF" : "#1D1D1F"
    readonly property color textMuted: darkMode ? Qt.rgba(1, 1, 1, 0.56) : Qt.rgba(0, 0, 0, 0.50)
    readonly property color lineCol: darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.18)
    readonly property color accentBlue: "#0A84FF"

    // View & layout state
    property string viewMode: "icon" // "icon" | "list" | "column" | "gallery"
    property string sortBy: "name"   // "name" | "date" | "size" | "kind" | "tag"
    property bool sortAsc: true
    property bool showHidden: false
    property bool showPathBar: false
    property bool showStatusBar: true
    property bool showPreview: false
    property bool showTabBar: false
    property bool sidebarCollapsed: false
    property bool searchExpanded: false
    property real iconScale: 80      // 44 .. 128
    property real targetIconScale: 80
    Behavior on iconScale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    readonly property var iconScaleSteps: [56, 80, 112]

    // Navigation & tabs
    property var tabs: []
    property int activeTabIndex: 0
    property string currentPath: home
    property string searchText: ""
    property string diskFreeText: ""
    property var items: []
    property var selectedPaths: []
    property string selectionAnchorPath: ""
    property var clipboardPaths: []
    property string clipboardMode: "copy"

    // Sidebar data
    property var sidebarCategories: []
    property bool itemDragging: false
    property var dragPaths: []
    property var dragLeadItem: null
    property real dragGhostX: 0
    property real dragGhostY: 0
    property real dragLastX: 0
    property real dragWiggleAngle: 0
    property int dragWiggleTick: 0
    property string dropHoverTargetPath: ""
    property var sidebarFavorites: []
    property var sidebarLocations: []
    property var sidebarIcloud: []
    property var activeSidebarItem: null
    property string activeSidebarCatId: "favorites"
    property var activeCategoryTarget: null
    property var sidebarTags: [
        { name: "Red", color: "#FF3B30" },
        { name: "Orange", color: "#FF9500" },
        { name: "Yellow", color: "#FFCC00" },
        { name: "Green", color: "#28CD41" },
        { name: "Blue", color: "#007AFF" },
        { name: "Purple", color: "#AF52DE" },
        { name: "Gray", color: "#8E8E93" }
    ]

    // List view inline expansion
    property var expandedDirs: ({})
    property var dirChildrenCache: ({})
    property var flatListEntries: []
    property var flatItemMap: ({})
    ListModel { id: flatListModel }
    property var iconItemMap: ({})
    ListModel { id: iconGridModel }

    // Column view (Miller columns)
    property var columns: [] // [{ path, items, selectedPath }]

    // Quick Look, Get Info & Open With state
    property bool quickLookOpen: false
    property bool getInfoOpen: false
    property bool openWithOpen: false
    property var openWithTarget: null
    property var openWithApps: []
    property string openWithMime: ""
    property string openWithSearch: ""
    property int openWithSelectedIdx: 0
    property bool openWithAlwaysDefault: false
    property bool archivePasswordOpen: false
    property string archivePasswordPath: ""
    property bool archivePasswordWrong: false
    property bool compressOpen: false
    property var compressPaths: []
    property string compressFormat: "zip"
    property string busyLabel: ""
    property string errorToast: ""
    property string previewTextContent: ""
    property int galleryIndex: 0

    // Rubberband selection state
    property rect rubberBandRect: Qt.rect(0, 0, 0, 0)
    property bool rubberBandActive: false
    property point rubberBandStart: Qt.point(0, 0)

    // Dialog / context targets
    property var contextItem: null
    property string renameTargetPath: ""
    property string renameTargetName: ""
    property int reqSeq: 0
    property string activeListReqId: ""
    property var pendingExpandReqs: ({})
    property var pendingColumnReqs: ({})

    // Sidebar drag-reorder state
    property string sidebarDragCatId: ""
    property int sidebarDragFromIdx: -1
    property int sidebarDragToIdx: -1
    property bool sidebarDragging: false

    Component.onCompleted: {
        if (instanceId === "") instanceId = Date.now().toString(36);
        Quickshell.execDetached([
            "hyprctl", "eval",
            "finder_window_rule = finder_window_rule or hl.window_rule({ name = \"finder-window\", match = { title = \"^Finder.*$\" }, float = true, center = true, border_size = 0, blur = true, ignore_alpha = 0.1 }); finder_picker_rule = finder_picker_rule or hl.window_rule({ name = \"finder-picker-window\", match = { title = \"^.* — Finder \\\\[.*\\\\]$\" }, float = true, center = true, border_size = 0, blur = true, ignore_alpha = 0.1 })"
        ]);
        var pickInit = Quickshell.env("FINDER_PICK_INITIAL") || "";
        var startPath = pickInit !== "" ? pickInit : (initialPath !== "" ? initialPath : home);
        tabs = [{ title: folderLabel(startPath), path: startPath, history: [startPath], histIdx: 0 }];
        currentPath = startPath;
        if (pickerMode === "save" && pickerSaveName !== "") {
            pickerSaveField.text = pickerSaveName;
        }
        if (!root.hub || root.openOnStart || root.isPickerMode) open(startPath);
    }

    function send(payload) {
        if (!daemon.running) return;
        daemon.write(JSON.stringify(payload) + "\n");
    }

    function nextReqId(prefix) {
        reqSeq += 1;
        return prefix + "-" + reqSeq;
    }

    function folderLabel(path) {
        if (!path || path === "/") return "Macintosh HD";
        if (path === "finder://recents") return "Recents";
        if (path === "finder://applications") return "Applications";
        if (path === "finder://trash") return "Trash";
        if (path === "finder://network") return "Network";
        if (path === "finder://airdrop") return "AirDrop";
        if (path.indexOf("finder://tag/") === 0) return path.slice(13) + " Tag";
        if (path === home) return path.split("/").pop() || "Home";
        var parts = path.replace(/\/+$/, "").split("/");
        return parts[parts.length - 1] || path;
    }

    function isArchiveName(name) {
        if (!name) return false;
        return /\.(zip|rar|tar|tar\.gz|tgz|tar\.xz|tar\.bz2|7z)$/i.test(name);
    }

    function tagColor(tagName) {
        for (var i = 0; i < sidebarTags.length; i++) {
            if (sidebarTags[i].name === tagName) return sidebarTags[i].color;
        }
        return "#8E8E93";
    }

    Timer {
        id: colTrimTimer
        property int keepCount: 1
        interval: 270
        onTriggered: {
            if (root.columns.length > keepCount) {
                root.columns = root.columns.slice(0, keepCount);
            }
        }
    }

    function refreshCurrent(skipColumnRebuild) {
        var reqId = nextReqId("list");
        activeListReqId = reqId;
        send({
            op: "list",
            reqId: reqId,
            path: currentPath,
            showHidden: showHidden,
            dark: darkMode,
            sortBy: sortBy,
            sortAsc: sortAsc,
            search: searchText
        });
        if (viewMode === "column" && !skipColumnRebuild) rebuildColumnsForPath(currentPath);
    }

    function navigateTo(path, pushHistory) {
        if (!path) return;
        if (pushHistory === undefined) pushHistory = true;
        currentPath = path;
        selectedPaths = [];
        selectionAnchorPath = "";
        expandedDirs = ({});
        dirChildrenCache = ({});
        flatItemMap = ({});
        flatListModel.clear();
        iconItemMap = ({});
        iconGridModel.clear();
        galleryIndex = 0;

        var copy = tabs.slice();
        if (copy[activeTabIndex]) {
            var tab = Object.assign({}, copy[activeTabIndex]);
            tab.path = path;
            tab.title = folderLabel(path);
            if (pushHistory) {
                var hist = tab.history.slice(0, tab.histIdx + 1);
                if (hist[hist.length - 1] !== path) {
                    hist.push(path);
                    tab.history = hist;
                    tab.histIdx = hist.length - 1;
                }
            }
            copy[activeTabIndex] = tab;
            tabs = copy;
        }

        // In Column View, if target path is already an ancestor column, animate back smoothly!
        var skipColRebuild = false;
        if (viewMode === "column" && columns.length > 1) {
            for (var k = 0; k < columns.length - 1; k++) {
                if (columns[k] && columns[k].path === path) {
                    skipColRebuild = true;
                    var cols = columns.slice();
                    cols[k] = Object.assign({}, cols[k], { selectedPath: "" });
                    columns = cols;
                    colTrimTimer.keepCount = k + 1;
                    colTrimTimer.restart();
                    var targetX = Math.max(0, (k + 1) * 228 - colFlick.width);
                    colFlick.contentX = targetX;
                    break;
                }
            }
        }
        refreshCurrent(skipColRebuild);
    }

    function canGoBack() {
        var t = tabs[activeTabIndex];
        return !!t && t.histIdx > 0;
    }

    function canGoForward() {
        var t = tabs[activeTabIndex];
        return !!t && t.histIdx < t.history.length - 1;
    }

    function goBack() {
        if (!canGoBack()) return;
        var copy = tabs.slice();
        var t = Object.assign({}, copy[activeTabIndex]);
        t.histIdx -= 1;
        copy[activeTabIndex] = t;
        tabs = copy;
        navigateTo(t.history[t.histIdx], false);
    }

    function goForward() {
        if (!canGoForward()) return;
        var copy = tabs.slice();
        var t = Object.assign({}, copy[activeTabIndex]);
        t.histIdx += 1;
        copy[activeTabIndex] = t;
        tabs = copy;
        navigateTo(t.history[t.histIdx], false);
    }

    function goEnclosing() {
        if (currentPath.indexOf("finder://") === 0 || currentPath === "/") return;
        var parts = currentPath.replace(/\/+$/, "").split("/");
        parts.pop();
        navigateTo(parts.length <= 1 ? "/" : parts.join("/"), true);
    }

    function addTab(path) {
        var p = path || currentPath || home;
        tabs = tabs.concat([{ title: folderLabel(p), path: p, history: [p], histIdx: 0 }]);
        activeTabIndex = tabs.length - 1;
        showTabBar = true;
        navigateTo(p, false);
    }

    function switchTab(idx) {
        if (idx < 0 || idx >= tabs.length) return;
        activeTabIndex = idx;
        navigateTo(tabs[idx].path, false);
    }

    property int closingTabIndex: -1
    property int pendingRemoveTabIdx: -1

    ListModel { id: tabBarModel }

    function syncTabBarModel() {
        var n = tabs ? tabs.length : 0;
        if (pendingRemoveTabIdx >= 0 && n === tabBarModel.count - 1) {
            var rIdx = pendingRemoveTabIdx;
            pendingRemoveTabIdx = -1;
            tabBarModel.remove(rIdx, 1);
            for (var u = 0; u < n; u++) {
                tabBarModel.setProperty(u, "title", tabs[u].title || "");
            }
            return;
        }
        pendingRemoveTabIdx = -1;
        if (n === tabBarModel.count) {
            for (var i = 0; i < n; i++) {
                tabBarModel.setProperty(i, "title", tabs[i].title || "");
            }
            return;
        }
        if (n === tabBarModel.count + 1 && tabBarModel.count > 0) {
            for (var j = 0; j < tabBarModel.count; j++) {
                tabBarModel.setProperty(j, "title", tabs[j].title || "");
            }
            tabBarModel.append({ title: tabs[n - 1].title || "" });
            return;
        }
        tabBarModel.clear();
        for (var k = 0; k < n; k++) {
            tabBarModel.append({ title: tabs[k].title || "" });
        }
    }

    Timer {
        id: closeTabTimer
        property int targetIdx: -1
        interval: 140
        onTriggered: {
            var idx = targetIdx;
            root.closingTabIndex = -1;
            if (idx < 0 || idx >= root.tabs.length) return;
            if (root.tabs.length <= 1) { win.visible = false; return; }
            var copy = root.tabs.slice();
            copy.splice(idx, 1);
            root.pendingRemoveTabIdx = idx;
            root.tabs = copy;
            if (root.activeTabIndex >= root.tabs.length) root.activeTabIndex = root.tabs.length - 1;
            root.navigateTo(root.tabs[root.activeTabIndex].path, false);
        }
    }

    function closeTab(idx) {
        if (tabs.length <= 1) { win.visible = false; return; }
        if (closingTabIndex >= 0) return;
        closingTabIndex = idx;
        closeTabTimer.targetIdx = idx;
        closeTabTimer.restart();
    }

    function isSelected(path) {
        return selectedPaths.indexOf(path) >= 0;
    }

    function primarySelectedItem() {
        if (selectedPaths.length === 0) return null;
        var target = selectedPaths[0];
        for (var i = 0; i < items.length; i++) if (items[i].path === target) return items[i];
        for (var k in dirChildrenCache) {
            var arr = dirChildrenCache[k];
            for (var j = 0; j < arr.length; j++) if (arr[j].path === target) return arr[j];
        }
        for (var c = 0; c < columns.length; c++) {
            var cItems = columns[c].items || [];
            for (var m = 0; m < cItems.length; m++) if (cItems[m].path === target) return cItems[m];
        }
        return null;
    }

    function selectedItemsList() {
        var out = [];
        for (var i = 0; i < items.length; i++) {
            if (selectedPaths.indexOf(items[i].path) >= 0) out.push(items[i]);
        }
        if (out.length === 0 && selectedPaths.length > 0) {
            var p = primarySelectedItem();
            if (p) out.push(p);
        }
        return out;
    }

    function totalSelectedBytes() {
        var list = selectedItemsList();
        var sum = 0;
        for (var i = 0; i < list.length; i++) sum += Number(list[i].size || 0);
        return sum;
    }

    function formatBytes(n) {
        if (n < 1024) return n + " bytes";
        var units = ["KB", "MB", "GB", "TB"];
        for (var i = 0; i < units.length; i++) {
            n /= 1024.0;
            if (n < 1024.0 || i === units.length - 1) return (n < 10 ? n.toFixed(1) : Math.round(n)) + " " + units[i];
        }
        return "0 bytes";
    }

    function formatDate(ms) {
        if (!ms) return "--";
        return Qt.formatDateTime(new Date(Number(ms)), "MMM d, yyyy 'at' h:mm AP");
    }

    function openWithFor(item) {
        if (!item || item.isDir) return;
        openWithTarget = item;
        openWithApps = [];
        openWithMime = "";
        openWithSearch = "";
        openWithSelectedIdx = 0;
        openWithAlwaysDefault = false;
        openWithOpen = true;
        send({ op: "listApps", path: item.path, dark: darkMode });
    }

    function filteredOpenWithApps() {
        var q = openWithSearch.trim().toLowerCase();
        if (!q) return openWithApps;
        var out = [];
        for (var i = 0; i < openWithApps.length; i++) {
            if (openWithApps[i].name.toLowerCase().indexOf(q) >= 0) out.push(openWithApps[i]);
        }
        return out;
    }

    function openCompressFor(paths) {
        if (!paths || paths.length === 0) return;
        compressPaths = paths.slice();
        compressFormat = "zip";
        var baseName = "Archive";
        if (paths.length === 1) {
            var fn = folderLabel(paths[0]);
            var dot = fn.lastIndexOf(".");
            baseName = dot > 0 ? fn.slice(0, dot) : fn;
        }
        compressNameField.text = baseName;
        compressPwdField.text = "";
        compressOpen = true;
        compressNameField.forceActiveFocus();
        compressNameField.selectAll();
    }

    function selectItem(item, modifiers, scopeItems) {
        if (!item) { selectedPaths = []; selectionAnchorPath = ""; return; }
        var list = scopeItems || (viewMode === "list" ? flatListEntries.map(function (e) { return e.item; }) : items);
        var ctrl = (modifiers & Qt.ControlModifier) !== 0;
        var shift = (modifiers & Qt.ShiftModifier) !== 0;
        if (ctrl) {
            var next = selectedPaths.slice();
            var idx = next.indexOf(item.path);
            if (idx >= 0) next.splice(idx, 1);
            else {
                next.push(item.path);
                selectionAnchorPath = item.path;
            }
            selectedPaths = next;
        } else if (shift && (selectionAnchorPath !== "" || selectedPaths.length > 0)) {
            var a = -1, b = -1;
            var anchor = selectionAnchorPath !== "" ? selectionAnchorPath : selectedPaths[0];
            for (var i = 0; i < list.length; i++) {
                if (list[i].path === anchor) a = i;
                if (list[i].path === item.path) b = i;
            }
            if (a >= 0 && b >= 0) {
                var lo = Math.min(a, b), hi = Math.max(a, b);
                var range = [];
                for (var k = lo; k <= hi; k++) range.push(list[k].path);
                selectedPaths = range;
            } else {
                selectedPaths = [item.path];
                selectionAnchorPath = item.path;
            }
        } else {
            selectedPaths = [item.path];
            selectionAnchorPath = item.path;
        }

        // Update gallery index & text preview if needed
        for (var g = 0; g < items.length; g++) {
            if (items[g].path === item.path) { galleryIndex = g; break; }
        }
        if (item.isText && (showPreview || quickLookOpen || viewMode === "column")) {
            var reqId = nextReqId("text");
            send({ op: "previewText", reqId: reqId, path: item.path });
        } else {
            previewTextContent = "";
        }
    }

    function confirmPicker(explicitPaths) {
        if (!isPickerMode) return;
        var chosen = [];
        if (explicitPaths && explicitPaths.length > 0) {
            chosen = explicitPaths;
        } else if (pickerMode === "save") {
            var fn = pickerSaveField.text.trim();
            if (fn === "") return;
            var base = currentPath === "/" ? "" : currentPath.replace(/\/+$/, "");
            chosen = [base + "/" + fn];
        } else if (pickerMode === "folder") {
            var pItem = primarySelectedItem();
            if (pItem && pItem.isDir) chosen = [pItem.path];
            else if (currentPath.indexOf("finder://") !== 0) chosen = [currentPath];
        } else {
            if (selectedPaths.length > 0) {
                chosen = pickerMode === "open-multiple" ? selectedPaths.slice() : [selectedPaths[0]];
            }
        }
        if (chosen.length === 0) return;
        send({ op: "pickerResult", outFile: pickerOutFile, paths: chosen, cancelled: false });
    }

    function cancelPicker() {
        if (!isPickerMode) { win.visible = false; return; }
        send({ op: "pickerResult", outFile: pickerOutFile, paths: [], cancelled: true });
    }

    function activateItem(item) {
        if (!item) return;
        if (item.isDir) {
            navigateTo(item.path, true);
        } else if (isPickerMode && (pickerMode === "open" || pickerMode === "open-multiple")) {
            confirmPicker([item.path]);
        } else {
            send({ op: "open", path: item.path });
        }
    }

    function toggleListExpand(item) {
        if (!item || !item.isDir) return;
        var next = Object.assign({}, expandedDirs);
        if (next[item.path]) {
            delete next[item.path];
            expandedDirs = next;
            rebuildFlatList();
        } else {
            next[item.path] = true;
            expandedDirs = next;
            if (dirChildrenCache[item.path]) {
                rebuildFlatList();
            } else {
                var reqId = nextReqId("expand");
                var pMap = Object.assign({}, pendingExpandReqs);
                pMap[reqId] = item.path;
                pendingExpandReqs = pMap;
                send({ op: "list", reqId: reqId, path: item.path, showHidden: showHidden, dark: darkMode, sortBy: sortBy, sortAsc: sortAsc, search: "" });
            }
        }
    }

    function syncIconGridModel() {
        var arr = items || [];
        var mapUpdate = Object.assign({}, iconItemMap);
        for (var m = 0; m < arr.length; m++) {
            mapUpdate[arr[m].path] = arr[m];
        }
        iconItemMap = mapUpdate;

        if (iconGridModel.count === 0 || arr.length === 0) {
            iconGridModel.clear();
            for (var a = 0; a < arr.length; a++) {
                iconGridModel.append({ path: arr[a].path });
            }
            return;
        }

        var idx = 0;
        while (idx < arr.length) {
            var tPath = arr[idx].path;
            if (idx < iconGridModel.count && iconGridModel.get(idx).path === tPath) {
                idx++;
            } else {
                var foundIdx = -1;
                for (var s = idx + 1; s < iconGridModel.count; s++) {
                    if (iconGridModel.get(s).path === tPath) {
                        foundIdx = s;
                        break;
                    }
                }
                if (foundIdx >= 0) {
                    iconGridModel.remove(idx, foundIdx - idx);
                } else {
                    iconGridModel.insert(idx, { path: tPath });
                    idx++;
                }
            }
        }
        if (iconGridModel.count > arr.length) {
            iconGridModel.remove(arr.length, iconGridModel.count - arr.length);
        }
    }

    function rebuildFlatList() {
        var out = [];
        var mapUpdate = Object.assign({}, flatItemMap);
        function walk(arr, depth) {
            for (var i = 0; i < arr.length; i++) {
                var it = arr[i];
                mapUpdate[it.path] = it;
                out.push({ item: it, depth: depth });
                if (it.isDir && expandedDirs[it.path] && dirChildrenCache[it.path]) {
                    walk(dirChildrenCache[it.path], depth + 1);
                }
            }
        }
        walk(items, 0);
        flatItemMap = mapUpdate;
        flatListEntries = out;

        if (flatListModel.count === 0 || out.length === 0) {
            flatListModel.clear();
            for (var a = 0; a < out.length; a++) {
                flatListModel.append({ path: out[a].item.path, depth: out[a].depth });
            }
            return;
        }

        var idx = 0;
        while (idx < out.length) {
            var target = out[idx];
            var tPath = target.item.path;
            var tDepth = target.depth;
            if (idx < flatListModel.count && flatListModel.get(idx).path === tPath) {
                if (flatListModel.get(idx).depth !== tDepth) {
                    flatListModel.setProperty(idx, "depth", tDepth);
                }
                idx++;
            } else {
                var foundIdx = -1;
                for (var s = idx + 1; s < flatListModel.count; s++) {
                    if (flatListModel.get(s).path === tPath) {
                        foundIdx = s;
                        break;
                    }
                }
                if (foundIdx >= 0) {
                    flatListModel.remove(idx, foundIdx - idx);
                } else {
                    flatListModel.insert(idx, { path: tPath, depth: tDepth });
                    idx++;
                }
            }
        }
        if (flatListModel.count > out.length) {
            flatListModel.remove(out.length, flatListModel.count - out.length);
        }
    }

    function rebuildColumnsForPath(path) {
        colTrimTimer.stop();
        columns = [{ path: path, items: items, selectedPath: "" }];
        var reqId = nextReqId("col");
        var m = Object.assign({}, pendingColumnReqs);
        m[reqId] = 0;
        pendingColumnReqs = m;
        send({ op: "list", reqId: reqId, path: path, showHidden: showHidden, dark: darkMode, sortBy: sortBy, sortAsc: sortAsc, search: "" });
    }

    function selectColumnItem(colIndex, item, modifiers) {
        colTrimTimer.stop();
        var colItems = (columns[colIndex] && columns[colIndex].items) ? columns[colIndex].items : items;
        selectItem(item, modifiers || 0, colItems);
        var isMulti = ((modifiers || 0) & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
        var cols = columns.slice();
        cols[colIndex] = Object.assign({}, cols[colIndex], { selectedPath: item.path });
        if (item.isDir && !isMulti) {
            cols = cols.slice(0, colIndex + 1);
            columns = cols;
            var nextIdx = colIndex + 1;
            columns = columns.concat([{ path: item.path, items: [], selectedPath: "" }]);
            var reqId = nextReqId("col");
            var m = Object.assign({}, pendingColumnReqs);
            m[reqId] = nextIdx;
            pendingColumnReqs = m;
            send({ op: "list", reqId: reqId, path: item.path, showHidden: showHidden, dark: darkMode, sortBy: sortBy, sortAsc: sortAsc, search: "" });
        } else {
            // Clicking a file in an earlier column: animate back smoothly before trimming trailing columns
            columns = cols;
            if (colIndex + 1 < cols.length) {
                colTrimTimer.keepCount = colIndex + 1;
                colTrimTimer.restart();
                colFlick.contentX = Math.max(0, (colIndex + 1) * 228 - colFlick.width);
            }
        }
    }

    function setSort(field) {
        if (sortBy === field) sortAsc = !sortAsc;
        else { sortBy = field; sortAsc = true; }
        refreshCurrent();
    }

    function setViewMode(mode) {
        viewMode = mode;
        if (mode === "column") rebuildColumnsForPath(currentPath);
        else if (mode === "list") rebuildFlatList();
    }

    function iconScaleIndex() {
        var best = 0;
        for (var i = 1; i < iconScaleSteps.length; i++)
            if (Math.abs(iconScale - iconScaleSteps[i]) < Math.abs(iconScale - iconScaleSteps[best])) best = i;
        return best;
    }
    function setIconScaleIndex(index) {
        var v = iconScaleSteps[Math.max(0, Math.min(iconScaleSteps.length - 1, index))];
        targetIconScale = v;
        iconScale = v;
    }

    function zoomIconScale(delta) {
        var next = Math.max(44, Math.min(128, targetIconScale + delta));
        targetIconScale = next;
        iconScale = next;
    }

    function isDotHidden(it) {
        if (!it) return false;
        var nm = it.name || it.displayName || "";
        return nm.length > 0 && nm.charAt(0) === ".";
    }

    function canDropOn(targetPath) {
        if (!targetPath || dragPaths.length === 0) return false;
        if (targetPath.indexOf("finder://") === 0 && targetPath !== "finder://trash") return false;
        var normTarget = targetPath.length > 1 ? targetPath.replace(/\/+$/, "") : targetPath;
        for (var i = 0; i < dragPaths.length; i++) {
            var src = dragPaths[i];
            var normSrc = src.length > 1 ? src.replace(/\/+$/, "") : src;
            if (normTarget === normSrc) return false;
            if (normTarget.indexOf(normSrc + "/") === 0) return false;
            if (targetPath !== "finder://trash") {
                var slashIdx = normSrc.lastIndexOf("/");
                var parentDir = slashIdx <= 0 ? "/" : normSrc.substring(0, slashIdx);
                if (parentDir === normTarget) return false;
            }
        }
        return true;
    }

    function copySelection(mode) {
        if (selectedPaths.length === 0) return;
        clipboardPaths = selectedPaths.slice();
        clipboardMode = mode === "move" ? "move" : "copy";
        // Separate Finder windows have distinct QML root objects.
        send({ op: "clipboardSet", paths: clipboardPaths, mode: clipboardMode });
    }

    function pasteInto(dest) {
        if (!dest || dest.indexOf("finder://") === 0) return;
        // Always resolve shared state so this works after changing tab/window.
        send({ op: "clipboardGet", dest: dest });
    }

    function receiveDroppedUrls(urls, dest) {
        if (!urls || !dest || dest.indexOf("finder://") === 0) return;
        var paths = [];
        for (var i = 0; i < urls.length; i++) {
            var raw = String(urls[i]);
            if (raw.indexOf("file://") === 0) paths.push(decodeURIComponent(raw.slice(7)));
        }
        if (paths.length > 0) send({ op: "paste", mode: "move", sources: paths, dest: dest });
    }

    function dragUris() {
        var urls = [];
        for (var i = 0; i < dragPaths.length; i++) urls.push("file://" + encodeURI(dragPaths[i]));
        return urls;
    }

    function startNativeDrag(source) {
        // Drag.Automatic asks Qt to use the Wayland/X11 drag protocol, which
        // lets DropArea in another Finder process receive the file URLs.
        if (source) source.Drag.startDrag(Qt.MoveAction);
    }

    function findDropTargetAt(wx, wy) {
        // The old hit-test omitted tabs, so their paths could never be drops.
        if (tabBar.visible) {
            for (var t = 0; t < tabRowRepeater.count; t++) {
                var tab = tabRowRepeater.itemAt(t);
                if (!tab) continue;
                var tabPos = tab.mapToItem(windowFrame, 0, 0);
                if (wx >= tabPos.x && wx <= tabPos.x + tab.width && wy >= tabPos.y && wy <= tabPos.y + tab.height) {
                    var tabPath = root.tabs[t] ? root.tabs[t].path : "";
                    return canDropOn(tabPath) ? tabPath : "";
                }
            }
        }
        // 1. Bottom Path Bar breadcrumbs
        if (root.showPathBar && !win.pathBarEditing) {
            var pbPos = pathBarContainer.mapToItem(windowFrame, 0, 0);
            if (wx >= pbPos.x && wx <= pbPos.x + pathBarContainer.width && wy >= pbPos.y && wy <= pbPos.y + pathBarContainer.height) {
                for (var b = 0; b < crumbRepeater.count; b++) {
                    var cItem = crumbRepeater.itemAt(b);
                    if (!cItem) continue;
                    var cp = cItem.mapToItem(windowFrame, 0, 0);
                    if (wx >= cp.x && wx <= cp.x + cItem.width && wy >= cp.y && wy <= cp.y + cItem.height) {
                        var bPath = cItem.crumbPath;
                        return canDropOn(bPath) ? bPath : "";
                    }
                }
                return "";
            }
        }
        // 2. Sidebar pinned items
        if (!root.sidebarCollapsed) {
            var sbPos = sidebarCard.mapToItem(windowFrame, 0, 0);
            if (wx >= sbPos.x && wx <= sbPos.x + sidebarCard.width && wy >= sbPos.y && wy <= sbPos.y + sidebarCard.height) {
                for (var c = 0; c < sidebarCatRepeater.count; c++) {
                    var catObj = sidebarCatRepeater.itemAt(c);
                    if (!catObj || !catObj.itemsRepeater) continue;
                    var rep = catObj.itemsRepeater;
                    for (var s = 0; s < rep.count; s++) {
                        var sItem = rep.itemAt(s);
                        if (!sItem) continue;
                        var sp = sItem.mapToItem(windowFrame, 0, 0);
                        if (wx >= sp.x && wx <= sp.x + sItem.width && wy >= sp.y && wy <= sp.y + sItem.height) {
                            var sPath = sItem.modelData ? sItem.modelData.path : "";
                            return canDropOn(sPath) ? sPath : "";
                        }
                    }
                }
                return "";
            }
        }
        // 3. Active View folders
        if (root.viewMode === "icon") {
            var ig = windowFrame.mapToItem(iconGrid, wx, wy);
            if (ig.x >= 0 && ig.x <= iconGrid.width && ig.y >= 0 && ig.y <= iconGrid.height) {
                var cell = iconGrid.itemAt(ig.x + iconGrid.contentX, ig.y + iconGrid.contentY);
                if (cell && cell.modelData && cell.modelData.isDir && canDropOn(cell.modelData.path)) {
                    return cell.modelData.path;
                }
            }
        } else if (root.viewMode === "list") {
            var lv = windowFrame.mapToItem(listView, wx, wy);
            if (lv.x >= 0 && lv.x <= listView.width && lv.y >= 0 && lv.y <= listView.height) {
                var lrow = listView.itemAt(lv.x + listView.contentX, lv.y + listView.contentY);
                if (lrow && lrow.it && lrow.it.isDir && canDropOn(lrow.it.path)) {
                    return lrow.it.path;
                }
            }
        } else if (root.viewMode === "column") {
            for (var k = 0; k < colRepeater.count; k++) {
                var colWrap = colRepeater.itemAt(k);
                if (!colWrap || !colWrap.colListView) continue;
                var clv = colWrap.colListView;
                var cp2 = windowFrame.mapToItem(clv, wx, wy);
                if (cp2.x >= 0 && cp2.x <= clv.width && cp2.y >= 0 && cp2.y <= clv.height) {
                    var crow = clv.itemAt(cp2.x + clv.contentX, cp2.y + clv.contentY);
                    if (crow && crow.modelData && crow.modelData.isDir && canDropOn(crow.modelData.path)) {
                        return crow.modelData.path;
                    }
                }
            }
        }
        return "";
    }

    function startItemDrag(it, wx, wy) {
        if (!it || !it.path) return;
        if (isSelected(it.path) && selectedPaths.length > 0) {
            dragPaths = selectedPaths.slice();
        } else {
            selectedPaths = [it.path];
            selectionAnchorPath = it.path;
            dragPaths = [it.path];
        }
        dragLeadItem = it;
        dragGhostX = wx;
        dragGhostY = wy;
        dragLastX = wx;
        dragWiggleAngle = 0;
        dragWiggleTick = 0;
        dropHoverTargetPath = findDropTargetAt(wx, wy);
        itemDragging = true;
    }

    function updateItemDrag(wx, wy) {
        if (!itemDragging) return;
        var vx = wx - dragLastX;
        dragLastX = wx;
        dragGhostX = wx;
        dragGhostY = wy;
        dragWiggleTick += 1;
        var wobble = Math.sin(dragWiggleTick * 0.65) * (Math.abs(vx) > 0.6 ? 4.2 : 1.4);
        dragWiggleAngle = Math.max(-16, Math.min(16, vx * 0.65 + wobble));
        dropHoverTargetPath = findDropTargetAt(wx, wy);
    }

    function finishItemDrag() {
        if (!itemDragging) return;
        var target = dropHoverTargetPath;
        var sources = dragPaths.slice();
        itemDragging = false;
        dropHoverTargetPath = "";
        dragPaths = [];
        dragLeadItem = null;
        dragWiggleAngle = 0;
        if (target && sources.length > 0) {
            if (target === "finder://trash") {
                send({ op: "trash", paths: sources });
            } else {
                send({ op: "paste", mode: "move", sources: sources, dest: target });
            }
            selectedPaths = [];
        }
    }

    Timer {
        id: dragAutoScrollTimer
        interval: 16
        repeat: true
        running: root.itemDragging
        onTriggered: {
            var wx = root.dragGhostX;
            var wy = root.dragGhostY;
            var zone = 46;
            var scrolled = false;

            function scrollFlick(f, localY, stopAnim) {
                if (!f || f.height <= 0 || f.contentHeight <= f.height) return false;
                var delta = 0;
                if (localY >= 0 && localY < zone) {
                    delta = -Math.max(2, ((zone - localY) / zone) * 11);
                } else if (localY > f.height - zone && localY <= f.height) {
                    delta = Math.max(2, ((localY - (f.height - zone)) / zone) * 11);
                }
                if (delta === 0) return false;
                var maxY = Math.max(0, f.contentHeight - f.height);
                var nextY = Math.max(0, Math.min(maxY, f.contentY + delta));
                if (Math.abs(nextY - f.contentY) < 0.1) return false;
                if (stopAnim) {
                    iconScrollAnim.stop();
                    f.targetScrollY = nextY;
                }
                f.contentY = nextY;
                return true;
            }

            if (root.viewMode === "icon") {
                var ig = windowFrame.mapToItem(iconGrid, wx, wy);
                if (ig.x >= 0 && ig.x <= iconGrid.width) scrolled = scrollFlick(iconGrid, ig.y, true);
            } else if (root.viewMode === "list") {
                var lv = windowFrame.mapToItem(listView, wx, wy);
                if (lv.x >= 0 && lv.x <= listView.width) scrolled = scrollFlick(listView, lv.y, false);
            } else if (root.viewMode === "column") {
                for (var k = 0; k < colRepeater.count; k++) {
                    var colWrap = colRepeater.itemAt(k);
                    if (!colWrap || !colWrap.colListView) continue;
                    var clv = colWrap.colListView;
                    var cp = windowFrame.mapToItem(clv, wx, wy);
                    if (cp.x >= 0 && cp.x <= clv.width) {
                        if (scrollFlick(clv, cp.y, false)) { scrolled = true; break; }
                    }
                }
            }

            if (scrolled) {
                root.dropHoverTargetPath = root.findDropTargetAt(wx, wy);
            }
        }
    }

    function open(path) {
        if (path && path !== "") navigateTo(path, true);
        else refreshCurrent();
        win.visible = true;
        win.raise();
        win.requestActivate();
    }

    function windowSelector() {
        return 'window = "title:^(' + win.title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ')$"';
    }

    function breadcrumbParts() {
        if (currentPath.indexOf("finder://") === 0) return [{ label: folderLabel(currentPath), path: currentPath }];
        if (currentPath === "/") return [{ label: "Macintosh HD", path: "/" }];
        var raw = currentPath.split("/").filter(function (s) { return s !== ""; });
        var out = [{ label: "Macintosh HD", path: "/" }];
        var acc = "";
        for (var i = 0; i < raw.length; i++) {
            acc += "/" + raw[i];
            out.push({ label: raw[i], path: acc });
        }
        return out;
    }

    function selectAll() {
        var all = [];
        for (var i = 0; i < items.length; i++) all.push(items[i].path);
        selectedPaths = all;
    }

    function moveSelection(deltaX, deltaY) {
        if (items.length === 0) return;
        var curIdx = -1;
        if (selectedPaths.length > 0) {
            var curP = selectedPaths[0];
            for (var i = 0; i < items.length; i++) {
                if (items[i].path === curP) { curIdx = i; break; }
            }
        }
        var nextIdx = curIdx;
        if (viewMode === "icon") {
            var cellW = iconScale + 44;
            var cols = Math.max(1, Math.floor((win.width - 224 - 32) / cellW));
            if (curIdx === -1) nextIdx = 0;
            else {
                var target = curIdx + deltaX + deltaY * cols;
                nextIdx = Math.max(0, Math.min(items.length - 1, target));
            }
        } else if (viewMode === "gallery") {
            if (curIdx === -1) nextIdx = 0;
            else nextIdx = Math.max(0, Math.min(items.length - 1, curIdx + deltaX + deltaY));
            galleryIndex = nextIdx;
        } else {
            if (curIdx === -1) nextIdx = 0;
            else nextIdx = Math.max(0, Math.min(items.length - 1, curIdx + deltaY + deltaX));
        }
        if (nextIdx >= 0 && nextIdx < items.length) {
            selectItem(items[nextIdx], 0);
        }
    }

    function updateRubberBandSelection() {
        if (!rubberBandActive || viewMode !== "icon") return;
        var rx = rubberBandRect.x;
        var ry = rubberBandRect.y + iconGrid.contentY;
        var rw = rubberBandRect.width;
        var rh = rubberBandRect.height;
        var cols = Math.max(1, Math.floor(iconGrid.width / iconGrid.cellWidth));
        var newSel = [];
        for (var i = 0; i < items.length; i++) {
            var col = i % cols;
            var row = Math.floor(i / cols);
            var cx = col * iconGrid.cellWidth;
            var cy = row * iconGrid.cellHeight;
            var cw = iconGrid.cellWidth;
            var ch = iconGrid.cellHeight;
            if (rx < cx + cw && rx + rw > cx && ry < cy + ch && ry + rh > cy) {
                newSel.push(items[i].path);
            }
        }
        selectedPaths = newSel;
    }

    function handleEvent(ev) {
        if (ev.event === "sidebar") {
            sidebarCategories = ev.categories || [];
            sidebarFavorites = ev.favorites || [];
            sidebarLocations = ev.locations || [];
            sidebarIcloud = ev.cloud || [];
            if (ev.tags) sidebarTags = ev.tags;
        } else if (ev.event === "listed") {
            var reqId = ev.reqId || "";
            if (reqId === activeListReqId) {
                items = ev.items || [];
                diskFreeText = ev.diskFree || "";
                syncIconGridModel();
                rebuildFlatList();
                if (viewMode === "column" && columns.length === 0) {
                    columns = [{ path: currentPath, items: items, selectedPath: "" }];
                }
            } else if (pendingExpandReqs[reqId]) {
                var dirPath = pendingExpandReqs[reqId];
                var nextCache = Object.assign({}, dirChildrenCache);
                nextCache[dirPath] = ev.items || [];
                dirChildrenCache = nextCache;
                var pMap = Object.assign({}, pendingExpandReqs);
                delete pMap[reqId];
                pendingExpandReqs = pMap;
                rebuildFlatList();
            } else if (pendingColumnReqs[reqId] !== undefined) {
                var colIdx = pendingColumnReqs[reqId];
                var cMap = Object.assign({}, pendingColumnReqs);
                delete cMap[reqId];
                pendingColumnReqs = cMap;
                if (colIdx < columns.length) {
                    var cols = columns.slice();
                    cols[colIdx] = Object.assign({}, cols[colIdx], { items: ev.items || [] });
                    columns = cols;
                }
            }
        } else if (ev.event === "thumb") {
            var p = ev.path, th = ev.thumb;
            var changed = false;
            var updated = items.map(function (it) {
                if (it.path !== p) return it;
                changed = true;
                return Object.assign({}, it, { thumb: th });
            });
            if (changed) {
                items = updated;
                var mCopy = Object.assign({}, iconItemMap);
                for (var u = 0; u < updated.length; u++) mCopy[updated[u].path] = updated[u];
                iconItemMap = mCopy;
                var fCopy = Object.assign({}, flatItemMap);
                for (var f = 0; f < updated.length; f++) fCopy[updated[f].path] = updated[f];
                flatItemMap = fCopy;
            }
        } else if (ev.event === "mutated") {
            refreshCurrent();
            if (ev.select) selectedPaths = [ev.select];
        } else if (ev.event === "clipboard") {
            clipboardPaths = ev.paths || [];
            clipboardMode = ev.mode === "move" ? "move" : "copy";
            var destination = ev.dest || "";
            if (clipboardPaths.length > 0 && destination && destination.indexOf("finder://") !== 0)
                send({ op: "paste", mode: clipboardMode, sources: clipboardPaths, dest: destination });
        } else if (ev.event === "previewText") {
            previewTextContent = ev.text || "";
        } else if (ev.event === "appsList") {
            openWithApps = ev.apps || [];
            openWithMime = ev.mime || "";
            openWithSelectedIdx = 0;
        } else if (ev.event === "extractPasswordRequired") {
            archivePasswordPath = ev.path || "";
            archivePasswordWrong = !!ev.wrongPassword;
            archivePwdField.text = "";
            archivePasswordOpen = true;
            archivePwdField.forceActiveFocus();
        } else if (ev.event === "busy") {
            busyLabel = ev.label || "Working…";
        } else if (ev.event === "busyDone") {
            busyLabel = "";
            if (ev.label) {
                errorToast = ev.label;
                errorToastTimer.restart();
            }
        } else if (ev.event === "defaultFileManager") {
            isDefaultFileManager = !!ev.isDefault;
        } else if (ev.event === "pickerSaved") {
            Qt.quit();
        } else if (ev.event === "error") {
            busyLabel = "";
            errorToast = ev.message || "Operation failed";
            errorToastTimer.restart();
        } else if (ev.event === "config") {
            var c = ev.config || {};
            if (c.viewMode) viewMode = c.viewMode;
            if (c.sortBy) sortBy = c.sortBy;
            if (c.sortAsc !== undefined) sortAsc = !!c.sortAsc;
            if (c.showHidden !== undefined) showHidden = !!c.showHidden;
            if (c.showPathBar !== undefined) showPathBar = !!c.showPathBar;
            if (c.showStatusBar !== undefined) showStatusBar = !!c.showStatusBar;
            if (c.showPreview !== undefined) showPreview = !!c.showPreview;
            if (c.showTabBar !== undefined) showTabBar = !!c.showTabBar;
            if (c.iconScale !== undefined) iconScale = Number(c.iconScale);
            if (c.sidebarCollapsed !== undefined && win.width >= 820) sidebarCollapsed = !!c.sidebarCollapsed;

            if (initialPath === "") {
                if (c.lastTabs && c.lastTabs.length > 0) {
                    var restored = [];
                    for (var ti = 0; ti < c.lastTabs.length; ti++) {
                        var tp = c.lastTabs[ti].path || home;
                        restored.push({ title: folderLabel(tp), path: tp, history: [tp], histIdx: 0 });
                    }
                    tabs = restored;
                    var aIdx = Math.max(0, Math.min(restored.length - 1, Number(c.activeTabIndex || 0)));
                    activeTabIndex = aIdx;
                    currentPath = restored[aIdx].path;
                    if (restored.length > 1) showTabBar = true;
                } else if (c.lastPath && c.lastPath !== "") {
                    currentPath = c.lastPath;
                    tabs = [{ title: folderLabel(c.lastPath), path: c.lastPath, history: [c.lastPath], histIdx: 0 }];
                    activeTabIndex = 0;
                }
            }
            configLoaded = true;
            refreshCurrent();
        }
    }

    Timer {
        id: saveConfigTimer
        interval: 220
        onTriggered: root.persistConfigNow()
    }

    function scheduleSaveConfig() {
        if (!configLoaded) return;
        saveConfigTimer.restart();
    }

    function persistConfigNow() {
        if (!configLoaded) return;
        var tabSnapshots = [];
        for (var i = 0; i < tabs.length; i++) {
            tabSnapshots.push({ path: tabs[i].path, title: tabs[i].title });
        }
        send({
            op: "saveConfig",
            config: {
                viewMode: viewMode,
                sortBy: sortBy,
                sortAsc: sortAsc,
                showHidden: showHidden,
                showPathBar: showPathBar,
                showStatusBar: showStatusBar,
                showPreview: showPreview,
                showTabBar: showTabBar,
                sidebarCollapsed: win.width >= 820 ? sidebarCollapsed : false,
                iconScale: iconScale,
                lastPath: currentPath,
                lastTabs: tabSnapshots,
                activeTabIndex: activeTabIndex
            }
        });
    }

    onViewModeChanged: scheduleSaveConfig()
    onSortByChanged: scheduleSaveConfig()
    onSortAscChanged: scheduleSaveConfig()
    onShowHiddenChanged: scheduleSaveConfig()
    onShowPathBarChanged: scheduleSaveConfig()
    onShowStatusBarChanged: scheduleSaveConfig()
    onShowPreviewChanged: scheduleSaveConfig()
    onShowTabBarChanged: scheduleSaveConfig()
    onSidebarCollapsedChanged: scheduleSaveConfig()
    onIconScaleChanged: scheduleSaveConfig()
    onCurrentPathChanged: scheduleSaveConfig()
    onTabsChanged: { syncTabBarModel(); scheduleSaveConfig(); }
    onActiveTabIndexChanged: scheduleSaveConfig()

    readonly property string localDaemonScript: Qt.resolvedUrl("../scripts/finder_daemon.py").toString().replace(/^file:\/\//, "")
    readonly property string daemonScript: (localDaemonScript !== "" ? localDaemonScript : (root.home + "/.config/quickshell/shell27/scripts/finder_daemon.py"))

    Process {
        id: daemon
        running: true
        stdinEnabled: true
        command: ["python3", root.daemonScript]
        onStarted: {
            if (!root.isPickerMode) root.send({ op: "getConfig" });
            // Populate paste menus from a copy made in another Finder window.
            root.send({ op: "clipboardGet" });
            root.send({ op: "sidebar", dark: root.darkMode });
            root.refreshCurrent();
            if (!root.isPickerMode) startupDeferredTimer.restart();
        }
        stdout: SplitParser {
            onRead: line => {
                try { root.handleEvent(JSON.parse(line)); } catch (e) {}
            }
        }
    }

    Timer {
        id: startupDeferredTimer
        interval: 250
        onTriggered: {
            root.send({ op: "getDefaultFileManager" });
            if (!gsettingsProc.running) gsettingsProc.running = true;
        }
    }

    IpcHandler {
        target: "finder"
        function open(path: string): void {
            if (root.isPickerMode) return;
            if (win.visible && path && path !== "") {
                root.addTab(path);
                win.raise();
                win.requestActivate();
            } else {
                root.open(path);
            }
        }
        function toggle(): void {
            if (root.isPickerMode) return;
            if (win.visible) win.visible = false;
            else root.open("");
        }
    }

    onDarkModeChanged: {
        send({ op: "sidebar", dark: darkMode });
        refreshCurrent();
    }

    Window {
        id: win
        title: root.isPickerMode
               ? ((root.pickerTitle !== "" ? root.pickerTitle : (root.pickerMode === "save" ? "Save As" : root.pickerMode === "folder" ? "Choose Folder" : "Open")) + " — Finder [" + root.instanceId + "]")
               : ("Finder — " + root.folderLabel(root.currentPath) + " [" + root.instanceId + "]")
        width: root.isPickerMode ? 840 : 1060
        height: root.isPickerMode ? 540 : 680
        minimumWidth: root.isPickerMode ? 640 : 740
        minimumHeight: root.isPickerMode ? 400 : 460
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        property int floatTries: 0
        onVisibleChanged: if (visible) { floatTries = 0; floatTimer.restart(); }
        onWidthChanged: root.sidebarCollapsed = (width < 820)
        onClosing: close => {
            close.accepted = false;
            if (root.isPickerMode) root.cancelPicker();
            else win.visible = false;
        }

        Timer {
            id: floatTimer
            interval: 60
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                var sel = root.windowSelector();
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "20", ' + sel + ' })');
                if (win.floatTries >= 2) Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                if (++win.floatTries >= 4) stop();
            }
        }

        property bool pathBarEditing: false
        function startPathBarEdit() {
            if (!root.showPathBar) { goToDialog.open(); return; }
            pathBarEditing = true;
            pathBarField.text = root.currentPath;
            pathBarField.forceActiveFocus();
            pathBarField.selectAll();
        }
        readonly property bool textInputFocused: win.activeFocusItem !== null && win.activeFocusItem.cursorPosition !== undefined

        // Keyboard shortcuts (macOS Finder + standard Linux file manager)
        Shortcut { sequence: "Ctrl+W"; context: Qt.WindowShortcut; onActivated: root.closeTab(root.activeTabIndex) }
        Shortcut { sequence: "Ctrl+T"; context: Qt.WindowShortcut; onActivated: root.addTab(root.currentPath) }
        Shortcut { sequence: "Ctrl+N"; context: Qt.WindowShortcut; onActivated: Quickshell.execDetached(["qs", "-p", root.home + "/.config/quickshell/shell27/Finder.qml"]) }
        Shortcut { sequence: "Ctrl+Shift+N"; context: Qt.WindowShortcut; onActivated: root.send({ op: "mkdir", parent: root.currentPath, name: "untitled folder" }) }
        Shortcut { sequence: "Ctrl+1"; context: Qt.WindowShortcut; onActivated: root.setViewMode("icon") }
        Shortcut { sequence: "Ctrl+2"; context: Qt.WindowShortcut; onActivated: root.setViewMode("list") }
        Shortcut { sequence: "Ctrl+3"; context: Qt.WindowShortcut; onActivated: root.setViewMode("column") }
        Shortcut { sequence: "Ctrl+4"; context: Qt.WindowShortcut; onActivated: root.setViewMode("gallery") }
        Shortcut { sequence: "Ctrl+Shift+P"; context: Qt.WindowShortcut; onActivated: root.showPreview = !root.showPreview }
        Shortcut { sequence: "F3"; context: Qt.WindowShortcut; onActivated: root.showPreview = !root.showPreview }
        Shortcut { sequence: "Ctrl+H"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: { root.showHidden = !root.showHidden; root.refreshCurrent(); } }
        Shortcut { sequence: "Ctrl+Shift+H"; context: Qt.WindowShortcut; onActivated: { root.showHidden = !root.showHidden; root.refreshCurrent(); } }
        Shortcut { sequence: "Ctrl+."; context: Qt.WindowShortcut; onActivated: { root.showHidden = !root.showHidden; root.refreshCurrent(); } }
        Shortcut { sequence: "Ctrl+Shift+S"; context: Qt.WindowShortcut; onActivated: root.sidebarCollapsed = !root.sidebarCollapsed }
        Shortcut { sequence: "Ctrl+/"; context: Qt.WindowShortcut; onActivated: root.showStatusBar = !root.showStatusBar }
        Shortcut { sequence: "Ctrl+Shift+B"; context: Qt.WindowShortcut; onActivated: root.showPathBar = !root.showPathBar }
        Shortcut { sequence: "Ctrl+Shift+G"; context: Qt.WindowShortcut; onActivated: goToDialog.open() }
        Shortcut { sequence: "Ctrl+L"; context: Qt.WindowShortcut; onActivated: win.startPathBarEdit() }
        Shortcut { sequence: "Ctrl+I"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: if (root.primarySelectedItem()) root.getInfoOpen = !root.getInfoOpen }
        Shortcut { sequence: "Alt+I"; context: Qt.WindowShortcut; onActivated: if (root.primarySelectedItem()) root.getInfoOpen = !root.getInfoOpen }
        Shortcut { sequence: "Alt+Return"; context: Qt.WindowShortcut; onActivated: if (root.primarySelectedItem()) root.getInfoOpen = !root.getInfoOpen }
        Shortcut { sequence: "Ctrl+F"; context: Qt.WindowShortcut; onActivated: { root.searchExpanded = true; searchField.forceActiveFocus(); } }
        Shortcut { sequence: "Ctrl+A"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: root.selectAll() }
        Shortcut { sequence: "Ctrl+C"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: root.copySelection("copy") }
        Shortcut { sequence: "Ctrl+Shift+C"; context: Qt.WindowShortcut; onActivated: { var p = root.selectedPaths.length > 0 ? root.selectedPaths.join("\n") : root.currentPath; Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", p]); } }
        Shortcut { sequence: "Ctrl+X"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: root.copySelection("move") }
        Shortcut { sequence: "Ctrl+V"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: root.pasteInto(root.currentPath) }
        Shortcut { sequence: "Ctrl+D"; context: Qt.WindowShortcut; onActivated: if (root.primarySelectedItem()) root.send({ op: "duplicate", path: root.primarySelectedItem().path }) }
        Shortcut { sequence: "Ctrl+E"; context: Qt.WindowShortcut; onActivated: { var p = root.primarySelectedItem(); if (p && root.isArchiveName(p.name)) root.send({ op: "extract", path: p.path }); } }
        Shortcut { sequence: "Ctrl+K"; context: Qt.WindowShortcut; onActivated: if (root.selectedPaths.length > 0) root.openCompressFor(root.selectedPaths) }
        Shortcut { sequence: "F2"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: { if (root.selectedPaths.length > 1) { bulkRenameModal.open(); } else { var p = root.primarySelectedItem(); if (p) { root.renameTargetPath = p.path; root.renameTargetName = p.name; renameModal.open(); } } } }
        Shortcut { sequence: "Ctrl+Shift+R"; context: Qt.WindowShortcut; onActivated: if (root.selectedPaths.length > 1) bulkRenameModal.open() }
        Shortcut { sequence: "Ctrl+R"; context: Qt.WindowShortcut; onActivated: root.refreshCurrent() }
        Shortcut { sequence: "F5"; context: Qt.WindowShortcut; onActivated: root.refreshCurrent() }
        Shortcut { sequence: "Ctrl+O"; context: Qt.WindowShortcut; onActivated: if (root.primarySelectedItem()) root.activateItem(root.primarySelectedItem()) }
        Shortcut { sequence: "Ctrl+Down"; context: Qt.WindowShortcut; onActivated: if (root.primarySelectedItem()) root.activateItem(root.primarySelectedItem()) }
        Shortcut { sequence: "Ctrl+Backspace"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: if (root.selectedPaths.length > 0) root.send({ op: "trash", paths: root.selectedPaths }) }
        Shortcut { sequence: "Delete"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: if (root.selectedPaths.length > 0) root.send({ op: "trash", paths: root.selectedPaths }) }
        Shortcut { sequence: "Backspace"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: root.goBack() }
        Shortcut { sequence: "Ctrl+Up"; context: Qt.WindowShortcut; onActivated: root.goEnclosing() }
        Shortcut { sequence: "Alt+Up"; context: Qt.WindowShortcut; onActivated: root.goEnclosing() }
        Shortcut { sequence: "Alt+Home"; context: Qt.WindowShortcut; onActivated: root.navigateTo(root.home, true) }
        Shortcut { sequence: "Ctrl+Alt+T"; context: Qt.WindowShortcut; onActivated: Quickshell.execDetached(["sh", "-c", "cd \"$1\" && (kitty || ghostty || alacritty || foot)", "sh", root.currentPath]) }
        Shortcut { sequence: "Ctrl+="; context: Qt.WindowShortcut; onActivated: root.setIconScaleIndex(Math.min(2, root.iconScaleIndex() + 1)) }
        Shortcut { sequence: "Ctrl++"; context: Qt.WindowShortcut; onActivated: root.setIconScaleIndex(Math.min(2, root.iconScaleIndex() + 1)) }
        Shortcut { sequence: "Ctrl+-"; context: Qt.WindowShortcut; onActivated: root.setIconScaleIndex(Math.max(0, root.iconScaleIndex() - 1)) }
        Shortcut { sequence: "Ctrl+0"; context: Qt.WindowShortcut; onActivated: root.setIconScaleIndex(1) }
        Shortcut { sequence: "Ctrl+["; context: Qt.WindowShortcut; onActivated: root.goBack() }
        Shortcut { sequence: "Ctrl+]"; context: Qt.WindowShortcut; onActivated: root.goForward() }
        Shortcut { sequence: "Alt+Left"; context: Qt.WindowShortcut; onActivated: root.goBack() }
        Shortcut { sequence: "Alt+Right"; context: Qt.WindowShortcut; onActivated: root.goForward() }
        Shortcut { sequence: "Ctrl+Tab"; context: Qt.WindowShortcut; onActivated: if (root.tabs.length > 1) root.switchTab((root.activeTabIndex + 1) % root.tabs.length) }
        Shortcut { sequence: "Ctrl+Shift+Tab"; context: Qt.WindowShortcut; onActivated: if (root.tabs.length > 1) root.switchTab((root.activeTabIndex - 1 + root.tabs.length) % root.tabs.length) }
        Shortcut { sequence: "Home"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: if (root.items.length > 0) root.selectItem(root.items[0], 0) }
        Shortcut { sequence: "End"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: if (root.items.length > 0) root.selectItem(root.items[root.items.length - 1], 0) }
        Shortcut { sequence: "Space"; context: Qt.WindowShortcut; enabled: !win.textInputFocused; onActivated: if (root.primarySelectedItem()) root.quickLookOpen = !root.quickLookOpen }
        Shortcut { sequence: "Escape"; context: Qt.WindowShortcut; onActivated: { if (win.pathBarEditing) { win.pathBarEditing = false; } else if (bulkRenameModal.opacity > 0.5) bulkRenameModal.close(); else if (renameModal.opacity > 0.5) renameModal.close(); else if (newCategoryModal.opacity > 0.5) newCategoryModal.close(); else if (root.compressOpen) root.compressOpen = false; else if (root.archivePasswordOpen) root.archivePasswordOpen = false; else if (root.openWithOpen) root.openWithOpen = false; else if (root.quickLookOpen) root.quickLookOpen = false; else if (root.getInfoOpen) root.getInfoOpen = false; else if (root.searchExpanded) { root.searchText = ""; root.searchExpanded = false; root.refreshCurrent(); } else root.selectedPaths = []; } }

        // Main Window Shell
        Rectangle {
            id: windowFrame
            anchors.fill: parent
            radius: 20
            color: "transparent"
            border.width: 1.5
            border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.14)
            clip: true
            focus: true

            Keys.onPressed: event => {
                if (searchField.activeFocus) return;
                if (event.key === Qt.Key_Space) {
                    if (root.primarySelectedItem()) root.quickLookOpen = !root.quickLookOpen;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    var p = root.primarySelectedItem();
                    if (p) {
                        root.renameTargetPath = p.path;
                        root.renameTargetName = p.name;
                        renameModal.open();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    root.moveSelection(-1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.moveSelection(1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.moveSelection(0, -1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.moveSelection(0, 1);
                    event.accepted = true;
                }
            }

            // Native drops cross QML processes; custom folder dragging cannot.
            DropArea {
                anchors.fill: parent
                z: 985
                keys: ["text/uri-list"]
                onDropped: drop => {
                    // Keep precise folder/tab drops in this Finder window on
                    // the existing custom path.  Native handling is for a
                    // different Finder process, where that mouse tracking is
                    // unavailable.
                    if (root.itemDragging) return;
                    root.receiveDroppedUrls(drop.urls, root.currentPath);
                    drop.acceptProposedAction();
                }
            }

            // FLOATING DRAG PREVIEW (follows cursor with subtle velocity shake & wiggle)
            Item {
                id: dragGhostOverlay
                visible: root.itemDragging && root.dragLeadItem !== null
                x: root.dragGhostX - width / 2
                y: root.dragGhostY - height / 2 - 10
                width: 96; height: 96
                z: 990
                rotation: root.dragWiggleAngle
                scale: root.itemDragging ? 1.04 : 0.86
                Behavior on rotation { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                Rectangle {
                    anchors.centerIn: parent
                    width: 84; height: 84; radius: 14
                    color: root.darkMode ? Qt.rgba(0.16, 0.17, 0.20, 0.88) : Qt.rgba(0.96, 0.97, 0.99, 0.92)
                    border.width: 1.2
                    border.color: root.dropHoverTargetPath !== "" ? root.accentBlue : (root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16))
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Column {
                        anchors.centerIn: parent; width: 72; spacing: 4
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 44; height: 44
                            Image {
                                anchors.fill: parent
                                visible: root.dragLeadItem ? (root.dragLeadItem.thumb !== "" || root.dragLeadItem.icon !== "") : false
                                source: root.dragLeadItem ? (root.dragLeadItem.thumb ? "file://" + root.dragLeadItem.thumb : (root.dragLeadItem.icon ? "file://" + root.dragLeadItem.icon : "")) : ""
                                fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                            }
                            WGlyph {
                                anchors.centerIn: parent; width: 34; height: 34
                                visible: root.dragLeadItem ? (root.dragLeadItem.thumb === "" && root.dragLeadItem.icon === "") : false
                                kind: (root.dragLeadItem && root.dragLeadItem.isDir) ? "folder" : "doc"
                                color: (root.dragLeadItem && root.dragLeadItem.isDir) ? root.accentBlue : root.textMuted
                            }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: root.dragLeadItem ? root.dragLeadItem.displayName : ""
                            color: root.textPrimary
                            font.family: root.fam; font.pixelSize: 10; font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }
                    }

                    // Multi-item count badge
                    Rectangle {
                        visible: root.dragPaths.length > 1
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: -6; anchors.rightMargin: -6
                        width: Math.max(20, dragCountTxt.implicitWidth + 10); height: 20; radius: 10
                        color: root.accentBlue
                        border.width: 1.5; border.color: "white"
                        Text {
                            id: dragCountTxt
                            anchors.centerIn: parent
                            text: root.dragPaths.length.toString()
                            color: "white"; font.family: root.fam; font.pixelSize: 11; font.weight: Font.Bold
                        }
                    }
                }
            }

            // Edge resize handles
            MouseArea { x: 12; y: 0; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.TopEdge) }
            MouseArea { x: 12; y: parent.height - 6; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }
            MouseArea { x: 0; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.LeftEdge) }
            MouseArea { x: parent.width - 6; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 0; y: 0; width: 14; height: 14; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.TopEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 14; y: 0; width: 14; height: 14; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: win.startSystemResize(Qt.TopEdge | Qt.RightEdge) }
            MouseArea { x: 0; y: parent.height - 14; width: 14; height: 14; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 14; y: parent.height - 14; width: 14; height: 14; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // Flat translucent sidebar; the window rule supplies the compositor blur.
            Rectangle {
                id: sidebarCard
                x: 0; y: 0
                width: root.sidebarCollapsed ? 0 : 224
                height: parent.height
                radius: 0
                color: root.sidebarBg
                clip: true
                z: 20
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.lineCol }

                // Traffic Lights
                Item {
                    id: trafficLights
                    x: 14; y: 14; width: 58; height: 14
                    Row {
                        id: lightRow
                        spacing: 8
                        Repeater {
                            model: [{ c: "#FF5F57", g: "×" }, { c: "#FEBC2E", g: "−" }, { c: "#28C840", g: "↗" }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 13; height: 13; radius: 6.5
                                color: (win.active || lightHover.containsMouse) ? modelData.c : (root.darkMode ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.14))
                                border.width: 1
                                border.color: (win.active || lightHover.containsMouse) ? Qt.darker(modelData.c, 1.15) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    visible: lightHover.containsMouse
                                    text: parent.modelData.g
                                    color: Qt.rgba(0, 0, 0, 0.65)
                                    font.pixelSize: 9; font.weight: Font.Bold
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: lightHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mouse => {
                            var sel = root.windowSelector();
                            if (mouse.x < 20) win.visible = false;
                            else if (mouse.x < 40) Hyprland.dispatch('hl.dsp.window.movetoworkspacesilent({ workspace = "special:minimized", ' + sel + ' })');
                            else Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", ' + sel + ' })');
                        }
                    }
                }

                // Sidebar Scrollable Sections
                Flickable {
                    id: sidebarFlick
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 40
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    contentHeight: sidebarCol.implicitHeight + 16
                    interactive: !root.sidebarDragging
                    clip: true

                    Column {
                        id: sidebarCol
                        width: sidebarFlick.width - 24
                        x: 12
                        spacing: 11

                        // Dynamic Sidebar Categories (Favorites, Locations, iCloud, Custom Categories)
                        Repeater {
                            id: sidebarCatRepeater
                            model: root.sidebarCategories.length > 0 ? root.sidebarCategories : [
                                { id: "favorites", label: "Favorites", items: root.sidebarFavorites },
                                { id: "locations", label: "Locations", items: root.sidebarLocations },
                                { id: "cloud", label: "iCloud", items: root.sidebarIcloud }
                            ]
                            delegate: Column {
                                id: catCol
                                required property var modelData
                                required property int index
                                readonly property var cat: modelData
                                readonly property int catIdx: index
                                readonly property alias itemsRepeater: sidebarItemRepeater
                                width: sidebarCol.width
                                spacing: 2

                                Item {
                                    width: parent.width; height: 22
                                    Text {
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: catCol.cat.label || ""
                                        color: root.textMuted
                                        font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                        font.pixelSize: 11; font.weight: Font.DemiBold
                                    }
                                    // Add folder (+) button on hover
                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "+"
                                        color: root.textMuted
                                        font.pixelSize: 14
                                        opacity: catHeaderHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        TapHandler {
                                            onTapped: {
                                                root.send({
                                                    op: "addSidebarItem",
                                                    categoryId: catCol.cat.id,
                                                    label: root.folderLabel(root.currentPath),
                                                    path: root.currentPath,
                                                    glyph: "folder"
                                                });
                                            }
                                        }
                                    }
                                    HoverHandler { id: catHeaderHover }
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: {
                                            root.activeCategoryTarget = catCol.cat;
                                            categoryMenu.popup();
                                        }
                                    }
                                }

                                Column {
                                    id: catItemsCol
                                    width: sidebarCol.width
                                    spacing: 0

                                    Repeater {
                                        id: sidebarItemRepeater
                                        model: catCol.cat.items || []
                                        delegate: Item {
                                            id: sidebarDragDelegate
                                            required property var modelData
                                            required property int index
                                            readonly property int itemIdx: index
                                            readonly property string catId: catCol.cat.id
                                            readonly property bool isBeingDragged: root.sidebarDragging && root.sidebarDragCatId === catId && root.sidebarDragFromIdx === itemIdx
                                            width: sidebarCol.width
                                            height: 30

                                            // Clear drop indicator line above this item
                                            Rectangle {
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.top: parent.top; anchors.topMargin: -1
                                                height: 2; radius: 1
                                                color: root.accentBlue
                                                visible: root.sidebarDragging && root.sidebarDragCatId === sidebarDragDelegate.catId && root.sidebarDragToIdx === sidebarDragDelegate.itemIdx && root.sidebarDragFromIdx !== sidebarDragDelegate.itemIdx
                                                z: 10
                                                Rectangle {
                                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                                    width: 6; height: 6; radius: 3; color: root.accentBlue
                                                }
                                            }

                                            SidebarRow {
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                height: 28
                                                label: sidebarDragDelegate.modelData.label
                                                glyph: sidebarDragDelegate.modelData.glyph
                                                active: root.currentPath === sidebarDragDelegate.modelData.path
                                                dropTarget: root.itemDragging && root.dropHoverTargetPath === (sidebarDragDelegate.modelData.path || "")
                                                hovered: rowMa.containsMouse
                                                pressed: rowMa.pressed
                                                dark: root.darkMode
                                                fam: root.fam
                                                textCol: root.textPrimary
                                                scale: sidebarDragDelegate.isBeingDragged ? 1.03 : 1.0
                                                opacity: sidebarDragDelegate.isBeingDragged ? 0.85 : 1.0
                                                border.width: sidebarDragDelegate.isBeingDragged ? 1.5 : 0
                                                border.color: sidebarDragDelegate.isBeingDragged ? root.accentBlue : "transparent"
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            }

                                            // Clear drop indicator line below the last item
                                            Rectangle {
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.bottom: parent.bottom; anchors.bottomMargin: -1
                                                height: 2; radius: 1
                                                color: root.accentBlue
                                                visible: root.sidebarDragging && root.sidebarDragCatId === sidebarDragDelegate.catId && root.sidebarDragToIdx === sidebarDragDelegate.itemIdx + 1 && root.sidebarDragFromIdx !== sidebarDragDelegate.itemIdx + 1 && sidebarDragDelegate.itemIdx === ((catCol.cat.items || []).length - 1)
                                                z: 10
                                                Rectangle {
                                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                                    width: 6; height: 6; radius: 3; color: root.accentBlue
                                                }
                                            }

                                            // Unified click, right-click, hover, and press-and-hold drag handler
                                            MouseArea {
                                                id: rowMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                                pressAndHoldInterval: 250
                                                preventStealing: root.sidebarDragging
                                                cursorShape: root.sidebarDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                                property bool didDrag: false
                                                onPressed: mouse => {
                                                    didDrag = false;
                                                    if (mouse.button === Qt.RightButton) {
                                                        root.activeSidebarItem = sidebarDragDelegate.modelData;
                                                        root.activeSidebarCatId = sidebarDragDelegate.catId;
                                                        sidebarItemMenu.popup();
                                                    } else if (mouse.button === Qt.MiddleButton) {
                                                        root.addTab(sidebarDragDelegate.modelData.path);
                                                    }
                                                }
                                                onPressAndHold: mouse => {
                                                    if (mouse.button !== Qt.LeftButton) return;
                                                    didDrag = true;
                                                    root.sidebarDragCatId = sidebarDragDelegate.catId;
                                                    root.sidebarDragFromIdx = sidebarDragDelegate.itemIdx;
                                                    root.sidebarDragToIdx = sidebarDragDelegate.itemIdx;
                                                    root.sidebarDragging = true;
                                                }
                                                onPositionChanged: mouse => {
                                                    if (!root.sidebarDragging || root.sidebarDragCatId !== sidebarDragDelegate.catId) return;
                                                    var localY = mapToItem(catItemsCol, mouse.x, mouse.y).y;
                                                    var catItems = catCol.cat.items || [];
                                                    var target = Math.max(0, Math.min(catItems.length, Math.round(localY / 30)));
                                                    root.sidebarDragToIdx = target;
                                                }
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.LeftButton && !didDrag) {
                                                        root.navigateTo(sidebarDragDelegate.modelData.path, true);
                                                    }
                                                }
                                                onReleased: {
                                                    if (root.sidebarDragging && root.sidebarDragFromIdx >= 0 && root.sidebarDragToIdx >= 0 && root.sidebarDragFromIdx !== root.sidebarDragToIdx && root.sidebarDragToIdx !== root.sidebarDragFromIdx + 1) {
                                                        root.send({
                                                            op: "reorderSidebarItem",
                                                            categoryId: root.sidebarDragCatId,
                                                            fromIndex: root.sidebarDragFromIdx,
                                                            toIndex: root.sidebarDragToIdx
                                                        });
                                                    }
                                                    root.sidebarDragging = false;
                                                    root.sidebarDragFromIdx = -1;
                                                    root.sidebarDragToIdx = -1;
                                                    root.sidebarDragCatId = "";
                                                }
                                                onCanceled: {
                                                    didDrag = false;
                                                    root.sidebarDragging = false;
                                                    root.sidebarDragFromIdx = -1;
                                                    root.sidebarDragToIdx = -1;
                                                    root.sidebarDragCatId = "";
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Tags Section
                        Column {
                            width: parent.width; spacing: 2
                            Text {
                                leftPadding: 10; bottomPadding: 3
                                text: "Tags"
                                color: root.textMuted
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                            Repeater {
                                model: root.sidebarTags
                                delegate: Rectangle {
                                    required property var modelData
                                    width: sidebarCol.width; height: 28; radius: 8
                                    readonly property bool active: root.currentPath === ("finder://tag/" + modelData.name)
                                    color: active ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09))
                                                  : (tagRowHover.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Row {
                                        anchors.fill: parent; anchors.leftMargin: 12; spacing: 10
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 10; height: 10; radius: 5
                                            color: modelData.color
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name
                                            color: root.textPrimary
                                            font.family: root.fam; font.pixelSize: 13
                                        }
                                    }
                                    HoverHandler { id: tagRowHover }
                                    TapHandler { onTapped: root.navigateTo("finder://tag/" + modelData.name, true) }
                                }
                            }
                            Rectangle {
                                width: sidebarCol.width; height: 28; radius: 8
                                readonly property bool active: root.currentPath === "finder://tag/All"
                                color: active ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09))
                                              : (allTagsHover.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 10; spacing: 9
                                    WGlyph { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; kind: "tagAll"; color: root.textMuted }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "All Tags..."
                                        color: root.textPrimary
                                        font.family: root.fam; font.pixelSize: 13
                                    }
                                }
                                HoverHandler { id: allTagsHover }
                                TapHandler { onTapped: root.navigateTo("finder://tag/All", true) }
                            }
                        }
                    }
                    LiquidScrollBar { flick: sidebarFlick; material: "liquid"; dark: root.darkMode; compact: true }
                }
            }

            // 2. RIGHT MAIN PANE
            Item {
                id: mainPane
                anchors.left: sidebarCard.right
                anchors.leftMargin: 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Rectangle { anchors.fill: parent; color: root.windowBg; z: -1 }

                // Window drag region across empty toolbar space
                MouseArea {
                    x: 0; y: 0; width: parent.width; height: 56; z: 1
                    acceptedButtons: Qt.LeftButton
                    onPressed: win.startSystemMove()
                }

                // FLOATING LIQUID GLASS TOOLBAR
                Item {
                    id: toolbar
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    height: 54
                    z: 25

                    // Subtle top fade so scrolled items melt smoothly under pills
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: root.windowBg }
                            GradientStop { position: 0.75; color: Qt.rgba(root.windowBg.r, root.windowBg.g, root.windowBg.b, 0.85) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Left: Sidebar Toggle + < | > Nav Capsule (matching Settings app) + Folder Title
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10; z: 2

                        // Sidebar Toggle Button (like macOS Finder)
                        Item {
                            width: 34; height: 34
                            anchors.verticalCenter: parent.verticalCenter
                            scale: sbTogMa.pressed ? 0.90 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                            Rectangle {
                                anchors.fill: parent; radius: 17
                                color: sbTogHover.hovered ? root.pillHoverBg : root.pillBg
                                border.width: 1; border.color: root.lineCol
                                GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.glassShaderUrl; dark: root.darkMode; baseColor: root.pillBase; cornerR: 17; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: root.darkMode ? 0.48 : 0.72; flatInner: 1 }

                                Canvas {
                                    anchors.centerIn: parent; width: 15; height: 13
                                    property color ink: root.textPrimary
                                    onInkChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                        ctx.strokeStyle = ink; ctx.lineWidth = 1.25;
                                        ctx.lineCap = "round"; ctx.lineJoin = "round";
                                        ctx.beginPath(); ctx.roundedRect(1, 1, 13, 11, 2.2, 2.2); ctx.stroke();
                                        ctx.beginPath(); ctx.moveTo(5.2, 1.5); ctx.lineTo(5.2, 11.5); ctx.stroke();
                                    }
                                }
                            }
                            HoverHandler { id: sbTogHover }
                            MacToolTip { visible: sbTogHover.hovered; text: root.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar" }
                            MouseArea {
                                id: sbTogMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sidebarCollapsed = !root.sidebarCollapsed
                            }
                        }

                        Item {
                            width: 66; height: 34
                            anchors.verticalCenter: parent.verticalCenter

                            GlassSlab {
                                id: navPill
                                anchors.fill: parent
                                cornerR: 17
                                glass: true
                                shaderUrl: root.glassShaderUrl
                                dark: root.darkMode
                                baseColor: root.darkMode ? "#3C3C40" : "#E6E8EE"
                                blurPx: 6
                                thickness: 14
                                strengthMul: 0.6
                                rim: 0.15
                                grain: 0.02
                                tint: root.darkMode ? 0.42 : 0.72
                                flatInner: 1

                                CornerBorder {
                                    z: 2; anchors.fill: parent
                                    cornerR: 17; dark: root.darkMode
                                    tint: root.bar ? root.bar.menuBorderColor : (root.darkMode ? "#8A9AB5" : "#7A8294")
                                    amount: 1; lineW: root.darkMode ? 0.8 : 1.0
                                }
                            }

                            Row {
                                anchors.fill: parent
                                spacing: 0
                                Repeater {
                                    model: [ { g: "\u2039", dir: -1 }, { g: "\u203A", dir: 1 } ]
                                    delegate: Item {
                                        id: navBtn
                                        required property var modelData
                                        readonly property bool ok: modelData.dir < 0 ? root.canGoBack() : root.canGoForward()
                                        width: 33; height: 34
                                        Text {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: -2
                                            text: navBtn.modelData.g
                                            font.family: Fonts.forWeight(Font.Normal, root.fam)
                                            font.pixelSize: 26
                                            color: navBtn.ok ? root.textPrimary : root.textMuted
                                            opacity: navBtn.ok ? 1 : 0.35
                                            scale: (navBtn.ok && navMa.pressed) ? 0.86 : 1
                                            Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                                        }
                                        MouseArea {
                                            id: navMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: navBtn.ok
                                            cursorShape: navBtn.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (navBtn.modelData.dir < 0) root.goBack();
                                                else root.goForward();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            WGlyph { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; kind: "folder"; color: root.accentBlue }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.folderLabel(root.currentPath)
                                color: root.textPrimary
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Right: View Mode Segmented Pill | Sort Pill | Share/Tag/More Pill | Search Pill
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8; z: 2

                        // 1. Segmented View Switcher Pill
                        Rectangle {
                            width: 146; height: 34; radius: 17
                            color: root.pillBg
                            border.width: 1; border.color: root.lineCol
                            GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.glassShaderUrl; dark: root.darkMode; baseColor: root.pillBase; cornerR: 17; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: root.darkMode ? 0.48 : 0.72; flatInner: 1 }

                            // Animated sliding indicator
                            Rectangle {
                                readonly property int actIdx: root.viewMode === "icon" ? 0 : root.viewMode === "list" ? 1 : root.viewMode === "column" ? 2 : 3
                                x: 3 + actIdx * 35; y: 3
                                width: 34; height: 28; radius: 14
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.09)
                                border.width: 0.8; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.20)
                                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }

                            Row {
                                anchors.fill: parent; anchors.margins: 3; spacing: 1
                                Repeater {
                                    model: [
                                        { id: "icon", tip: "Icon View (⌘1)" },
                                        { id: "list", tip: "List View (⌘2)" },
                                        { id: "column", tip: "Column View (⌘3)" },
                                        { id: "gallery", tip: "Gallery View (⌘4)" }
                                    ]
                                    delegate: Item {
                                        id: modeBtn
                                        required property var modelData
                                        required property int index
                                        readonly property bool active: root.viewMode === modelData.id
                                        width: 34; height: 28
                                        scale: modeMa.pressed ? 0.90 : 1
                                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }

                                        Canvas {
                                            anchors.centerIn: parent; width: 14; height: 14
                                            property string modeId: modelData.id
                                            property color ink: root.textPrimary
                                            onInkChanged: requestPaint()
                                            onPaint: {
                                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                                ctx.strokeStyle = ink; ctx.fillStyle = ink; ctx.lineWidth = 1.25;
                                                ctx.lineCap = "round"; ctx.lineJoin = "round";
                                                if (modeId === "icon") {
                                                    // 2x2 rounded grid
                                                    ctx.beginPath(); ctx.roundedRect(1.5, 1.5, 4.5, 4.5, 1.2, 1.2); ctx.stroke();
                                                    ctx.beginPath(); ctx.roundedRect(8, 1.5, 4.5, 4.5, 1.2, 1.2); ctx.stroke();
                                                    ctx.beginPath(); ctx.roundedRect(1.5, 8, 4.5, 4.5, 1.2, 1.2); ctx.stroke();
                                                    ctx.beginPath(); ctx.roundedRect(8, 8, 4.5, 4.5, 1.2, 1.2); ctx.stroke();
                                                } else if (modeId === "list") {
                                                    for (var i = 0; i < 3; i++) {
                                                        var y = 2.5 + i * 4.2;
                                                        ctx.beginPath(); ctx.roundedRect(1.5, y, 2, 1.5, 0.6, 0.6); ctx.fill();
                                                        ctx.beginPath(); ctx.roundedRect(5, y, 7.5, 1.5, 0.6, 0.6); ctx.fill();
                                                    }
                                                } else if (modeId === "column") {
                                                    ctx.beginPath(); ctx.roundedRect(1.5, 2, 11, 10, 1.4, 1.4); ctx.stroke();
                                                    ctx.beginPath(); ctx.moveTo(5, 2.8); ctx.lineTo(5, 11.2); ctx.stroke();
                                                    ctx.beginPath(); ctx.moveTo(8.5, 2.8); ctx.lineTo(8.5, 11.2); ctx.stroke();
                                                } else {
                                                    // Gallery: Widescreen landscape frame + 3 mini filmstrip cards
                                                    ctx.beginPath(); ctx.roundedRect(1.5, 2.0, 11, 6.0, 1.4, 1.4); ctx.stroke();
                                                    ctx.beginPath(); ctx.roundedRect(1.5, 10.5, 3.0, 1.8, 0.5, 0.5); ctx.fill();
                                                    ctx.beginPath(); ctx.roundedRect(5.5, 10.5, 3.0, 1.8, 0.5, 0.5); ctx.fill();
                                                    ctx.beginPath(); ctx.roundedRect(9.5, 10.5, 3.0, 1.8, 0.5, 0.5); ctx.fill();
                                                }
                                            }
                                        }

                                        // Vertical separation line on the right of segment (unless active or next active)
                                        Rectangle {
                                            anchors.right: parent.right; anchors.rightMargin: -1
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 1; height: 16
                                            visible: modeBtn.index < 3 && !modeBtn.active && root.viewMode !== ["icon", "list", "column", "gallery"][modeBtn.index + 1]
                                            color: root.lineCol
                                        }

                                        HoverHandler { id: vh }
                                        MacToolTip { visible: vh.hovered; text: modelData.tip }
                                        MouseArea {
                                            id: modeMa
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setViewMode(modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Sort / View Options Pill
                        Item {
                            width: 48; height: 34
                            scale: sortMa.pressed ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                            Rectangle {
                                anchors.fill: parent; radius: 17
                                color: sortBtnHover.hovered ? root.pillHoverBg : root.pillBg
                                border.width: 1; border.color: root.lineCol
                                GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.glassShaderUrl; dark: root.darkMode; baseColor: root.pillBase; cornerR: 17; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: root.darkMode ? 0.48 : 0.72; flatInner: 1 }

                                Row {
                                    anchors.centerIn: parent; spacing: 4
                                    WGlyph { anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; kind: "layers"; color: root.textPrimary }
                                    Canvas {
                                        anchors.verticalCenter: parent.verticalCenter; width: 8; height: 6
                                        property color ink: root.textMuted
                                        onInkChanged: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                            ctx.strokeStyle = ink; ctx.lineWidth = 1.3;
                                            ctx.lineCap = "round"; ctx.lineJoin = "round";
                                            ctx.beginPath(); ctx.moveTo(1.5, 1.5); ctx.lineTo(4, 4.3); ctx.lineTo(6.5, 1.5); ctx.stroke();
                                        }
                                    }
                                }
                            }
                            HoverHandler { id: sortBtnHover }
                            MacToolTip { visible: sortBtnHover.hovered; text: "Sort & View Options" }
                            MouseArea {
                                id: sortMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sortMenu.popup()
                            }
                            FinderMenu {
                                id: sortMenu
                                menuWidth: 210
                                FinderMenuItem { text: (root.sortBy === "name" ? "✓ " : "    ") + "Sort by Name"; dark: root.darkMode; fam: root.fam; onTriggered: root.setSort("name") }
                                FinderMenuItem { text: (root.sortBy === "date" ? "✓ " : "    ") + "Sort by Date Modified"; dark: root.darkMode; fam: root.fam; onTriggered: root.setSort("date") }
                                FinderMenuItem { text: (root.sortBy === "size" ? "✓ " : "    ") + "Sort by Size"; dark: root.darkMode; fam: root.fam; onTriggered: root.setSort("size") }
                                FinderMenuItem { text: (root.sortBy === "kind" ? "✓ " : "    ") + "Sort by Kind"; dark: root.darkMode; fam: root.fam; onTriggered: root.setSort("kind") }
                                FinderMenuItem { text: (root.sortBy === "tag" ? "✓ " : "    ") + "Sort by Tag"; dark: root.darkMode; fam: root.fam; onTriggered: root.setSort("tag") }
                                MenuSeparator {}
                                FinderMenuItem { text: (root.showHidden ? "✓ " : "    ") + "Show Hidden Files"; dark: root.darkMode; fam: root.fam; onTriggered: { root.showHidden = !root.showHidden; root.refreshCurrent(); } }
                                FinderMenuItem { text: (root.showTabBar ? "✓ " : "    ") + "Show Tab Bar"; dark: root.darkMode; fam: root.fam; onTriggered: root.showTabBar = !root.showTabBar }
                                FinderMenuItem { text: (root.showPathBar ? "✓ " : "    ") + "Show Path Bar"; dark: root.darkMode; fam: root.fam; onTriggered: root.showPathBar = !root.showPathBar }
                                FinderMenuItem { text: (root.showStatusBar ? "✓ " : "    ") + "Show Status Bar"; dark: root.darkMode; fam: root.fam; onTriggered: root.showStatusBar = !root.showStatusBar }
                                FinderMenuItem { text: (root.showPreview ? "✓ " : "    ") + "Show Preview"; dark: root.darkMode; fam: root.fam; onTriggered: root.showPreview = !root.showPreview }
                            }
                        }

                        // 3. Actions Pill: Share | Tag | More (...)
                        Rectangle {
                            width: 106; height: 34; radius: 17
                            color: root.pillBg
                            border.width: 1; border.color: root.lineCol
                            GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.glassShaderUrl; dark: root.darkMode; baseColor: root.pillBase; cornerR: 17; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: root.darkMode ? 0.48 : 0.72; flatInner: 1 }
                            Row {
                                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                                // Copy Path / Share
                                Item {
                                    width: 31; height: 34
                                    scale: shareMa.pressed ? 0.88 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                    Rectangle {
                                        anchors.centerIn: parent; width: 26; height: 26; radius: 13
                                        color: shareH.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                                    }
                                    WGlyph { anchors.centerIn: parent; width: 13; height: 13; kind: "link"; color: root.textPrimary }
                                    HoverHandler { id: shareH }
                                    MacToolTip { visible: shareH.hovered; text: "Copy Path" }
                                    MouseArea {
                                        id: shareMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var p = root.selectedPaths.length > 0 ? root.selectedPaths.join("\n") : root.currentPath;
                                            Quickshell.execDetached(["wl-copy", p]);
                                        }
                                    }
                                }
                                // Tag menu
                                Item {
                                    width: 31; height: 34
                                    scale: tagMa.pressed ? 0.88 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                    Rectangle {
                                        anchors.centerIn: parent; width: 26; height: 26; radius: 13
                                        color: tagH.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                                    }
                                    Canvas {
                                        anchors.centerIn: parent; width: 14; height: 14
                                        property color ink: root.textPrimary
                                        onInkChanged: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                            ctx.strokeStyle = ink; ctx.lineWidth = 1.25;
                                            ctx.lineCap = "round"; ctx.lineJoin = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(3.0, 6.0);
                                            ctx.lineTo(6.2, 2.8);
                                            ctx.arcTo(7.0, 2.0, 8.2, 2.0, 1.2);
                                            ctx.lineTo(10.6, 2.0);
                                            ctx.arcTo(12.0, 2.0, 12.0, 3.4, 1.4);
                                            ctx.lineTo(12.0, 5.8);
                                            ctx.arcTo(12.0, 7.0, 11.2, 7.8, 1.2);
                                            ctx.lineTo(8.0, 11.0);
                                            ctx.arcTo(7.0, 12.0, 6.0, 11.0, 1.3);
                                            ctx.lineTo(3.0, 8.0);
                                            ctx.arcTo(2.0, 7.0, 3.0, 6.0, 1.3);
                                            ctx.closePath();
                                            ctx.stroke();
                                            ctx.beginPath(); ctx.arc(9.4, 4.6, 1.05, 0, Math.PI * 2); ctx.stroke();
                                        }
                                    }
                                    HoverHandler { id: tagH }
                                    MacToolTip { visible: tagH.hovered; text: "Edit Tags" }
                                    MouseArea {
                                        id: tagMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tagPopoverMenu.popup()
                                    }
                                    FinderMenu {
                                        id: tagPopoverMenu
                                        menuWidth: 190
                                        Repeater {
                                            model: root.sidebarTags
                                            delegate: FinderMenuItem {
                                                required property var modelData
                                                text: "●  " + modelData.name
                                                dark: root.darkMode; fam: root.fam
                                                accentDot: modelData.color
                                                onTriggered: if (root.selectedPaths.length > 0) root.send({ op: "setTag", paths: root.selectedPaths, tag: modelData.name, toggle: true })
                                            }
                                        }
                                    }
                                }
                                // More (...)
                                Item {
                                    width: 31; height: 34
                                    scale: moreMa.pressed ? 0.88 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                    Rectangle {
                                        anchors.centerIn: parent; width: 26; height: 26; radius: 13
                                        color: moreH.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                                    }
                                    WGlyph { anchors.centerIn: parent; width: 14; height: 14; kind: "dots"; color: root.textPrimary }
                                    HoverHandler { id: moreH }
                                    MacToolTip { visible: moreH.hovered; text: "Actions" }
                                    MouseArea {
                                        id: moreMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: moreToolbarMenu.popup()
                                    }
                                    FinderMenu {
                                        id: moreToolbarMenu
                                        menuWidth: 210
                                        FinderMenuItem { text: "New Folder"; dark: root.darkMode; fam: root.fam; onTriggered: root.send({ op: "mkdir", parent: root.currentPath, name: "untitled folder" }) }
                                        FinderMenuItem { text: "New Tab"; dark: root.darkMode; fam: root.fam; onTriggered: root.addTab(root.currentPath) }
                                        FinderMenuItem { text: "Go to Folder…"; dark: root.darkMode; fam: root.fam; onTriggered: goToDialog.open() }
                                        MenuSeparator {}
                                        FinderMenuItem { text: "Quick Look"; dark: root.darkMode; fam: root.fam; onTriggered: if (root.primarySelectedItem()) root.quickLookOpen = true }
                                        FinderMenuItem { text: "Get Info"; dark: root.darkMode; fam: root.fam; onTriggered: if (root.primarySelectedItem()) root.getInfoOpen = true }
                                        FinderMenuItem {
                                            visible: root.selectedPaths.length > 0
                                            text: root.selectedPaths.length > 1 ? ("Compress " + root.selectedPaths.length + " Items…") : "Compress…"
                                            dark: root.darkMode; fam: root.fam
                                            onTriggered: if (root.selectedPaths.length > 0) root.openCompressFor(root.selectedPaths)
                                        }
                                        FinderMenuItem { text: "Open in Terminal"; dark: root.darkMode; fam: root.fam; onTriggered: Quickshell.execDetached(["sh", "-c", "cd \"$1\" && (kitty || ghostty || alacritty || foot)", "sh", root.currentPath]) }
                                        MenuSeparator {}
                                        FinderMenuItem {
                                            text: root.isDefaultFileManager ? "✓ Default File Manager" : "Set as Default File Manager"
                                            dark: root.darkMode; fam: root.fam
                                            onTriggered: root.send({ op: "setDefaultFileManager" })
                                        }
                                    }
                                }
                            }
                        }

                        // 4. Expanding Search Pill
                        Rectangle {
                            id: searchPill
                            width: root.searchExpanded ? 210 : 34
                            height: 34; radius: 17
                            color: root.darkMode ? (root.searchExpanded ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.08))
                                                 : (root.searchExpanded ? Qt.rgba(0, 0, 0, 0.08) : root.pillBg)
                            border.width: root.searchExpanded ? 1.5 : 1
                            border.color: root.searchExpanded ? root.accentBlue : root.lineCol
                            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                            GlassSlab { anchors.fill: parent; glass: true; shaderUrl: root.glassShaderUrl; dark: root.darkMode; baseColor: root.pillBase; cornerR: 17; thickness: 5; strengthMul: 0.22; rim: 0.13; tint: root.darkMode ? 0.48 : 0.72; flatInner: 1 }

                            WGlyph {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                width: 13; height: 13; kind: "search"
                                color: root.searchExpanded ? root.accentBlue : root.textPrimary
                                Behavior on color { ColorAnimation { duration: 180 } }
                                TapHandler {
                                    onTapped: {
                                        root.searchExpanded = !root.searchExpanded;
                                        if (root.searchExpanded) searchField.forceActiveFocus();
                                        else { root.searchText = ""; searchField.text = ""; root.refreshCurrent(); }
                                    }
                                }
                            }
                            TextField {
                                id: searchField
                                visible: root.searchExpanded
                                anchors.left: parent.left; anchors.leftMargin: 28
                                anchors.right: searchClearBtn.visible ? searchClearBtn.left : parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                placeholderText: "Search " + root.folderLabel(root.currentPath)
                                color: root.textPrimary; placeholderTextColor: root.textMuted
                                font.family: root.fam; font.pixelSize: 12
                                background: Item {}
                                onTextChanged: { root.searchText = text; searchDebounce.restart(); }
                            }
                            Rectangle {
                                id: searchClearBtn
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 8
                                visible: root.searchExpanded && root.searchText !== ""
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.25)
                                Text { anchors.centerIn: parent; text: "×"; color: root.darkMode ? "white" : "#1D1D1F"; font.pixelSize: 12; font.weight: Font.Bold }
                                TapHandler {
                                    onTapped: {
                                        root.searchText = "";
                                        searchField.text = "";
                                        root.refreshCurrent();
                                    }
                                }
                            }
                            Timer { id: searchDebounce; interval: 180; onTriggered: root.refreshCurrent() }
                        }
                    }
                }

                // TAB BAR (Liquid Glass matching macOS Finder)
                Item {
                    id: tabBar
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: toolbar.bottom
                    height: root.showTabBar || root.tabs.length > 1 ? 36 : 0
                    visible: height > 0
                    clip: true
                    opacity: height > 4 ? 1.0 : 0.0
                    z: 20
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Row {
                        id: tabRow
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.right: addTabBtn.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            id: tabRowRepeater
                            model: tabBarModel
                            delegate: Item {
                                id: tabItem
                                required property string title
                                required property int index
                                readonly property bool isAct: index === root.activeTabIndex
                                readonly property bool isClosing: index === root.closingTabIndex
                                width: Math.max(80, (tabRow.width - Math.max(0, root.tabs.length - 1) * tabRow.spacing) / Math.max(1, root.tabs.length))
                                height: 28
                                property real enterProgress: 0
                                Component.onCompleted: enterProgress = 1
                                opacity: isClosing ? 0.0 : enterProgress
                                scale: isClosing ? 0.88 : (tabMa.pressed ? 0.96 : (0.90 + 0.10 * enterProgress))
                                Behavior on enterProgress { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }

                                Rectangle {
                                    anchors.fill: parent; radius: 14
                                    color: tabItem.isAct ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                                         : (tabH.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : "transparent")
                                    border.width: 1
                                    border.color: tabItem.isAct ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.20)) : root.lineCol
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Behavior on border.color { ColorAnimation { duration: 140 } }

                                    GlassSlab {
                                        anchors.fill: parent
                                        visible: tabItem.isAct
                                        glass: true
                                        shaderUrl: root.glassShaderUrl
                                        dark: root.darkMode
                                        baseColor: root.pillBase
                                        cornerR: 14
                                        thickness: 6
                                        strengthMul: 0.28
                                        rim: 0.18
                                        tint: 0.52
                                        flatInner: 1
                                    }

                                    Row {
                                        anchors.centerIn: parent; spacing: 6
                                        WGlyph {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 13; height: 13; kind: "folder"
                                            color: tabItem.isAct ? root.accentBlue : root.textMuted
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(tabItem.width - 48, implicitWidth)
                                            elide: Text.ElideMiddle
                                            text: tabItem.title
                                            color: tabItem.isAct ? root.textPrimary : root.textMuted
                                            font.family: Fonts.forWeight(tabItem.isAct ? Font.DemiBold : Font.Normal, root.fam)
                                            font.pixelSize: 12
                                            font.weight: tabItem.isAct ? Font.DemiBold : Font.Normal
                                        }
                                    }

                                    // Tab click & middle-click close
                                    MouseArea {
                                        id: tabMa
                                        anchors.fill: parent
                                        z: 1
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.MiddleButton) root.closeTab(tabItem.index);
                                            else root.switchTab(tabItem.index);
                                        }
                                    }

                                    // Close button (above tabMa so clicks always register!)
                                    Rectangle {
                                        id: tabCloseBtn
                                        anchors.left: parent.left; anchors.leftMargin: 7
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 17; height: 17; radius: 8.5
                                        z: 5
                                        visible: tabH.hovered || tabItem.isAct || tabCloseMa.containsMouse
                                        color: tabCloseMa.containsMouse ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text { anchors.centerIn: parent; text: "×"; color: tabCloseMa.containsMouse ? root.textPrimary : root.textMuted; font.pixelSize: 12; font.weight: Font.Bold }
                                        MouseArea {
                                            id: tabCloseMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeTab(tabItem.index)
                                        }
                                    }
                                }

                                HoverHandler { id: tabH }
                            }
                        }
                    }

                    // Add Tab Button
                    Rectangle {
                        id: addTabBtn
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 14
                        color: addTabHover.hovered ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                                                   : (root.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06))
                        border.width: 1; border.color: root.lineCol
                        scale: addTabMa.pressed ? 0.90 : 1
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                        GlassSlab {
                            anchors.fill: parent; glass: true
                            shaderUrl: root.glassShaderUrl
                            dark: root.darkMode; baseColor: root.pillBase; cornerR: 14
                            thickness: 4; strengthMul: 0.18; rim: 0.12; tint: 0.38; flatInner: 1
                        }

                        Text { anchors.centerIn: parent; text: "+"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 15 }
                        HoverHandler { id: addTabHover }
                        MouseArea {
                            id: addTabMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addTab(root.currentPath)
                        }
                    }
                }

                // TRASH ACTION BANNER (only visible in Trash)
                Rectangle {
                    id: trashBanner
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: tabBar.bottom
                    height: root.currentPath === "finder://trash" ? 40 : 0
                    visible: height > 0
                    clip: true
                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.025)
                    z: 19
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineCol }

                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.items.length > 0 ? ("Trash — " + root.items.length + (root.items.length === 1 ? " item" : " items")) : "Trash is empty"
                        color: root.textMuted
                        font.family: root.fam; font.pixelSize: 12
                    }

                    Rectangle {
                        id: emptyTrashBtn
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72; height: 26; radius: 13
                        opacity: root.items.length > 0 ? 1.0 : 0.4
                        scale: emptyTrashMa.pressed && root.items.length > 0 ? 0.92 : 1.0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                        color: emptyTrashHover.hovered && root.items.length > 0
                               ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                               : (root.darkMode ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06))
                        border.width: 1; border.color: root.lineCol
                        Text {
                            anchors.centerIn: parent
                            text: "Empty"
                            color: root.textPrimary
                            font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                            font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        HoverHandler { id: emptyTrashHover }
                        MouseArea {
                            id: emptyTrashMa
                            anchors.fill: parent
                            enabled: root.items.length > 0
                            cursorShape: root.items.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.send({ op: "emptyTrash" })
                        }
                    }
                }

                // CONTENT STAGE + OPTIONAL RIGHT INSPECTOR
                Item {
                    id: contentStage
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: trashBanner.bottom
                    anchors.bottom: bottomChrome.top

                    // Right Preview Inspector (when toggled OR in Column View final preview)
                    Rectangle {
                        id: previewPane
                        visible: root.showPreview && root.viewMode !== "gallery"
                        width: visible ? 250 : 0
                        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(0, 0, 0, 0.02)
                        Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: root.lineCol }

                        PreviewInspector {
                            anchors.fill: parent
                            items: root.selectedItemsList()
                            previewText: root.previewTextContent
                            dark: root.darkMode
                            fam: root.fam
                            textPrimary: root.textPrimary
                            textMuted: root.textMuted
                            lineCol: root.lineCol
                            onTagClicked: tag => root.navigateTo("finder://tag/" + tag, true)
                            onCopyPath: p => Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", p])
                        }
                    }

                    // Main View Area
                    Item {
                        id: viewHost
                        anchors.left: parent.left
                        anchors.right: previewPane.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom

                        // Background right-click for non-icon views (icon view uses rubberband area)
                        MouseArea {
                            anchors.fill: parent
                            z: 1
                            visible: root.viewMode !== "icon"
                            acceptedButtons: Qt.RightButton
                            onClicked: { root.contextItem = null; bgMenu.popup(); }
                        }

                        // Empty / Search Empty / AirDrop state
                        Column {
                            anchors.centerIn: parent; spacing: 12; z: 5
                            visible: root.items.length === 0

                            // Search No Results (macOS style)
                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: root.searchText !== ""
                                spacing: 10

                                WGlyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 48; height: 48
                                    kind: "search"
                                    color: root.textMuted
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No Results for “" + root.searchText + "”"
                                    color: root.textPrimary
                                    font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                    font.pixelSize: 15; font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Check the spelling or try a new search."
                                    color: root.textMuted
                                    font.family: root.fam; font.pixelSize: 12
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 104; height: 26; radius: 13
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                                    border.width: 1; border.color: root.lineCol
                                    Text { anchors.centerIn: parent; text: "Clear Search"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 11 }
                                    TapHandler {
                                        onTapped: {
                                            root.searchText = "";
                                            searchField.text = "";
                                            root.refreshCurrent();
                                        }
                                    }
                                }
                            }

                            // Empty folder / AirDrop
                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: root.searchText === ""
                                spacing: 8
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: root.currentPath === "finder://airdrop"
                                    width: 42; height: 42
                                    source: Qt.resolvedUrl("../assets/airdrop-symbolic.svg")
                                    sourceSize: Qt.size(84, 84)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect { colorization: 1; colorizationColor: root.textMuted }
                                }
                                WGlyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 42; height: 42
                                    visible: root.currentPath !== "finder://airdrop"
                                    kind: "folder"
                                    color: root.textMuted
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.currentPath === "finder://airdrop" ? "AirDrop — Ready to Share" : "This folder is empty"
                                    color: root.textMuted; font.family: root.fam; font.pixelSize: 14
                                }
                            }
                        }

                        // Background rubberband selection area (only active in icon view)
                        MouseArea {
                            id: rubberBandArea
                            anchors.fill: parent
                            z: 2
                            visible: root.viewMode === "icon"
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true
                            onPressed: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    root.contextItem = null;
                                    bgMenu.popup();
                                } else {
                                    root.selectedPaths = [];
                                    root.rubberBandStart = Qt.point(mouse.x, mouse.y);
                                    root.rubberBandRect = Qt.rect(mouse.x, mouse.y, 0, 0);
                                    root.rubberBandActive = true;
                                }
                            }
                            onPositionChanged: mouse => {
                                if (root.rubberBandActive) {
                                    root.rubberBandRect = Qt.rect(
                                        Math.min(root.rubberBandStart.x, mouse.x),
                                        Math.min(root.rubberBandStart.y, mouse.y),
                                        Math.abs(mouse.x - root.rubberBandStart.x),
                                        Math.abs(mouse.y - root.rubberBandStart.y)
                                    );
                                    root.updateRubberBandSelection();
                                }
                            }
                            onReleased: root.rubberBandActive = false
                            onCanceled: root.rubberBandActive = false
                        }

                        // Visual rubberband marquee selection box
                        Rectangle {
                            visible: root.rubberBandActive && root.rubberBandRect.width > 2 && root.rubberBandRect.height > 2
                            x: root.rubberBandRect.x; y: root.rubberBandRect.y
                            width: root.rubberBandRect.width; height: root.rubberBandRect.height
                            color: Qt.rgba(0.04, 0.52, 1.0, 0.18)
                            border.width: 1; border.color: root.accentBlue
                            radius: 3
                            z: 200
                        }

                        // --- VIEW 1: ICON VIEW ---
                        GridView {
                            id: iconGrid
                            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 10
                            visible: root.viewMode === "icon"
                            clip: true
                            interactive: false
                            cellWidth: root.iconScale + 44
                            cellHeight: root.iconScale + 60
                            model: iconGridModel
                            z: 3
                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; from: 0.90; to: 1; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                                }
                            }
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; to: 0.72; duration: 170; easing.type: Easing.OutCubic }
                                }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "x,y"; duration: 200; easing.type: Easing.OutCubic }
                            }
                            delegate: Item {
                                id: iconCell
                                required property string path
                                readonly property var modelData: root.iconItemMap[path] || ({ isDir: false, path: path, displayName: "", kind: "", mtime: 0, size: 0, icon: "", thumb: "", folderColor: "", tags: [] })
                                readonly property bool sel: root.isSelected(modelData.path)
                                readonly property bool isDropTarget: root.itemDragging && modelData.isDir && root.dropHoverTargetPath === modelData.path
                                width: iconGrid.cellWidth; height: iconGrid.cellHeight
                                Drag.dragType: Drag.Automatic
                                Drag.supportedActions: Qt.MoveAction
                                Drag.mimeData: ({ "text/uri-list": root.dragUris() })

                                Column {
                                    anchors.centerIn: parent
                                    width: iconGrid.cellWidth - 10
                                    spacing: 6
                                    opacity: (root.itemDragging && root.dragPaths.indexOf(iconCell.modelData.path) >= 0) ? 0.45 : (root.isDotHidden(iconCell.modelData) ? 0.60 : 1.0)
                                    Behavior on opacity { NumberAnimation { duration: 120 } }

                                    // Icon or Thumbnail frame
                                    Item {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: root.iconScale; height: root.iconScale

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: root.iconScale + 12; height: root.iconScale + 8
                                            radius: 10
                                            color: iconCell.isDropTarget ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.22) : (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                                            border.width: iconCell.isDropTarget ? 1.8 : 0
                                            border.color: iconCell.isDropTarget ? root.accentBlue : "transparent"
                                            opacity: (iconCell.sel || iconCell.isDropTarget) ? 1 : 0
                                            scale: iconCell.isDropTarget ? 1.04 : (iconCell.sel ? 1 : 0.94)
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                                        }

                                        // Thumbnail image (with white photo border like Finder)
                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: modelData.thumb !== ""
                                            width: root.iconScale - 6; height: root.iconScale - 6
                                            radius: 6
                                            color: "#111"
                                            border.width: 2; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : "white"
                                            clip: true
                                            Image {
                                                anchors.fill: parent
                                                source: modelData.thumb ? "file://" + modelData.thumb : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true; smooth: true
                                            }
                                        }

                                        // Theme Icon (with optional colorization tint for tagged folders, keeping exact shape!)
                                        Image {
                                            anchors.centerIn: parent
                                            visible: modelData.thumb === "" && modelData.icon !== ""
                                            width: root.iconScale * 0.88; height: root.iconScale * 0.88
                                            source: modelData.icon ? "file://" + modelData.icon : ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true; smooth: true
                                            layer.enabled: modelData.isDir && modelData.folderColor !== ""
                                            layer.effect: MultiEffect {
                                                colorization: modelData.isDir && modelData.folderColor !== "" ? 0.65 : 0
                                                colorizationColor: modelData.folderColor || "transparent"
                                            }
                                        }

                                        // Fallback Glyph
                                        WGlyph {
                                            anchors.centerIn: parent
                                            visible: modelData.thumb === "" && modelData.icon === ""
                                            width: root.iconScale * 0.65; height: root.iconScale * 0.65
                                            kind: modelData.isDir ? "folder" : "doc"
                                            color: (modelData.isDir && modelData.folderColor !== "") ? modelData.folderColor : (modelData.isDir ? "#4CB5FF" : root.textMuted)
                                        }
                                    }

                                    // Label + Colored Tag Dots
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(parent.width, labelRow.implicitWidth + 12)
                                        height: labelRow.implicitHeight + 4
                                        radius: 5
                                        color: iconCell.sel ? root.accentBlue : "transparent"
                                        Behavior on color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }

                                        Row {
                                            id: labelRow
                                            anchors.centerIn: parent; spacing: 4
                                            Repeater {
                                                model: iconCell.modelData.tags || []
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 8; height: 8; radius: 4
                                                    color: root.tagColor(modelData)
                                                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                                                }
                                            }
                                            Text {
                                                width: Math.min(iconCell.width - 28, implicitWidth)
                                                text: modelData.displayName
                                                color: iconCell.sel ? "white" : root.textPrimary
                                                font.family: root.fam; font.pixelSize: 12
                                                horizontalAlignment: Text.AlignHCenter
                                                wrapMode: Text.WrapAnywhere
                                                maximumLineCount: 2
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: iconCellMa
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    preventStealing: true
                                    property point pressWinPos: Qt.point(0, 0)
                                    property bool dragArmed: false
                                    onPressed: mouse => {
                                        if (mouse.button === Qt.LeftButton) {
                                            pressWinPos = mapToItem(windowFrame, mouse.x, mouse.y);
                                            dragArmed = true;
                                        } else {
                                            dragArmed = false;
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (!dragArmed || !(mouse.buttons & Qt.LeftButton)) return;
                                        var wp = mapToItem(windowFrame, mouse.x, mouse.y);
                                        if (!root.itemDragging) {
                                            if (Math.hypot(wp.x - pressWinPos.x, wp.y - pressWinPos.y) > 7) {
                                                root.startItemDrag(iconCell.modelData, wp.x, wp.y);
                                                root.startNativeDrag(iconCell);
                                            }
                                        } else {
                                            root.updateItemDrag(wp.x, wp.y);
                                        }
                                    }
                                    onReleased: mouse => {
                                        dragArmed = false;
                                        if (root.itemDragging) {
                                            root.finishItemDrag();
                                        } else if (mouse.button === Qt.LeftButton) {
                                            root.selectItem(iconCell.modelData, mouse.modifiers);
                                        }
                                    }
                                    onCanceled: {
                                        dragArmed = false;
                                        if (root.itemDragging) root.finishItemDrag();
                                    }
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            if (!root.isSelected(iconCell.modelData.path)) root.selectItem(iconCell.modelData, 0);
                                            root.contextItem = iconCell.modelData;
                                            itemMenu.popup();
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            if (iconCell.modelData.isDir) root.addTab(iconCell.modelData.path);
                                        }
                                    }
                                    onDoubleClicked: mouse => {
                                        if (mouse.button === Qt.LeftButton) root.activateItem(iconCell.modelData);
                                    }
                                }
                            }
                            LiquidScrollBar {
                                id: iconScrollBar
                                flick: iconGrid
                                material: "liquid"
                                dark: root.darkMode
                                compact: true
                                anchors.right: iconGrid.right
                                anchors.rightMargin: -12
                                anchors.top: iconGrid.top
                                anchors.bottom: iconGrid.bottom
                                alwaysVisible: iconGrid.contentHeight > iconGrid.height
                                z: 250
                            }
                            property real targetScrollY: 0
                            NumberAnimation {
                                id: iconScrollAnim
                                target: iconGrid
                                property: "contentY"
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                            MouseArea {
                                anchors.fill: parent
                                z: 50
                                acceptedButtons: Qt.NoButton
                                onWheel: wheel => {
                                    if (wheel.modifiers & Qt.ControlModifier) {
                                        var dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
                                        if (dy !== 0) {
                                            var step = (dy / 120.0) * 14.0;
                                            if (Math.abs(step) < 4) step = dy > 0 ? 8 : -8;
                                            root.zoomIconScale(step);
                                        }
                                        wheel.accepted = true;
                                    } else {
                                        var maxY = Math.max(0, iconGrid.contentHeight - iconGrid.height);
                                        var scrollStep = wheel.angleDelta.y * 1.9;
                                        var base = iconScrollAnim.running ? iconGrid.targetScrollY : iconGrid.contentY;
                                        iconGrid.targetScrollY = Math.max(0, Math.min(maxY, base - scrollStep));
                                        iconScrollAnim.stop();
                                        iconScrollAnim.from = iconGrid.contentY;
                                        iconScrollAnim.to = iconGrid.targetScrollY;
                                        iconScrollAnim.start();
                                        wheel.accepted = true;
                                    }
                                }
                            }
                        }

                        // --- VIEW 2: LIST VIEW (with inline expandable disclosure triangles!) ---
                        Item {
                            anchors.fill: parent
                            visible: root.viewMode === "list"
                            z: 3

                            // Column Headers
                            Rectangle {
                                id: listHeader
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 28
                                color: "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineCol }
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18
                                    ListColHead { width: parent.width - 330; label: "Name"; field: "name"; sortBy: root.sortBy; sortAsc: root.sortAsc; textCol: root.textMuted; fam: root.fam; onClicked: root.setSort("name") }
                                    ListColHead { width: 155; label: "Date Modified"; field: "date"; sortBy: root.sortBy; sortAsc: root.sortAsc; textCol: root.textMuted; fam: root.fam; onClicked: root.setSort("date") }
                                    ListColHead { width: 85; label: "Size"; field: "size"; sortBy: root.sortBy; sortAsc: root.sortAsc; alignRight: true; textCol: root.textMuted; fam: root.fam; onClicked: root.setSort("size") }
                                    ListColHead { width: 90; label: "Kind"; field: "kind"; sortBy: root.sortBy; sortAsc: root.sortAsc; textCol: root.textMuted; fam: root.fam; onClicked: root.setSort("kind") }
                                }
                            }

                            ListView {
                                id: listView
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: listHeader.bottom; anchors.bottom: parent.bottom
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                clip: true
                                model: flatListModel
                                add: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
                                        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 170; easing.type: Easing.OutCubic }
                                    }
                                }
                                remove: Transition {
                                    NumberAnimation { property: "opacity"; to: 0; duration: 130; easing.type: Easing.OutCubic }
                                }
                                displaced: Transition {
                                    NumberAnimation { properties: "y"; duration: 180; easing.type: Easing.OutCubic }
                                }
                                delegate: Rectangle {
                                    id: lRow
                                    required property string path
                                    required property int depth
                                    required property int index
                                    readonly property var it: root.flatItemMap[path] || ({ isDir: false, path: path, displayName: "", kind: "", mtime: 0, size: 0, icon: "", thumb: "", tags: [] })
                                    readonly property bool sel: root.isSelected(it.path)
                                    readonly property bool expanded: !!root.expandedDirs[it.path]
                                    readonly property bool isDropTarget: root.itemDragging && it.isDir && root.dropHoverTargetPath === it.path
                                    width: listView.width; height: 28; radius: 7
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.MoveAction
                                    Drag.mimeData: ({ "text/uri-list": root.dragUris() })
                                    color: isDropTarget ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.22)
                                         : (sel ? root.accentBlue : (index % 2 === 1 ? root.surfaceAlt : "transparent"))
                                    border.width: isDropTarget ? 1.5 : 0
                                    border.color: isDropTarget ? root.accentBlue : "transparent"
                                    Behavior on color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }

                                    Row {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                        opacity: (root.itemDragging && root.dragPaths.indexOf(lRow.it.path) >= 0) ? 0.45 : (root.isDotHidden(lRow.it) ? 0.60 : 1.0)
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        // Name + Indent + Disclosure Arrow + Icon
                                        Item {
                                            width: parent.width - 330; height: parent.height
                                            Row {
                                                anchors.fill: parent; anchors.leftMargin: lRow.depth * 18; spacing: 6
                                                // Disclosure triangle (rounded vector chevron with smooth rotation)
                                                Item {
                                                    width: 16; height: parent.height
                                                    Canvas {
                                                        anchors.centerIn: parent
                                                        width: 10; height: 10
                                                        visible: lRow.it.isDir
                                                        rotation: lRow.expanded ? 90 : 0
                                                        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                        property color ink: lRow.sel ? "white" : root.textMuted
                                                        onInkChanged: requestPaint()
                                                        onPaint: {
                                                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                                            ctx.strokeStyle = ink; ctx.lineWidth = 1.4;
                                                            ctx.lineCap = "round"; ctx.lineJoin = "round";
                                                            ctx.beginPath(); ctx.moveTo(3.5, 2.0); ctx.lineTo(6.8, 5.0); ctx.lineTo(3.5, 8.0); ctx.stroke();
                                                        }
                                                    }
                                                    MouseArea { anchors.fill: parent; enabled: lRow.it.isDir; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.toggleListExpand(lRow.it) }
                                                }
                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 16; height: 16
                                                    source: lRow.it.thumb ? "file://" + lRow.it.thumb : (lRow.it.icon ? "file://" + lRow.it.icon : "")
                                                    fillMode: Image.PreserveAspectFit; asynchronous: true
                                                    visible: source !== ""
                                                }
                                                Repeater {
                                                    model: lRow.it.tags || []
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 7; height: 7; radius: 3.5; color: root.tagColor(modelData)
                                                    }
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Math.max(40, parent.width - 60)
                                                    text: lRow.it.displayName
                                                    color: lRow.sel ? "white" : root.textPrimary
                                                    font.family: root.fam; font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                        Text {
                                            width: 155; height: parent.height; verticalAlignment: Text.AlignVCenter
                                            text: root.formatDate(lRow.it.mtime)
                                            color: lRow.sel ? Qt.rgba(1, 1, 1, 0.88) : root.textMuted
                                            font.family: root.fam; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 85; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                                            text: lRow.it.isDir ? "--" : root.formatBytes(lRow.it.size)
                                            color: lRow.sel ? Qt.rgba(1, 1, 1, 0.88) : root.textMuted
                                            font.family: root.fam; font.pixelSize: 12
                                        }
                                        Text {
                                            width: 90; leftPadding: 14; height: parent.height; verticalAlignment: Text.AlignVCenter
                                            text: lRow.it.kind
                                            color: lRow.sel ? Qt.rgba(1, 1, 1, 0.88) : root.textMuted
                                            font.family: root.fam; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        z: -1
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        preventStealing: true
                                        property point pressWinPos: Qt.point(0, 0)
                                        property bool dragArmed: false
                                        onPressed: mouse => {
                                            if (mouse.button === Qt.LeftButton) {
                                                pressWinPos = mapToItem(windowFrame, mouse.x, mouse.y);
                                                dragArmed = true;
                                            } else {
                                                dragArmed = false;
                                            }
                                        }
                                        onPositionChanged: mouse => {
                                            if (!dragArmed || !(mouse.buttons & Qt.LeftButton)) return;
                                            var wp = mapToItem(windowFrame, mouse.x, mouse.y);
                                            if (!root.itemDragging) {
                                                if (Math.hypot(wp.x - pressWinPos.x, wp.y - pressWinPos.y) > 7) {
                                                root.startItemDrag(lRow.it, wp.x, wp.y);
                                                root.startNativeDrag(lRow);
                                                }
                                            } else {
                                                root.updateItemDrag(wp.x, wp.y);
                                            }
                                        }
                                        onReleased: mouse => {
                                            dragArmed = false;
                                            if (root.itemDragging) {
                                                root.finishItemDrag();
                                            } else if (mouse.button === Qt.LeftButton) {
                                                root.selectItem(lRow.it, mouse.modifiers);
                                            }
                                        }
                                        onCanceled: {
                                            dragArmed = false;
                                            if (root.itemDragging) root.finishItemDrag();
                                        }
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                if (!root.isSelected(lRow.it.path)) root.selectItem(lRow.it, 0);
                                                root.contextItem = lRow.it;
                                                itemMenu.popup();
                                            } else if (mouse.button === Qt.MiddleButton) {
                                                if (lRow.it.isDir) root.addTab(lRow.it.path);
                                            }
                                        }
                                        onDoubleClicked: mouse => {
                                            if (mouse.button === Qt.LeftButton) root.activateItem(lRow.it);
                                        }
                                    }
                                }
                            }
                            LiquidScrollBar { flick: listView; material: "liquid"; dark: root.darkMode; compact: true; anchors.right: listView.right; anchors.top: listView.top; anchors.bottom: listView.bottom }
                        }

                        // --- VIEW 3: COLUMN VIEW (Miller Columns) ---
                        Flickable {
                            id: colFlick
                            anchors.fill: parent
                            visible: root.viewMode === "column"
                            z: 3
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            contentWidth: Math.max(width, colRow.implicitWidth)
                            contentHeight: height
                            Behavior on contentX {
                                enabled: !colFlick.dragging && !colFlick.flicking
                                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                            }
                            onContentWidthChanged: {
                                if (contentWidth > width) contentX = contentWidth - width;
                                else contentX = 0;
                            }
                            onWidthChanged: {
                                if (contentWidth <= width) contentX = 0;
                            }

                            Row {
                                id: colRow
                                height: colFlick.height
                                Repeater {
                                    id: colRepeater
                                    model: root.columns
                                    delegate: Item {
                                        required property var modelData
                                        required property int index
                                        readonly property int colIdx: index
                                        readonly property alias colListView: colList
                                        readonly property bool isDeepestSelectedCol: {
                                            for (var k = root.columns.length - 1; k >= 0; k--) {
                                                if (root.columns[k] && root.columns[k].selectedPath !== "") return k === colIdx;
                                            }
                                            return colIdx === 0;
                                        }
                                        width: 228; height: colRow.height

                                        ListView {
                                            id: colList
                                            anchors.fill: parent; anchors.margins: 6
                                            clip: true
                                            model: modelData.items || []
                                            delegate: Rectangle {
                                                id: mRow
                                                required property var modelData
                                                readonly property bool active: root.columns[colIdx] && modelData.path === root.columns[colIdx].selectedPath
                                                readonly property bool multiSel: root.isSelected(modelData.path)
                                                readonly property bool isPrimaryFocus: multiSel || (active && isDeepestSelectedCol)
                                                readonly property bool isDropTarget: root.itemDragging && modelData.isDir && root.dropHoverTargetPath === modelData.path
                                                width: 216; height: 26; radius: 6
                                                Drag.dragType: Drag.Automatic
                                                Drag.supportedActions: Qt.MoveAction
                                                Drag.mimeData: ({ "text/uri-list": root.dragUris() })
                                                color: isDropTarget ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.22)
                                                     : (isPrimaryFocus ? root.accentBlue
                                                     : (active ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10)) : "transparent"))
                                                border.width: isDropTarget ? 1.5 : 0
                                                border.color: isDropTarget ? root.accentBlue : "transparent"
                                                Behavior on color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }
                                                Row {
                                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 7
                                                    opacity: (root.itemDragging && root.dragPaths.indexOf(mRow.modelData.path) >= 0) ? 0.45 : (root.isDotHidden(mRow.modelData) ? 0.60 : 1.0)
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    Image {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 15; height: 15
                                                        source: modelData.thumb ? "file://" + modelData.thumb : (modelData.icon ? "file://" + modelData.icon : "")
                                                        fillMode: Image.PreserveAspectFit; asynchronous: true
                                                        layer.enabled: modelData.isDir && modelData.folderColor !== ""
                                                        layer.effect: MultiEffect {
                                                            colorization: modelData.isDir && modelData.folderColor !== "" ? 0.65 : 0
                                                            colorizationColor: modelData.folderColor || "transparent"
                                                        }
                                                    }
                                                    Repeater {
                                                        model: modelData.tags || []
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 7; height: 7; radius: 3.5; color: root.tagColor(modelData)
                                                            border.width: 0.8; border.color: Qt.rgba(0, 0, 0, 0.25)
                                                        }
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: Math.max(40, parent.width - 36 - ((modelData.tags ? modelData.tags.length : 0) * 14))
                                                        text: modelData.displayName
                                                        color: mRow.isPrimaryFocus ? "white" : root.textPrimary
                                                        font.family: Fonts.forWeight(mRow.active ? Font.DemiBold : Font.Normal, root.fam)
                                                        font.weight: mRow.active ? Font.DemiBold : Font.Normal
                                                        font.pixelSize: 13; elide: Text.ElideRight
                                                    }
                                                    Canvas {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 8; height: 10
                                                        visible: modelData.isDir
                                                        property color ink: mRow.isPrimaryFocus ? "white" : root.textMuted
                                                        onInkChanged: requestPaint()
                                                        onPaint: {
                                                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                                            ctx.strokeStyle = ink; ctx.lineWidth = 1.4;
                                                            ctx.lineCap = "round"; ctx.lineJoin = "round";
                                                            ctx.beginPath(); ctx.moveTo(2.2, 2.0); ctx.lineTo(5.6, 5.0); ctx.lineTo(2.2, 8.0); ctx.stroke();
                                                        }
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                                    preventStealing: true
                                                    property point pressWinPos: Qt.point(0, 0)
                                                    property bool dragArmed: false
                                                    onPressed: mouse => {
                                                        if (mouse.button === Qt.LeftButton) {
                                                            pressWinPos = mapToItem(windowFrame, mouse.x, mouse.y);
                                                            dragArmed = true;
                                                        } else {
                                                            dragArmed = false;
                                                        }
                                                    }
                                                    onPositionChanged: mouse => {
                                                        if (!dragArmed || !(mouse.buttons & Qt.LeftButton)) return;
                                                        var wp = mapToItem(windowFrame, mouse.x, mouse.y);
                                                        if (!root.itemDragging) {
                                                            if (Math.hypot(wp.x - pressWinPos.x, wp.y - pressWinPos.y) > 7) {
                                                                root.startItemDrag(mRow.modelData, wp.x, wp.y);
                                                                root.startNativeDrag(mRow);
                                                            }
                                                        } else {
                                                            root.updateItemDrag(wp.x, wp.y);
                                                        }
                                                    }
                                                    onReleased: mouse => {
                                                        dragArmed = false;
                                                        if (root.itemDragging) {
                                                            root.finishItemDrag();
                                                        } else if (mouse.button === Qt.LeftButton) {
                                                            root.selectColumnItem(colIdx, mRow.modelData, mouse.modifiers);
                                                        }
                                                    }
                                                    onCanceled: {
                                                        dragArmed = false;
                                                        if (root.itemDragging) root.finishItemDrag();
                                                    }
                                                    onClicked: mouse => {
                                                        if (mouse.button === Qt.RightButton) {
                                                            if (!root.isSelected(mRow.modelData.path)) root.selectColumnItem(colIdx, mRow.modelData, 0);
                                                            root.contextItem = mRow.modelData;
                                                            itemMenu.popup();
                                                        } else if (mouse.button === Qt.MiddleButton) {
                                                            if (mRow.modelData.isDir) root.addTab(mRow.modelData.path);
                                                        }
                                                    }
                                                    onDoubleClicked: mouse => {
                                                        if (mouse.button === Qt.LeftButton) root.activateItem(mRow.modelData);
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.lineCol }
                                    }
                                }
                            }
                            LiquidScrollBar {
                                flick: colFlick
                                horizontal: true
                                material: "liquid"
                                dark: root.darkMode
                                compact: true
                                anchors.left: colFlick.left
                                anchors.right: colFlick.right
                                anchors.bottom: colFlick.bottom
                                alwaysVisible: colFlick.contentWidth > colFlick.width
                                z: 250
                            }
                        }

                        // --- VIEW 4: GALLERY VIEW ---
                        Item {
                            anchors.fill: parent
                            visible: root.viewMode === "gallery"
                            z: 3

                            Item {
                                anchors.left: parent.left; anchors.right: galleryInspector.left
                                anchors.top: parent.top; anchors.bottom: filmstrip.top
                                readonly property var cur: root.items[root.galleryIndex] || null

                                Image {
                                    anchors.centerIn: parent
                                    width: parent.width - 60; height: parent.height - 40
                                    visible: parent.cur && (parent.cur.thumb !== "" || parent.cur.icon !== "")
                                    source: parent.cur ? ("file://" + (parent.cur.thumb || parent.cur.icon)) : ""
                                    fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                                    layer.enabled: parent.cur && parent.cur.isDir && parent.cur.folderColor !== ""
                                    layer.effect: MultiEffect {
                                        colorization: parent.cur && parent.cur.isDir && parent.cur.folderColor !== "" ? 0.65 : 0
                                        colorizationColor: (parent.cur && parent.cur.folderColor) || "transparent"
                                    }
                                }
                                Row {
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 6
                                    Repeater {
                                        model: parent.parent.cur ? (parent.parent.cur.tags || []) : []
                                        delegate: Rectangle {
                                            required property string modelData
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 8; height: 8; radius: 4
                                            color: root.tagColor(modelData)
                                            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.parent.cur ? parent.parent.cur.displayName : ""
                                        color: root.textPrimary; font.family: root.fam; font.pixelSize: 13
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        if (parent.cur) {
                                            if (!root.isSelected(parent.cur.path)) root.selectItem(parent.cur, 0);
                                            root.contextItem = parent.cur;
                                            itemMenu.popup();
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: galleryInspector
                                width: 245; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(0, 0, 0, 0.02)
                                Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: root.lineCol }
                                PreviewInspector {
                                    anchors.fill: parent
                                    items: root.items[root.galleryIndex] ? [root.items[root.galleryIndex]] : []
                                    previewText: root.previewTextContent
                                    dark: root.darkMode; fam: root.fam
                                    textPrimary: root.textPrimary; textMuted: root.textMuted; lineCol: root.lineCol
                                    onTagClicked: tag => root.navigateTo("finder://tag/" + tag, true)
                                    onCopyPath: p => Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", p])
                                }
                            }

                            ListView {
                                id: filmstrip
                                anchors.left: parent.left; anchors.right: galleryInspector.left
                                anchors.bottom: parent.bottom; anchors.margins: 10
                                height: 76; orientation: ListView.Horizontal; spacing: 8; clip: true
                                model: root.items
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: 68; height: 68; radius: 8
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                                    border.width: index === root.galleryIndex ? 2 : 1
                                    border.color: index === root.galleryIndex ? root.accentBlue : root.lineCol
                                    clip: true
                                    Image {
                                        anchors.fill: parent; anchors.margins: 4
                                        source: modelData.thumb ? "file://" + modelData.thumb : (modelData.icon ? "file://" + modelData.icon : "")
                                        fillMode: Image.PreserveAspectFit; asynchronous: true
                                    }
                                    Row {
                                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                                        spacing: 3
                                        Repeater {
                                            model: modelData.tags || []
                                            delegate: Rectangle {
                                                required property string modelData
                                                width: 6; height: 6; radius: 3
                                                color: root.tagColor(modelData)
                                                border.width: 0.8; border.color: Qt.rgba(0, 0, 0, 0.3)
                                            }
                                        }
                                    }
                                    TapHandler {
                                        onTapped: { root.galleryIndex = index; root.selectItem(modelData, 0); }
                                        onDoubleTapped: root.activateItem(modelData)
                                    }
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: {
                                            root.galleryIndex = index;
                                            if (!root.isSelected(modelData.path)) root.selectItem(modelData, 0);
                                            root.contextItem = modelData;
                                            itemMenu.popup();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // FLOATING LIQUID GLASS ACTIVITY / ERROR PILL
                Timer { id: errorToastTimer; interval: 3200; onTriggered: root.errorToast = "" }
                Rectangle {
                    id: activityPill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: bottomChrome.top
                    anchors.bottomMargin: 12
                    width: activityRow.implicitWidth + 24
                    height: 32; radius: 16
                    z: 40
                    visible: opacity > 0.01
                    opacity: (root.busyLabel !== "" || root.errorToast !== "") ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    color: root.errorToast !== "" ? Qt.rgba(0.95, 0.24, 0.22, 0.90) : (root.darkMode ? Qt.rgba(0.16, 0.16, 0.18, 0.88) : Qt.rgba(0.96, 0.96, 0.98, 0.94))
                    border.width: 1; border.color: root.errorToast !== "" ? Qt.rgba(1, 1, 1, 0.25) : root.lineCol
                    GlassSlab {
                        anchors.fill: parent; glass: true
                        visible: root.errorToast === ""
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode; baseColor: root.pillBase; cornerR: 16
                        thickness: 6; strengthMul: 0.25; rim: 0.16; tint: root.darkMode ? 0.48 : 0.72; flatInner: 1
                        z: -1
                    }
                    Row {
                        id: activityRow
                        anchors.centerIn: parent; spacing: 8
                        Canvas {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14
                            visible: root.busyLabel !== "" && root.errorToast === ""
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                ctx.strokeStyle = root.accentBlue; ctx.lineWidth = 2; ctx.lineCap = "round";
                                ctx.beginPath(); ctx.arc(7, 7, 5, 0, Math.PI * 1.45); ctx.stroke();
                            }
                            RotationAnimation on rotation {
                                running: activityPill.visible && root.busyLabel !== ""
                                from: 0; to: 360; duration: 750; loops: Animation.Infinite
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.errorToast !== "" ? root.errorToast : root.busyLabel
                            color: root.errorToast !== "" ? "white" : root.textPrimary
                            font.family: root.fam; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                }

                // Click anywhere outside bottomChrome while editing Path Bar -> exit edit mode & pass click through
                MouseArea {
                    anchors.fill: parent
                    z: 19
                    visible: win.pathBarEditing
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => {
                        win.pathBarEditing = false;
                        windowFrame.forceActiveFocus();
                        mouse.accepted = false;
                    }
                }

                // BOTTOM CHROME: PATH BAR + STATUS BAR
                Column {
                    id: bottomChrome
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    z: 20

                    // Path Bar (clickable breadcrumbs + inline editable manual path mode)
                    Rectangle {
                        id: pathBarContainer
                        width: parent.width
                        height: root.showPathBar ? 28 : 0
                        visible: height > 0
                        clip: true
                        color: "transparent"
                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.lineCol }

                        // Click empty space on Path Bar to switch to manual text path mode
                        MouseArea {
                            anchors.fill: parent
                            visible: !win.pathBarEditing
                            cursorShape: Qt.IBeamCursor
                            onClicked: win.startPathBarEdit()
                        }

                        Row {
                            opacity: win.pathBarEditing ? 0.0 : 1.0
                            scale: win.pathBarEditing ? 0.97 : 1.0
                            visible: opacity > 0.01
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 36; spacing: 5
                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Repeater {
                                id: crumbRepeater
                                model: root.breadcrumbParts()
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    readonly property string crumbPath: modelData.path
                                    readonly property bool isDropTarget: root.itemDragging && root.dropHoverTargetPath === crumbPath
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                    Text {
                                        visible: index > 0; text: "›"; color: root.textMuted; font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Rectangle {
                                        width: crumbRow.implicitWidth + 10; height: 22; radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: isDropTarget ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.22) : "transparent"
                                        border.width: isDropTarget ? 1.2 : 0
                                        border.color: isDropTarget ? root.accentBlue : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Row {
                                            id: crumbRow
                                            spacing: 4; anchors.centerIn: parent
                                            WGlyph {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 12; height: 12
                                                kind: index === 0 ? "monitor" : "folder"
                                                color: (isDropTarget || index === root.breadcrumbParts().length - 1) ? root.accentBlue : root.textMuted
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.label
                                                color: (isDropTarget || crumbHover.hovered) ? root.textPrimary : root.textMuted
                                                font.family: root.fam; font.pixelSize: 12
                                            }
                                        }
                                        HoverHandler { id: crumbHover }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(modelData.path, true)
                                        }
                                    }
                                }
                            }
                        }

                        // Subtle Edit Path button on the right of Path Bar
                        Rectangle {
                            opacity: win.pathBarEditing ? 0.0 : 1.0
                            visible: opacity > 0.01
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 5
                            color: pathEditMa.containsMouse ? root.pillHoverBg : "transparent"
                            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Text {
                                anchors.centerIn: parent
                                text: "✎"
                                color: pathEditMa.containsMouse ? root.textPrimary : root.textMuted
                                font.pixelSize: 11
                            }
                            HoverHandler { id: pathEditHover }
                            MacToolTip { visible: pathEditHover.hovered; text: "Edit Path (Ctrl+L)" }
                            MouseArea {
                                id: pathEditMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: win.startPathBarEdit()
                            }
                        }

                        // Inline Editable Path Field
                        Row {
                            opacity: win.pathBarEditing ? 1.0 : 0.0
                            scale: win.pathBarEditing ? 1.0 : 0.96
                            visible: opacity > 0.01
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.topMargin: 3; anchors.bottomMargin: 3
                            spacing: 6
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
                            TextField {
                                id: pathBarField
                                width: parent.width - 28
                                height: parent.height
                                leftPadding: 8; rightPadding: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.textPrimary
                                placeholderText: "~/Projects or /path/to/folder"
                                placeholderTextColor: root.textMuted
                                selectionColor: root.accentBlue
                                selectedTextColor: "white"
                                font.family: root.fam; font.pixelSize: 12
                                background: Rectangle {
                                    color: root.darkMode ? "#1B1B1E" : "white"
                                    radius: 6
                                    border.width: 1.5
                                    border.color: root.accentBlue
                                }
                                Keys.onEscapePressed: win.pathBarEditing = false
                                onActiveFocusChanged: if (!activeFocus && win.pathBarEditing) win.pathBarEditing = false
                                onAccepted: {
                                    var target = text.trim().replace(/^~(?=\/|$)/, root.home);
                                    if (target !== "") root.navigateTo(target, true);
                                    win.pathBarEditing = false;
                                }
                            }
                            Rectangle {
                                width: 22; height: parent.height; radius: 6
                                color: pathCancelMa.containsMouse ? root.pillHoverBg : root.pillBg
                                Text { anchors.centerIn: parent; text: "×"; color: root.textMuted; font.pixelSize: 12; font.weight: Font.Bold }
                                MouseArea {
                                    id: pathCancelMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: win.pathBarEditing = false
                                }
                            }
                        }
                    }

                    // Status Bar
                    Rectangle {
                        width: parent.width
                        height: root.showStatusBar ? 28 : 0
                        visible: height > 0
                        color: "transparent"
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.lineCol }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            width: Math.max(0, parent.width - 188)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: (root.selectedPaths.length > 0
                                   ? (root.selectedPaths.length + " of " + root.items.length + " selected")
                                   : (root.items.length + " items"))
                                  + (root.diskFreeText ? (", " + root.diskFreeText) : "")
                            color: root.textMuted; font.family: root.fam; font.pixelSize: 12
                        }

                        // macOS Icon Size Slider at bottom right (3 discrete configs: 56, 80, 112)
                        Row {
                            visible: root.viewMode === "icon"
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // Small icon hint (clickable to jump to Small)
                            Canvas {
                                width: 10; height: 10
                                anchors.verticalCenter: parent.verticalCenter
                                property color ink: root.iconScaleIndex() === 0 ? root.accentBlue : root.textMuted
                                onInkChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                    ctx.strokeStyle = ink; ctx.lineWidth = 1;
                                    ctx.lineCap = "round"; ctx.lineJoin = "round";
                                    ctx.beginPath(); ctx.roundedRect(0.5, 0.5, 3.5, 3.5, 0.8, 0.8); ctx.stroke();
                                    ctx.beginPath(); ctx.roundedRect(5.5, 0.5, 3.5, 3.5, 0.8, 0.8); ctx.stroke();
                                    ctx.beginPath(); ctx.roundedRect(0.5, 5.5, 3.5, 3.5, 0.8, 0.8); ctx.stroke();
                                    ctx.beginPath(); ctx.roundedRect(5.5, 5.5, 3.5, 3.5, 0.8, 0.8); ctx.stroke();
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setIconScaleIndex(0)
                                }
                            }

                            // Slider with exactly 3 options (snap steps: 0, 0.5, 1.0)
                            LiquidSlider {
                                id: iconSlider
                                width: 84; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                dark: root.darkMode
                                accent: root.accentBlue
                                trackColor: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
                                trackH: 3; knobSize: 13
                                stepSize: 0.5
                                value: root.iconScaleIndex() / 2.0
                                onMoved: v => {
                                    var idx = Math.round(v * 2);
                                    root.setIconScaleIndex(idx);
                                }
                            }

                            // Large icon hint (clickable to jump to Large)
                            Canvas {
                                width: 14; height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                property color ink: root.iconScaleIndex() === 2 ? root.accentBlue : root.textMuted
                                onInkChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                    ctx.strokeStyle = ink; ctx.lineWidth = 1.2;
                                    ctx.lineCap = "round"; ctx.lineJoin = "round";
                                    ctx.beginPath(); ctx.roundedRect(0.5, 0.5, 5.5, 5.5, 1.2, 1.2); ctx.stroke();
                                    ctx.beginPath(); ctx.roundedRect(7.5, 0.5, 5.5, 5.5, 1.2, 1.2); ctx.stroke();
                                    ctx.beginPath(); ctx.roundedRect(0.5, 7.5, 5.5, 5.5, 1.2, 1.2); ctx.stroke();
                                    ctx.beginPath(); ctx.roundedRect(7.5, 7.5, 5.5, 5.5, 1.2, 1.2); ctx.stroke();
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setIconScaleIndex(2)
                                }
                            }
                        }
                    }

                    // Picker Action Bar (only visible in File / Folder / Save picker mode)
                    Rectangle {
                        id: pickerBar
                        width: parent.width
                        height: root.isPickerMode ? 52 : 0
                        visible: height > 0
                        clip: true
                        color: root.darkMode ? Qt.rgba(0.11, 0.12, 0.14, 0.94) : Qt.rgba(0.95, 0.96, 0.98, 0.96)
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.lineCol }

                        Row {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                            spacing: 10

                            // Left: New Folder button (in save / folder mode)
                            Rectangle {
                                visible: root.pickerMode === "save" || root.pickerMode === "folder"
                                anchors.verticalCenter: parent.verticalCenter
                                width: 92; height: 30; radius: 8
                                color: pkNewFolderMa.containsMouse ? root.pillHoverBg : root.pillBg
                                border.width: 1; border.color: root.lineCol
                                Text { anchors.centerIn: parent; text: "New Folder"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                                MouseArea {
                                    id: pkNewFolderMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.send({ op: "mkdir", parent: root.currentPath, name: "untitled folder" })
                                }
                            }

                            // Middle: Save filename input OR selection summary
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (root.pickerMode === "save" || root.pickerMode === "folder" ? 280 : 178)
                                height: 32

                                Row {
                                    visible: root.pickerMode === "save"
                                    anchors.fill: parent; spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Save As:"
                                        color: root.textMuted; font.family: root.fam; font.pixelSize: 12
                                    }
                                    TextField {
                                        id: pickerSaveField
                                        width: parent.width - 62; height: 30
                                        anchors.verticalCenter: parent.verticalCenter
                                        leftPadding: 10; rightPadding: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.textPrimary
                                        placeholderText: "Filename…"
                                        placeholderTextColor: root.textMuted
                                        selectionColor: root.accentBlue; selectedTextColor: "white"
                                        font.family: root.fam; font.pixelSize: 12
                                        background: Rectangle {
                                            color: root.darkMode ? "#1B1B1E" : "white"
                                            radius: 7
                                            border.width: pickerSaveField.activeFocus ? 1.5 : 1
                                            border.color: pickerSaveField.activeFocus ? root.accentBlue : root.lineCol
                                        }
                                        Keys.onEscapePressed: root.cancelPicker()
                                        onAccepted: root.confirmPicker(null)
                                    }
                                }

                                Text {
                                    visible: root.pickerMode !== "save"
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideMiddle
                                    color: root.textMuted; font.family: root.fam; font.pixelSize: 12
                                    text: {
                                        if (root.pickerMode === "folder") {
                                            var p = root.primarySelectedItem();
                                            return "Folder: " + (p && p.isDir ? p.path : root.currentPath);
                                        }
                                        if (root.selectedPaths.length === 0) return "Select a file to open";
                                        if (root.selectedPaths.length === 1) return root.selectedPaths[0];
                                        return root.selectedPaths.length + " items selected";
                                    }
                                }
                            }

                            // Right: Cancel + Confirm buttons
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Rectangle {
                                    width: 74; height: 30; radius: 8
                                    color: pkCancelMa.containsMouse ? root.pillHoverBg : root.pillBg
                                    border.width: 1; border.color: root.lineCol
                                    Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                                    MouseArea {
                                        id: pkCancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cancelPicker()
                                    }
                                }
                                Rectangle {
                                    width: 84; height: 30; radius: 8
                                    readonly property bool canConfirm: {
                                        if (root.pickerMode === "save") return pickerSaveField.text.trim() !== "";
                                        if (root.pickerMode === "folder") return root.currentPath.indexOf("finder://") !== 0;
                                        return root.selectedPaths.length > 0;
                                    }
                                    color: canConfirm ? root.accentBlue : root.pillBg
                                    opacity: canConfirm ? (pkConfirmMa.containsMouse ? 0.90 : 1.0) : 0.45
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.pickerMode === "save" ? "Save" : (root.pickerMode === "folder" ? "Choose" : "Open")
                                        color: parent.canConfirm ? "white" : root.textMuted
                                        font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: pkConfirmMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: parent.canConfirm ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: if (parent.canConfirm) root.confirmPicker(null)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. ANIMATED QUICK LOOK HUD OVERLAY (Spacebar)
            Item {
                id: qlOverlay
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.quickLookOpen && !!root.primarySelectedItem() ? 1.0 : 0.0
                z: 600
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                    TapHandler { onTapped: root.quickLookOpen = false }
                }

                Rectangle {
                    id: qlCard
                    readonly property var qlItem: root.primarySelectedItem()
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 720)
                    height: Math.min(parent.height - 60, 520)
                    radius: 18
                    color: root.darkMode ? "#232327" : "#F8F8FA"
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
                    scale: root.quickLookOpen ? 1.0 : 0.88
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    TapHandler {} // prevent backdrop click closing when clicking card

                    GlassSlab {
                        anchors.fill: parent; glass: true
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode; baseColor: root.pillBase; cornerR: 18
                        thickness: 8; strengthMul: 0.22; rim: 0.16; tint: 0.55; flatInner: 1
                        z: -1
                    }

                    // Header
                    Item {
                        id: qlHeader
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: 44
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineCol }

                        // Traffic Light Close button
                        Rectangle {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; radius: 7; color: "#FF5F57"
                            Text { anchors.centerIn: parent; text: "×"; color: Qt.rgba(0, 0, 0, 0.65); font.pixelSize: 10; font.weight: Font.Bold }
                            TapHandler { onTapped: root.quickLookOpen = false }
                        }

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 180; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
                            text: qlCard.qlItem ? qlCard.qlItem.displayName : ""
                            color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 14; font.weight: Font.DemiBold
                        }

                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 80; height: 26; radius: 13
                            color: root.accentBlue
                            Text { anchors.centerIn: parent; text: "Open"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                            TapHandler { onTapped: if (qlCard.qlItem) { root.quickLookOpen = false; root.activateItem(qlCard.qlItem); } }
                        }
                    }

                    // Content Stage
                    Item {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: qlHeader.bottom; anchors.bottom: parent.bottom
                        anchors.margins: 16

                        Image {
                            anchors.fill: parent
                            visible: qlCard.qlItem && (qlCard.qlItem.isImage || qlCard.qlItem.thumb !== "")
                            source: qlCard.qlItem ? ("file://" + (qlCard.qlItem.isImage ? qlCard.qlItem.path : qlCard.qlItem.thumb)) : ""
                            fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                        }

                        Flickable {
                            anchors.fill: parent
                            visible: qlCard.qlItem && qlCard.qlItem.isText && !qlCard.qlItem.isImage
                            contentHeight: qlTxt.implicitHeight + 16
                            clip: true
                            TextEdit {
                                id: qlTxt
                                width: parent.width
                                readOnly: true
                                text: root.previewTextContent
                                color: root.textPrimary
                                font.family: "Monospace"
                                font.pixelSize: 12
                                wrapMode: TextEdit.WrapAnywhere
                                selectByMouse: true
                            }
                        }

                        Column {
                            anchors.centerIn: parent; spacing: 10
                            visible: qlCard.qlItem && !qlCard.qlItem.isImage && qlCard.qlItem.thumb === "" && !qlCard.qlItem.isText
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 96; height: 96
                                source: qlCard.qlItem && qlCard.qlItem.icon ? ("file://" + qlCard.qlItem.icon) : ""
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qlCard.qlItem ? (qlCard.qlItem.kind + " — " + (qlCard.qlItem.isDir ? qlCard.qlItem.sizeText : root.formatBytes(qlCard.qlItem.size))) : ""
                                color: root.textMuted; font.family: root.fam; font.pixelSize: 13
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qlCard.qlItem ? ("Modified: " + root.formatDate(qlCard.qlItem.mtime)) : ""
                                color: root.textMuted; font.family: root.fam; font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // 4. GET INFO INSPECTOR SHEET (⌘I)
            Item {
                id: getInfoSheet
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.getInfoOpen && !!root.primarySelectedItem() ? 1.0 : 0.0
                z: 700
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                    TapHandler { onTapped: root.getInfoOpen = false }
                }

                Rectangle {
                    id: getInfoCard
                    readonly property var infoItem: root.primarySelectedItem()
                    anchors.centerIn: parent
                    width: 340; height: 490
                    radius: 16
                    color: root.darkMode ? "#252528" : "#F6F6F8"
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
                    scale: root.getInfoOpen ? 1.0 : 0.88
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    TapHandler {}

                    GlassSlab {
                        anchors.fill: parent; glass: true
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode; baseColor: root.pillBase; cornerR: 16
                        thickness: 8; strengthMul: 0.22; rim: 0.16; tint: 0.55; flatInner: 1
                        z: -1
                    }

                    // Header
                    Item {
                        id: giHeader
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: 40
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineCol }
                        Rectangle {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 13; height: 13; radius: 6.5; color: "#FF5F57"
                            Text { anchors.centerIn: parent; text: "×"; color: Qt.rgba(0, 0, 0, 0.65); font.pixelSize: 9; font.weight: Font.Bold }
                            TapHandler { onTapped: root.getInfoOpen = false }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: (getInfoCard.infoItem ? getInfoCard.infoItem.displayName : "") + " Info"
                            color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                            elide: Text.ElideMiddle; width: parent.width - 60; horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Content
                    Flickable {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: giHeader.bottom; anchors.bottom: parent.bottom
                        anchors.margins: 14
                        contentHeight: giCol.implicitHeight + 10
                        clip: true

                        Column {
                            id: giCol
                            width: parent.width; spacing: 12

                            // Top icon + name + size
                            Row {
                                spacing: 14; width: parent.width
                                Image {
                                    width: 56; height: 56
                                    source: getInfoCard.infoItem ? ("file://" + (getInfoCard.infoItem.thumb || getInfoCard.infoItem.icon)) : ""
                                    fillMode: Image.PreserveAspectFit
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 70; spacing: 4
                                    TextField {
                                        id: giNameField
                                        width: parent.width
                                        text: getInfoCard.infoItem ? getInfoCard.infoItem.name : ""
                                        color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                        font.pixelSize: 14; font.weight: Font.DemiBold
                                        background: Rectangle {
                                            color: giNameField.activeFocus ? (root.darkMode ? "#1C1C1E" : "white") : "transparent"
                                            radius: 5
                                            border.width: giNameField.activeFocus ? 1 : 0
                                            border.color: root.accentBlue
                                        }
                                        onAccepted: {
                                            if (getInfoCard.infoItem && text !== getInfoCard.infoItem.name) {
                                                root.send({ op: "rename", path: getInfoCard.infoItem.path, newName: text });
                                            }
                                        }
                                    }
                                    Text {
                                        text: getInfoCard.infoItem ? (getInfoCard.infoItem.isDir ? getInfoCard.infoItem.sizeText : root.formatBytes(getInfoCard.infoItem.size)) : ""
                                        color: root.textMuted; font.family: root.fam; font.pixelSize: 12
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: root.lineCol }

                            // General info
                            Column {
                                width: parent.width; spacing: 6
                                Text { text: "General:"; color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                                Row {
                                    spacing: 8; width: parent.width
                                    Text { width: 75; text: "Kind:"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                                    Text { width: parent.width - 83; text: getInfoCard.infoItem ? getInfoCard.infoItem.kind : ""; color: root.textPrimary; font.family: root.fam; font.pixelSize: 11; elide: Text.ElideRight }
                                }
                                Row {
                                    spacing: 8; width: parent.width
                                    Text { width: 75; text: "Where:"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                                    Text {
                                        width: parent.width - 110; text: getInfoCard.infoItem ? getInfoCard.infoItem.path : ""; color: root.textPrimary; font.family: root.fam; font.pixelSize: 11; elide: Text.ElideMiddle
                                    }
                                    Text {
                                        text: "Copy"; color: root.accentBlue; font.family: root.fam; font.pixelSize: 11
                                        TapHandler { onTapped: if (getInfoCard.infoItem) Quickshell.execDetached(["wl-copy", getInfoCard.infoItem.path]) }
                                    }
                                }
                                Row {
                                    spacing: 8; width: parent.width
                                    Text { width: 75; text: "Created:"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                                    Text { width: parent.width - 83; text: getInfoCard.infoItem ? root.formatDate(getInfoCard.infoItem.ctime) : ""; color: root.textPrimary; font.family: root.fam; font.pixelSize: 11 }
                                }
                                Row {
                                    spacing: 8; width: parent.width
                                    Text { width: 75; text: "Modified:"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                                    Text { width: parent.width - 83; text: getInfoCard.infoItem ? root.formatDate(getInfoCard.infoItem.mtime) : ""; color: root.textPrimary; font.family: root.fam; font.pixelSize: 11 }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: root.lineCol }

                            // Tags Section
                            Column {
                                width: parent.width; spacing: 6
                                Text { text: "Tags:"; color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: root.sidebarTags
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool hasTag: getInfoCard.infoItem && getInfoCard.infoItem.tags && getInfoCard.infoItem.tags.indexOf(modelData.name) >= 0
                                            width: 20; height: 20; radius: 10
                                            color: modelData.color
                                            border.width: hasTag ? 2 : 0
                                            border.color: "white"
                                            scale: hasTag ? 1.15 : 1
                                            Behavior on scale { NumberAnimation { duration: 150 } }
                                            TapHandler {
                                                onTapped: {
                                                    if (getInfoCard.infoItem) {
                                                        root.send({ op: "setTag", paths: [getInfoCard.infoItem.path], tag: modelData.name, toggle: true });
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: root.lineCol }

                            // Sharing & Permissions
                            Column {
                                width: parent.width; spacing: 6
                                Text { text: "Sharing & Permissions:"; color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                                Text { text: "You have Read & Write access to this item."; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                            }
                        }
                    }
                }
            }

            // 5. NEW SIDEBAR CATEGORY MODAL
            Item {
                id: newCategoryModal
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: 0.0
                z: 800
                function open() { opacity = 1.0; catInputField.forceActiveFocus(); }
                function close() { opacity = 0.0; }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Rectangle {
                    anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45)
                    TapHandler { onTapped: newCategoryModal.close() }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 280; height: 130; radius: 14
                    color: root.darkMode ? "#29292B" : "#F6F6F8"
                    border.width: 1; border.color: root.lineCol
                    TapHandler {}

                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 10
                        Text { text: "New Sidebar Section"; color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                        TextField {
                            id: catInputField
                            width: parent.width; height: 28
                            placeholderText: "Section name"
                            color: root.textPrimary
                            background: Rectangle { color: root.darkMode ? "#1E1E20" : "white"; radius: 6; border.width: 1; border.color: root.lineCol }
                            onAccepted: {
                                if (text.trim() !== "") root.send({ op: "addSidebarCategory", label: text.trim() });
                                text = ""; newCategoryModal.close();
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            Rectangle {
                                width: 64; height: 26; radius: 6; color: root.lineCol
                                Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.pixelSize: 11 }
                                TapHandler { onTapped: newCategoryModal.close() }
                            }
                            Rectangle {
                                width: 64; height: 26; radius: 6; color: root.accentBlue
                                Text { anchors.centerIn: parent; text: "Create"; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                TapHandler {
                                    onTapped: {
                                        if (catInputField.text.trim() !== "") root.send({ op: "addSidebarCategory", label: catInputField.text.trim() });
                                        catInputField.text = ""; newCategoryModal.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 6. NAUTILUS-STYLE OPEN WITH MODAL SHEET
            Item {
                id: openWithSheet
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.openWithOpen ? 1.0 : 0.0
                z: 850
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                    TapHandler { onTapped: root.openWithOpen = false }
                }

                Rectangle {
                    id: openWithCard
                    anchors.centerIn: parent
                    width: 400; height: 480
                    radius: 16
                    color: root.darkMode ? "#252528" : "#F6F6F8"
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
                    scale: root.openWithOpen ? 1.0 : 0.90
                    Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    TapHandler {}

                    GlassSlab {
                        anchors.fill: parent; glass: true
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode; baseColor: root.pillBase; cornerR: 16
                        thickness: 8; strengthMul: 0.22; rim: 0.16; tint: root.darkMode ? 0.55 : 0.78; flatInner: 1
                        z: -1
                    }

                    // Header: Cancel (top-left) | Title (center) | Open (top-right)
                    Item {
                        id: owHeader
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: 48
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineCol }

                        Rectangle {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64; height: 28; radius: 8
                            color: owCancelH.hovered ? root.pillHoverBg : root.pillBg
                            border.width: 1; border.color: root.lineCol
                            Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                            HoverHandler { id: owCancelH }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openWithOpen = false }
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 170
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Open With"
                                color: root.textPrimary
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
                                text: root.openWithTarget ? root.openWithTarget.displayName : ""
                                color: root.textMuted; font.family: root.fam; font.pixelSize: 11
                            }
                        }

                        Rectangle {
                            id: owOpenBtn
                            readonly property var selApp: root.filteredOpenWithApps()[root.openWithSelectedIdx] || null
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64; height: 28; radius: 8
                            opacity: selApp ? 1.0 : 0.45
                            color: root.accentBlue
                            Text { anchors.centerIn: parent; text: "Open"; color: "white"; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !!owOpenBtn.selApp
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    var app = owOpenBtn.selApp;
                                    if (app && root.openWithTarget) {
                                        root.send({
                                            op: "openWith",
                                            path: root.openWithTarget.path,
                                            exec: app.exec,
                                            desktopId: app.desktopId,
                                            mime: root.openWithMime,
                                            setDefault: root.openWithAlwaysDefault
                                        });
                                        root.openWithOpen = false;
                                    }
                                }
                            }
                        }
                    }

                    // Search bar
                    TextField {
                        id: owSearchField
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: owHeader.bottom
                        anchors.margins: 12
                        height: 32
                        placeholderText: "Search applications…"
                        color: root.textPrimary; placeholderTextColor: root.textMuted
                        font.family: root.fam; font.pixelSize: 12
                        background: Rectangle {
                            color: root.darkMode ? "#1E1E20" : "white"
                            radius: 8; border.width: 1; border.color: owSearchField.activeFocus ? root.accentBlue : root.lineCol
                        }
                        onTextChanged: { root.openWithSearch = text; root.openWithSelectedIdx = 0; }
                    }

                    // Installed apps list
                    ListView {
                        id: owList
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: owSearchField.bottom; anchors.bottom: owFooter.top
                        anchors.margins: 12
                        clip: true
                        spacing: 2
                        model: root.filteredOpenWithApps()
                        delegate: Rectangle {
                            id: owRow
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.openWithSelectedIdx
                            width: owList.width; height: 40; radius: 8
                            color: sel ? root.accentBlue : (owRowH.hovered ? root.pillBg : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24; height: 24
                                    source: modelData.icon ? ("file://" + modelData.icon) : ""
                                    fillMode: Image.PreserveAspectFit; asynchronous: true
                                    visible: modelData.icon !== ""
                                }
                                WGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22; height: 22; kind: "appstore"
                                    color: owRow.sel ? "white" : root.textMuted
                                    visible: modelData.icon === ""
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - (modelData.isDefault ? 95 : 42)
                                    text: modelData.name
                                    color: owRow.sel ? "white" : root.textPrimary
                                    font.family: Fonts.forWeight(owRow.sel ? Font.DemiBold : Font.Normal, root.fam)
                                    font.weight: owRow.sel ? Font.DemiBold : Font.Normal
                                    font.pixelSize: 13; elide: Text.ElideRight
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!modelData.isDefault
                                    text: "Default"
                                    color: owRow.sel ? Qt.rgba(1, 1, 1, 0.85) : root.textMuted
                                    font.family: root.fam; font.pixelSize: 11
                                }
                            }
                            HoverHandler { id: owRowH }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openWithSelectedIdx = owRow.index
                                onDoubleClicked: {
                                    root.openWithSelectedIdx = owRow.index;
                                    if (root.openWithTarget) {
                                        root.send({
                                            op: "openWith",
                                            path: root.openWithTarget.path,
                                            exec: modelData.exec,
                                            desktopId: modelData.desktopId,
                                            mime: root.openWithMime,
                                            setDefault: root.openWithAlwaysDefault
                                        });
                                        root.openWithOpen = false;
                                    }
                                }
                            }
                        }
                        LiquidScrollBar { flick: owList; material: "liquid"; dark: root.darkMode; compact: true; anchors.right: owList.right; anchors.top: owList.top; anchors.bottom: owList.bottom }
                    }

                    // Bottom Bar: "Always use for this file type" toggle
                    Rectangle {
                        id: owFooter
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 46
                        color: "transparent"
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.lineCol }

                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Always use for this file type"
                            color: root.textPrimary; font.family: root.fam; font.pixelSize: 12
                        }

                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 22; radius: 11
                            color: root.openWithAlwaysDefault ? root.accentBlue : (root.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.18))
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Rectangle {
                                x: root.openWithAlwaysDefault ? 20 : 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 9; color: "white"
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openWithAlwaysDefault = !root.openWithAlwaysDefault
                            }
                        }
                    }
                }
            }
            // 7. ENCRYPTED ARCHIVE PASSWORD PROMPT
            Item {
                id: archivePasswordModal
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.archivePasswordOpen ? 1.0 : 0.0
                z: 880
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45)
                    TapHandler { onTapped: root.archivePasswordOpen = false }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 340; height: root.archivePasswordWrong ? 174 : 154; radius: 14
                    color: root.darkMode ? "#252528" : "#F6F6F8"
                    border.width: 1; border.color: root.lineCol
                    scale: root.archivePasswordOpen ? 1.0 : 0.90
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    TapHandler {}

                    GlassSlab {
                        anchors.fill: parent; glass: true
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode; baseColor: root.pillBase; cornerR: 14
                        thickness: 6; strengthMul: 0.22; rim: 0.16; tint: root.darkMode ? 0.55 : 0.78; flatInner: 1
                        z: -1
                    }

                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 10
                        Text {
                            width: parent.width; elide: Text.ElideMiddle
                            text: "Password Required — " + root.folderLabel(root.archivePasswordPath)
                            color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: root.archivePasswordWrong
                            text: "Incorrect password. Please try again."
                            color: "#FF453A"; font.family: root.fam; font.pixelSize: 11
                        }
                        TextField {
                            id: archivePwdField
                            width: parent.width; height: 30
                            echoMode: TextInput.Password
                            placeholderText: "Enter archive password…"
                            color: root.textPrimary; placeholderTextColor: root.textMuted
                            font.family: root.fam; font.pixelSize: 12
                            background: Rectangle { color: root.darkMode ? "#1E1E20" : "white"; radius: 7; border.width: 1; border.color: archivePwdField.activeFocus ? root.accentBlue : root.lineCol }
                            onAccepted: {
                                if (text !== "" && root.archivePasswordPath !== "") {
                                    root.archivePasswordOpen = false;
                                    root.send({ op: "extract", path: root.archivePasswordPath, password: text });
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right; spacing: 8
                            Rectangle {
                                width: 68; height: 28; radius: 7; color: root.pillBg
                                border.width: 1; border.color: root.lineCol
                                Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.archivePasswordOpen = false }
                            }
                            Rectangle {
                                width: 76; height: 28; radius: 7; color: root.accentBlue
                                Text { anchors.centerIn: parent; text: "Extract"; color: "white"; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (archivePwdField.text !== "" && root.archivePasswordPath !== "") {
                                            root.archivePasswordOpen = false;
                                            root.send({ op: "extract", path: root.archivePasswordPath, password: archivePwdField.text });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // 8. COMPRESS OPTIONS MODAL SHEET
            Item {
                id: compressModal
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: root.compressOpen ? 1.0 : 0.0
                z: 890
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45)
                    TapHandler { onTapped: root.compressOpen = false }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 380; height: 274; radius: 16
                    color: root.darkMode ? "#252528" : "#F6F6F8"
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
                    scale: root.compressOpen ? 1.0 : 0.90
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    TapHandler {}

                    GlassSlab {
                        anchors.fill: parent; glass: true
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode; baseColor: root.pillBase; cornerR: 16
                        thickness: 8; strengthMul: 0.22; rim: 0.16; tint: root.darkMode ? 0.55 : 0.78; flatInner: 1
                        z: -1
                    }

                    // Header
                    Item {
                        id: cmpHeader
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: 46
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineCol }

                        Rectangle {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64; height: 28; radius: 8
                            color: cmpCancelH.hovered ? root.pillHoverBg : root.pillBg
                            border.width: 1; border.color: root.lineCol
                            Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                            HoverHandler { id: cmpCancelH }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.compressOpen = false }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.compressPaths.length > 1 ? ("Compress " + root.compressPaths.length + " Items") : "Compress"
                            color: root.textPrimary; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                        }

                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 68; height: 28; radius: 8
                            color: root.accentBlue
                            Text { anchors.centerIn: parent; text: "Create"; color: "white"; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.compressOpen = false;
                                    root.send({
                                        op: "compress",
                                        paths: root.compressPaths,
                                        name: compressNameField.text,
                                        format: root.compressFormat,
                                        password: (root.compressFormat === "zip" || root.compressFormat === "7z") ? compressPwdField.text : ""
                                    });
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: cmpHeader.bottom; anchors.bottom: parent.bottom
                        anchors.margins: 16; spacing: 12

                        // Archive Name
                        Column {
                            width: parent.width; spacing: 5
                            Text { text: "Archive Name"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                            TextField {
                                id: compressNameField
                                width: parent.width; height: 32
                                placeholderText: "Archive"
                                color: root.textPrimary; placeholderTextColor: root.textMuted
                                font.family: root.fam; font.pixelSize: 12
                                background: Rectangle { color: root.darkMode ? "#1E1E20" : "white"; radius: 8; border.width: 1; border.color: compressNameField.activeFocus ? root.accentBlue : root.lineCol }
                            }
                        }

                        // Format Selector
                        Column {
                            width: parent.width; spacing: 5
                            Text { text: "Format"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Row {
                                width: parent.width; spacing: 6
                                Repeater {
                                    model: ["zip", "tar.gz", "tar.xz", "7z"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool sel: root.compressFormat === modelData
                                        width: (parent.width - 18) / 4; height: 28; radius: 7
                                        color: sel ? root.accentBlue : root.pillBg
                                        border.width: 1; border.color: sel ? root.accentBlue : root.lineCol
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "." + modelData
                                            color: sel ? "white" : root.textPrimary
                                            font.family: Fonts.forWeight(sel ? Font.DemiBold : Font.Normal, root.fam)
                                            font.weight: sel ? Font.DemiBold : Font.Normal
                                            font.pixelSize: 12
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.compressFormat = modelData }
                                    }
                                }
                            }
                        }

                        // Optional Password (for .zip / .7z)
                        Column {
                            width: parent.width; spacing: 5
                            opacity: (root.compressFormat === "zip" || root.compressFormat === "7z") ? 1.0 : 0.45
                            Text {
                                text: (root.compressFormat === "zip" || root.compressFormat === "7z") ? "Password (Optional)" : "Password (only available for .zip / .7z)"
                                color: root.textMuted; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                            TextField {
                                id: compressPwdField
                                width: parent.width; height: 32
                                enabled: root.compressFormat === "zip" || root.compressFormat === "7z"
                                echoMode: TextInput.Password
                                placeholderText: "Leave empty for no password"
                                color: root.textPrimary; placeholderTextColor: root.textMuted
                                font.family: root.fam; font.pixelSize: 12
                                background: Rectangle { color: root.darkMode ? "#1E1E20" : "white"; radius: 8; border.width: 1; border.color: compressPwdField.activeFocus ? root.accentBlue : root.lineCol }
                            }
                        }
                    }
                }
            }
        }

        // CONTEXT MENUS
        FinderMenu {
            id: itemMenu
            menuWidth: 215
            FinderMenuItem { text: "Open"; dark: root.darkMode; fam: root.fam; onTriggered: if (root.contextItem) root.activateItem(root.contextItem) }
            FinderMenuItem {
                visible: !!root.contextItem && !root.contextItem.isDir
                text: "Open With…"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.contextItem) root.openWithFor(root.contextItem)
            }
            FinderMenuItem { text: "Quick Look"; dark: root.darkMode; fam: root.fam; onTriggered: root.quickLookOpen = true }
            FinderMenuItem { text: "Get Info"; dark: root.darkMode; fam: root.fam; onTriggered: root.getInfoOpen = true }
            MenuSeparator {}
            FinderMenuItem {
                text: "Rename"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.contextItem) {
                    root.renameTargetPath = root.contextItem.path;
                    root.renameTargetName = root.contextItem.name;
                    renameModal.open();
                }
            }
            FinderMenuItem {
                visible: root.selectedPaths.length > 1
                text: "Rename " + root.selectedPaths.length + " Items…"
                dark: root.darkMode; fam: root.fam
                onTriggered: bulkRenameModal.open()
            }
            FinderMenuItem { text: "Duplicate"; dark: root.darkMode; fam: root.fam; onTriggered: if (root.contextItem) root.send({ op: "duplicate", path: root.contextItem.path }) }
            FinderMenuItem {
                visible: !!root.contextItem && (root.selectedPaths.length > 1 || !root.isArchiveName(root.contextItem.name))
                text: root.selectedPaths.length > 1 ? ("Compress " + root.selectedPaths.length + " Items…") : "Compress…"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.selectedPaths.length > 0) root.openCompressFor(root.selectedPaths)
            }
            FinderMenuItem {
                visible: !!root.contextItem && root.isArchiveName(root.contextItem.name)
                text: "Extract Here"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.contextItem) root.send({ op: "extract", path: root.contextItem.path })
            }
            FinderMenuItem { text: "Copy"; dark: root.darkMode; fam: root.fam; onTriggered: root.copySelection("copy") }
            FinderMenuItem { text: "Copy Path"; dark: root.darkMode; fam: root.fam; onTriggered: if (root.contextItem) Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", root.contextItem.path]) }
            MenuSeparator {}
            // Quick Tag Dots Row inside Menu
            Item {
                implicitWidth: 203; implicitHeight: 34
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Repeater {
                        model: root.sidebarTags
                        delegate: Rectangle {
                            required property var modelData
                            width: 16; height: 16; radius: 8
                            color: modelData.color
                            border.width: 1.5; border.color: Qt.rgba(1, 1, 1, 0.35)
                            scale: tagDotH.hovered ? 1.2 : 1.0
                            Behavior on scale { NumberAnimation { duration: 110 } }
                            HoverHandler { id: tagDotH }
                            MacToolTip { visible: tagDotH.hovered; text: "Tag: " + modelData.name }
                            TapHandler {
                                onTapped: {
                                    root.send({ op: "setTag", paths: root.selectedPaths, tag: modelData.name, toggle: true });
                                    if (root.contextItem && root.contextItem.isDir) {
                                        root.send({ op: "setFolderColor", paths: root.selectedPaths, color: modelData.color });
                                    }
                                    itemMenu.close();
                                }
                            }
                        }
                    }
                }
            }
            MenuSeparator {}
            FinderMenuItem { text: "Move to Trash"; dark: root.darkMode; fam: root.fam; onTriggered: if (root.selectedPaths.length > 0) root.send({ op: "trash", paths: root.selectedPaths }) }
        }

        FinderMenu {
            id: bgMenu
            menuWidth: 205
            FinderMenuItem { text: "New Folder"; dark: root.darkMode; fam: root.fam; onTriggered: root.send({ op: "mkdir", parent: root.currentPath, name: "untitled folder" }) }
            FinderMenuItem { text: "Paste Item"; enabled: root.clipboardPaths.length > 0; dark: root.darkMode; fam: root.fam; onTriggered: root.pasteInto(root.currentPath) }
            MenuSeparator {}
            FinderMenuItem { text: (root.showPreview ? "✓ " : "    ") + "Show Preview"; dark: root.darkMode; fam: root.fam; onTriggered: root.showPreview = !root.showPreview }
            FinderMenuItem { text: (root.showPathBar ? "✓ " : "    ") + "Show Path Bar"; dark: root.darkMode; fam: root.fam; onTriggered: root.showPathBar = !root.showPathBar }
            FinderMenuItem { text: "Go to Folder…"; dark: root.darkMode; fam: root.fam; onTriggered: goToDialog.open() }
        }

        FinderMenu {
            id: sidebarItemMenu
            menuWidth: 200
            FinderMenuItem {
                text: "Open in New Tab"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeSidebarItem) root.addTab(root.activeSidebarItem.path)
            }
            FinderMenuItem {
                text: "Open in New Window"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeSidebarItem) root.openInNewProcess(root.activeSidebarItem.path)
            }
            MenuSeparator {}
            FinderMenuItem {
                text: "Remove from Sidebar"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeSidebarItem) root.send({ op: "removeSidebarItem", path: root.activeSidebarItem.path, id: root.activeSidebarItem.id })
            }
            FinderMenuItem {
                text: "Move Up"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeSidebarItem) root.send({ op: "moveSidebarItem", categoryId: root.activeSidebarCatId, path: root.activeSidebarItem.path, dir: -1 })
            }
            FinderMenuItem {
                text: "Move Down"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeSidebarItem) root.send({ op: "moveSidebarItem", categoryId: root.activeSidebarCatId, path: root.activeSidebarItem.path, dir: 1 })
            }
            MenuSeparator {}
            FinderMenuItem {
                text: "Add Current Folder"
                dark: root.darkMode; fam: root.fam
                onTriggered: root.send({ op: "addSidebarItem", categoryId: root.activeSidebarCatId, label: root.folderLabel(root.currentPath), path: root.currentPath, glyph: "folder" })
            }
            FinderMenuItem {
                text: "New Section…"
                dark: root.darkMode; fam: root.fam
                onTriggered: newCategoryModal.open()
            }
        }

        FinderMenu {
            id: categoryMenu
            menuWidth: 195
            FinderMenuItem {
                text: "Add Current Folder"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeCategoryTarget) root.send({ op: "addSidebarItem", categoryId: root.activeCategoryTarget.id, label: root.folderLabel(root.currentPath), path: root.currentPath, glyph: "folder" })
            }
            FinderMenuItem {
                text: "Move Section Up"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeCategoryTarget) root.send({ op: "moveSidebarCategory", categoryId: root.activeCategoryTarget.id, dir: -1 })
            }
            FinderMenuItem {
                text: "Move Section Down"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeCategoryTarget) root.send({ op: "moveSidebarCategory", categoryId: root.activeCategoryTarget.id, dir: 1 })
            }
            FinderMenuItem {
                visible: !!root.activeCategoryTarget && root.activeCategoryTarget.isCustom
                text: "Remove Section"
                dark: root.darkMode; fam: root.fam
                onTriggered: if (root.activeCategoryTarget) root.send({ op: "removeSidebarCategory", categoryId: root.activeCategoryTarget.id })
            }
            MenuSeparator {}
            FinderMenuItem {
                text: "New Section…"
                dark: root.darkMode; fam: root.fam
                onTriggered: newCategoryModal.open()
            }
            FinderMenuItem {
                text: "Reset Sidebar to Defaults"
                dark: root.darkMode; fam: root.fam
                onTriggered: root.send({ op: "resetSidebar" })
            }
        }

        // DIALOGS: Rename, Go To Folder
        Item {
            id: renameModal
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: 0.0
            z: 860
            function open() {
                renameField.text = root.renameTargetName;
                opacity = 1.0;
                renameField.forceActiveFocus();
                renameField.selectAll();
            }
            function close() { opacity = 0.0; }
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: renameModal.close() }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 340; height: 158; radius: 14
                color: root.darkMode ? "#262629" : "#F6F6F8"
                border.width: 1; border.color: root.lineCol
                scale: renameModal.opacity > 0.5 ? 1.0 : 0.95
                Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent; anchors.margins: 18; spacing: 12
                    Column {
                        width: parent.width; spacing: 2
                        Text {
                            text: "Rename"
                            color: root.textPrimary
                            font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: root.renameTargetName
                            color: root.textMuted
                            font.family: root.fam
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }

                    TextField {
                        id: renameField
                        width: parent.width; height: 34
                        leftPadding: 10; rightPadding: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.textPrimary
                        placeholderText: "Item name"
                        placeholderTextColor: root.textMuted
                        selectionColor: root.accentBlue
                        selectedTextColor: "white"
                        font.family: root.fam; font.pixelSize: 13
                        background: Rectangle {
                            color: root.darkMode ? "#1B1B1E" : "white"
                            radius: 8
                            border.width: renameField.activeFocus ? 1.5 : 1
                            border.color: renameField.activeFocus ? root.accentBlue : root.lineCol
                        }
                        Keys.onEscapePressed: renameModal.close()
                        onAccepted: {
                            var nm = text.trim();
                            if (nm !== "" && nm !== root.renameTargetName) {
                                root.send({ op: "rename", path: root.renameTargetPath, newName: nm });
                            }
                            renameModal.close();
                        }
                    }

                    Row {
                        anchors.right: parent.right; spacing: 8
                        Rectangle {
                            width: 74; height: 30; radius: 8
                            color: renameCancelMa.containsMouse ? root.pillHoverBg : root.pillBg
                            border.width: 1; border.color: root.lineCol
                            Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                            MouseArea {
                                id: renameCancelMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: renameModal.close()
                            }
                        }
                        Rectangle {
                            width: 82; height: 30; radius: 8
                            readonly property bool canSubmit: renameField.text.trim() !== ""
                            color: canSubmit ? root.accentBlue : root.pillBg
                            opacity: canSubmit ? (renameOkMa.containsMouse ? 0.90 : 1.0) : 0.45
                            Text {
                                anchors.centerIn: parent; text: "Rename"
                                color: parent.canSubmit ? "white" : root.textMuted
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: renameOkMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: parent.canSubmit ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    var nm = renameField.text.trim();
                                    if (nm !== "") {
                                        if (nm !== root.renameTargetName) root.send({ op: "rename", path: root.renameTargetPath, newName: nm });
                                        renameModal.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // BULK RENAME MODAL
        Item {
            id: bulkRenameModal
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: 0.0
            z: 865

            property var targetPaths: []
            property string bulkMode: "template"  // "template" | "findReplace"
            property string templateStr: "{name}_{n}"
            property int startNum: 1
            property int padding: 3
            property string findStr: ""
            property string replaceStr: ""
            property bool caseSensitive: true

            function open() {
                targetPaths = root.selectedPaths.slice();
                if (targetPaths.length < 2) return;
                bulkMode = "template";
                templateStr = "{name}_{n}";
                startNum = 1;
                padding = 3;
                findStr = "";
                replaceStr = "";
                caseSensitive = true;
                opacity = 1.0;
                brTemplateField.forceActiveFocus();
            }
            function close() { opacity = 0.0; }

            function previewNames() {
                var out = [];
                for (var i = 0; i < targetPaths.length; i++) {
                    var parts = targetPaths[i].split("/");
                    var oldName = parts[parts.length - 1];
                    var newName = "";
                    if (bulkMode === "template") {
                        var stem = oldName;
                        var ext = "";
                        var dotIdx = oldName.lastIndexOf(".");
                        if (dotIdx > 0) { stem = oldName.substring(0, dotIdx); ext = oldName.substring(dotIdx); }
                        var counter = (startNum + i).toString();
                        while (counter.length < padding) counter = "0" + counter;
                        newName = templateStr.replace("{name}", stem).replace("{n}", counter).replace("{ext}", ext.substring(1));
                        if (ext && newName.indexOf(ext) < 0 && templateStr.indexOf("{ext}") < 0) newName += ext;
                    } else {
                        if (!findStr) { out.push({ old: oldName, new: oldName }); continue; }
                        if (caseSensitive) {
                            newName = oldName.split(findStr).join(replaceStr);
                        } else {
                            var result = "";
                            var j = 0;
                            var lf = findStr.toLowerCase();
                            while (j < oldName.length) {
                                if (oldName.substring(j, j + findStr.length).toLowerCase() === lf) {
                                    result += replaceStr;
                                    j += findStr.length;
                                } else {
                                    result += oldName[j];
                                    j++;
                                }
                            }
                            newName = result;
                        }
                    }
                    out.push({ old: oldName, new: newName || oldName });
                }
                return out;
            }

            function execute() {
                if (bulkMode === "template") {
                    root.send({ op: "bulkRename", mode: "template", paths: targetPaths, template: templateStr, startNumber: startNum, padding: padding });
                } else {
                    root.send({ op: "bulkRename", mode: "findReplace", paths: targetPaths, find: findStr, replace: replaceStr, caseSensitive: caseSensitive });
                }
                close();
            }

            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: bulkRenameModal.close() }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 480; height: 420; radius: 14
                color: root.darkMode ? "#262629" : "#F4F4F6"
                border.width: 1; border.color: root.lineCol
                scale: bulkRenameModal.opacity > 0.5 ? 1.0 : 0.95
                Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent; anchors.margins: 18; spacing: 12

                    // Header
                    Text {
                        text: "Rename " + bulkRenameModal.targetPaths.length + " Items"
                        color: root.textPrimary
                        font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                        font.pixelSize: 15; font.weight: Font.DemiBold
                    }

                    // Mode Tabs
                    Rectangle {
                        width: parent.width; height: 32; radius: 8
                        color: root.pillBg
                        border.width: 1; border.color: root.lineCol

                        Row {
                            anchors.fill: parent; anchors.margins: 2

                            Repeater {
                                model: [{ id: "template", label: "Template" }, { id: "findReplace", label: "Find & Replace" }]
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool act: bulkRenameModal.bulkMode === modelData.id
                                    width: parent.width / 2; height: 28; radius: 6
                                    color: act ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09)) : "transparent"
                                    border.width: act ? 1 : 0
                                    border.color: act ? root.lineCol : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: act ? root.textPrimary : root.textMuted
                                        font.family: Fonts.forWeight(act ? Font.DemiBold : Font.Normal, root.fam)
                                        font.pixelSize: 12; font.weight: act ? Font.DemiBold : Font.Normal
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            bulkRenameModal.bulkMode = modelData.id;
                                            if (modelData.id === "template") brTemplateField.forceActiveFocus();
                                            else brFindField.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Template Mode Fields
                    Column {
                        visible: bulkRenameModal.bulkMode === "template"
                        width: parent.width; spacing: 8

                        Column {
                            width: parent.width; spacing: 2
                            Text { text: "Template"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                            TextField {
                                id: brTemplateField
                                width: parent.width; height: 32; leftPadding: 10; rightPadding: 10
                                verticalAlignment: TextInput.AlignVCenter
                                text: bulkRenameModal.templateStr
                                color: root.textPrimary; placeholderTextColor: root.textMuted
                                selectionColor: root.accentBlue; selectedTextColor: "white"
                                font.family: root.fam; font.pixelSize: 13
                                background: Rectangle { color: root.darkMode ? "#1B1B1E" : "white"; radius: 8; border.width: brTemplateField.activeFocus ? 1.5 : 1; border.color: brTemplateField.activeFocus ? root.accentBlue : root.lineCol }
                                onTextChanged: bulkRenameModal.templateStr = text
                                Keys.onEscapePressed: bulkRenameModal.close()
                            }
                            Text {
                                text: "Placeholders: {name} = original, {n} = counter, {ext} = extension"
                                color: root.textMuted; font.family: root.fam; font.pixelSize: 10
                            }
                        }

                        Row {
                            spacing: 12
                            Column {
                                spacing: 2
                                Text { text: "Start #"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                                TextField {
                                    width: 70; height: 32; leftPadding: 8; rightPadding: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: bulkRenameModal.startNum.toString()
                                    color: root.textPrimary; font.family: root.fam; font.pixelSize: 13
                                    validator: IntValidator { bottom: 0; top: 99999 }
                                    selectionColor: root.accentBlue; selectedTextColor: "white"
                                    background: Rectangle { color: root.darkMode ? "#1B1B1E" : "white"; radius: 8; border.width: 1; border.color: activeFocus ? root.accentBlue : root.lineCol }
                                    onTextChanged: { var v = parseInt(text); if (!isNaN(v)) bulkRenameModal.startNum = v; }
                                }
                            }
                            Column {
                                spacing: 2
                                Text { text: "Padding"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                                TextField {
                                    width: 70; height: 32; leftPadding: 8; rightPadding: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: bulkRenameModal.padding.toString()
                                    color: root.textPrimary; font.family: root.fam; font.pixelSize: 13
                                    validator: IntValidator { bottom: 1; top: 8 }
                                    selectionColor: root.accentBlue; selectedTextColor: "white"
                                    background: Rectangle { color: root.darkMode ? "#1B1B1E" : "white"; radius: 8; border.width: 1; border.color: activeFocus ? root.accentBlue : root.lineCol }
                                    onTextChanged: { var v = parseInt(text); if (!isNaN(v) && v >= 1) bulkRenameModal.padding = v; }
                                }
                            }
                        }
                    }

                    // Find & Replace Mode Fields
                    Column {
                        visible: bulkRenameModal.bulkMode === "findReplace"
                        width: parent.width; spacing: 8

                        Column {
                            width: parent.width; spacing: 2
                            Text { text: "Find"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                            TextField {
                                id: brFindField
                                width: parent.width; height: 32; leftPadding: 10; rightPadding: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.textPrimary; placeholderText: "Text to find…"; placeholderTextColor: root.textMuted
                                selectionColor: root.accentBlue; selectedTextColor: "white"
                                font.family: root.fam; font.pixelSize: 13
                                background: Rectangle { color: root.darkMode ? "#1B1B1E" : "white"; radius: 8; border.width: brFindField.activeFocus ? 1.5 : 1; border.color: brFindField.activeFocus ? root.accentBlue : root.lineCol }
                                onTextChanged: bulkRenameModal.findStr = text
                                Keys.onEscapePressed: bulkRenameModal.close()
                            }
                        }
                        Column {
                            width: parent.width; spacing: 2
                            Text { text: "Replace with"; color: root.textMuted; font.family: root.fam; font.pixelSize: 11 }
                            TextField {
                                id: brReplaceField
                                width: parent.width; height: 32; leftPadding: 10; rightPadding: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.textPrimary; placeholderText: "Replacement text…"; placeholderTextColor: root.textMuted
                                selectionColor: root.accentBlue; selectedTextColor: "white"
                                font.family: root.fam; font.pixelSize: 13
                                background: Rectangle { color: root.darkMode ? "#1B1B1E" : "white"; radius: 8; border.width: brReplaceField.activeFocus ? 1.5 : 1; border.color: brReplaceField.activeFocus ? root.accentBlue : root.lineCol }
                                onTextChanged: bulkRenameModal.replaceStr = text
                                Keys.onEscapePressed: bulkRenameModal.close()
                            }
                        }

                        // Case-sensitive toggle
                        Row {
                            spacing: 6
                            Rectangle {
                                width: 18; height: 18; radius: 4
                                color: bulkRenameModal.caseSensitive ? root.accentBlue : (root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                border.width: bulkRenameModal.caseSensitive ? 0 : 1
                                border.color: root.lineCol
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.centerIn: parent; text: "✓"; color: "white"
                                    font.pixelSize: 11; font.weight: Font.Bold
                                    visible: bulkRenameModal.caseSensitive
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: bulkRenameModal.caseSensitive = !bulkRenameModal.caseSensitive
                                }
                            }
                            Text { text: "Case sensitive"; color: root.textMuted; font.family: root.fam; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }

                    // Preview
                    Rectangle {
                        width: parent.width; height: 110; radius: 8
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                        border.width: 1; border.color: root.lineCol
                        clip: true

                        Column {
                            anchors.fill: parent; anchors.margins: 1
                            Text {
                                x: 8; height: 22; verticalAlignment: Text.AlignVCenter
                                text: "Preview"; color: root.textMuted
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                font.pixelSize: 10; font.weight: Font.DemiBold
                            }
                            ListView {
                                width: parent.width; height: parent.height - 22
                                clip: true
                                model: bulkRenameModal.opacity > 0.5 ? bulkRenameModal.previewNames() : []
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width; height: 20
                                    Row {
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                        Text {
                                            width: (parent.width - 24) / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.old; color: root.textMuted
                                            font.family: root.fam; font.pixelSize: 11
                                            elide: Text.ElideMiddle
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "→"; color: root.textMuted; font.pixelSize: 11
                                        }
                                        Text {
                                            width: (parent.width - 24) / 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.new
                                            color: modelData.old !== modelData.new ? root.accentBlue : root.textMuted
                                            font.family: root.fam; font.pixelSize: 11
                                            font.weight: modelData.old !== modelData.new ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Buttons
                    Row {
                        anchors.right: parent.right; spacing: 8
                        Rectangle {
                            width: 74; height: 30; radius: 8
                            color: brCancelMa.containsMouse ? root.pillHoverBg : root.pillBg
                            border.width: 1; border.color: root.lineCol
                            Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                            MouseArea {
                                id: brCancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: bulkRenameModal.close()
                            }
                        }
                        Rectangle {
                            width: 90; height: 30; radius: 8
                            color: root.accentBlue
                            opacity: brRenameMa.containsMouse ? 0.90 : 1.0
                            Text {
                                anchors.centerIn: parent; text: "Rename All"
                                color: "white"; font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: brRenameMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: bulkRenameModal.execute()
                            }
                        }
                    }
                }
            }
        }

        Dialog {
            id: goToDialog
            title: "Go to the folder:"; width: 380; padding: 16; anchors.centerIn: parent; modal: true
            background: Rectangle { color: root.darkMode ? "#29292B" : "#F6F6F8"; radius: 14; border.width: 1; border.color: root.lineCol }
            contentItem: TextField {
                id: goToField; placeholderText: "~/Projects or /etc"; color: root.textPrimary; placeholderTextColor: root.textMuted
                font.family: root.fam; font.pixelSize: 13
                background: Rectangle { color: root.darkMode ? "#1E1E20" : "white"; radius: 8; border.width: 1; border.color: root.lineCol }
                onAccepted: { root.navigateTo(text.replace(/^~/, root.home), true); goToDialog.close(); }
            }
            footer: Row {
                spacing: 8; layoutDirection: Qt.RightToLeft
                Rectangle {
                    width: 64; height: 30; radius: 8; color: root.accentBlue
                    Text { anchors.centerIn: parent; text: "Go"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                    TapHandler { onTapped: { root.navigateTo(goToField.text.replace(/^~/, root.home), true); goToDialog.close(); } }
                }
                Rectangle {
                    width: 72; height: 30; radius: 8; color: root.lineCol
                    Text { anchors.centerIn: parent; text: "Cancel"; color: root.textPrimary; font.family: root.fam; font.pixelSize: 12 }
                    TapHandler { onTapped: goToDialog.close() }
                }
            }
            onOpened: { goToField.text = root.currentPath; goToField.forceActiveFocus(); goToField.selectAll(); }
        }
    }

    // --- INLINE HELPER COMPONENTS ---
    component MacToolTip: ToolTip {
        id: tt
        delay: 350
        timeout: 4000
        contentItem: Text {
            text: tt.text
            font.family: root.fam
            font.pixelSize: 11
            color: root.darkMode ? "#F5F7FF" : "#1D1D1F"
        }
        background: Rectangle {
            color: root.darkMode ? Qt.rgba(0.12, 0.12, 0.14, 0.94) : Qt.rgba(0.96, 0.96, 0.98, 0.96)
            radius: 6
            border.width: 1
            border.color: root.lineCol
        }
    }

    component SidebarRow: Rectangle {
        id: sRow
        property string label: ""
        property string glyph: "folder"
        property bool active: false
        property bool dropTarget: false
        property bool hovered: false
        property bool pressed: false
        property bool dark: true
        property string fam: "Open Runde"
        property color textCol: "white"

        height: 28; radius: 6
        // macOS authentic active selection: solid blue pill when active!
        color: active ? root.accentBlue
                      : (dropTarget ? Qt.rgba(root.accentBlue.r, root.accentBlue.g, root.accentBlue.b, 0.22)
                                    : (sRow.hovered ? (dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)) : "transparent"))
        border.width: dropTarget && !active ? 1.5 : 0
        border.color: dropTarget && !active ? root.accentBlue : "transparent"
        scale: sRow.pressed ? 0.985 : 1
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }

        Row {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
            Image {
                anchors.verticalCenter: parent.verticalCenter
                visible: sRow.glyph === "airdrop"
                width: 15; height: 15
                opacity: sRow.active ? 1.0 : 0.90
                source: Qt.resolvedUrl("../assets/airdrop-symbolic.svg")
                sourceSize: Qt.size(30, 30)
                fillMode: Image.PreserveAspectFit
                smooth: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1
                    colorizationColor: sRow.active ? "white" : root.accentBlue
                }
            }
            WGlyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: sRow.glyph !== "airdrop"
                width: 15; height: 15
                kind: glyph === "apps" ? "appstore"
                    : glyph === "desktop" ? "monitor"
                    : glyph === "downloads" ? "download"
                    : glyph === "music" ? "note"
                    : glyph === "usb" ? "external"
                    : glyph === "network" ? "ethernet"
                    : glyph === "shared" ? "sharedFolder"
                    : glyph
                color: sRow.active ? "white" : root.accentBlue
                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24
                text: sRow.label
                color: sRow.active ? "white" : (dark ? "#F5F7FF" : "#1D1D1F")
                font.family: Fonts.forWeight(sRow.active ? Font.DemiBold : Font.Normal, sRow.fam)
                font.pixelSize: 13
                font.weight: sRow.active ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
    }

    component FinderMenu: Menu {
        id: fm
        property int menuWidth: 210
        topPadding: 6; bottomPadding: 6; leftPadding: 6; rightPadding: 6
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 110; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; to: 0.98; duration: 110; easing.type: Easing.OutCubic }
            }
        }
        background: Rectangle {
            implicitWidth: fm.menuWidth
            radius: 12
            color: root.darkMode ? Qt.rgba(0.13, 0.13, 0.15, 0.86) : Qt.rgba(0.94, 0.94, 0.96, 0.98)
            border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.20)
            GlassSlab {
                anchors.fill: parent
                glass: true
                shaderUrl: root.glassShaderUrl
                dark: root.darkMode
                baseColor: root.darkMode ? "#252528" : "#F2F3F7"
                cornerR: 12
                thickness: 8
                strengthMul: 0.32
                rim: 0.16
                tint: root.darkMode ? 0.42 : 0.78
                flatInner: 1
            }
        }
    }

    function openInNewProcess(path) {
        var args = ["qs", "-p", home + "/.config/quickshell/shell27/Finder.qml"];
        if (path && path !== "") args.push("--", path);
        Quickshell.execDetached(args);
    }

    component FinderMenuItem: MenuItem {
        id: mi
        property bool dark: true
        property string fam: "Open Runde"
        property string accentDot: ""
        implicitWidth: 196; implicitHeight: visible ? 30 : 0; height: visible ? 30 : 0; hoverEnabled: true
        contentItem: Text {
            x: 10; width: parent.width - 20
            text: mi.text
            color: mi.accentDot !== "" ? mi.accentDot : (dark ? "#F5F7FF" : "#1D1D1F")
            font.family: fam; font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: mi.highlighted ? "#0A84FF" : "transparent"
        }
    }

    component ListColHead: Item {
        id: lch
        property string label: ""
        property string field: ""
        property string sortBy: "name"
        property bool sortAsc: true
        property color textCol: "gray"
        property string fam: "Open Runde"
        property bool alignRight: false
        property int leftPad: 0
        signal clicked()
        height: 28
        Row {
            anchors.fill: parent; anchors.leftMargin: leftPad; anchors.rightMargin: 6
            spacing: 5
            layoutDirection: alignRight ? Qt.RightToLeft : Qt.LeftToRight
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: textCol; font.family: fam; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            Canvas {
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8
                visible: lch.sortBy === lch.field
                rotation: lch.sortAsc ? 0 : 180
                Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                property color ink: lch.textCol
                onInkChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = ink; ctx.lineWidth = 1.35;
                    ctx.lineCap = "round"; ctx.lineJoin = "round";
                    ctx.beginPath(); ctx.moveTo(1.5, 5.2); ctx.lineTo(4.0, 2.5); ctx.lineTo(6.5, 5.2); ctx.stroke();
                }
            }
        }
        TapHandler { onTapped: clicked() }
    }

    component PreviewInspector: Item {
        property var items: []
        property string previewText: ""
        property bool dark: true
        property string fam: "Open Runde"
        property color textPrimary: "white"
        property color textMuted: "gray"
        property color lineCol: "gray"
        signal tagClicked(string tag)
        signal copyPath(string path)

        readonly property var single: items.length === 1 ? items[0] : null
        readonly property bool multi: items.length > 1

        Flickable {
            anchors.fill: parent; anchors.margins: 14
            contentHeight: inspCol.implicitHeight + 16; clip: true
            Column {
                id: inspCol
                width: parent.width; spacing: 12

                // Empty Selection: Rich Folder Overview
                Column {
                    width: parent.width; spacing: 10
                    visible: items.length === 0
                    Item {
                        width: parent.width; height: 96
                        WGlyph {
                            anchors.centerIn: parent
                            width: 56; height: 56
                            kind: root.currentPath === "finder://trash" ? "trash"
                                : root.currentPath === "finder://airdrop" ? "airdrop"
                                : "folder"
                            color: root.accentBlue
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WrapAnywhere
                        text: root.folderLabel(root.currentPath)
                        color: textPrimary; font.family: Fonts.forWeight(Font.DemiBold, fam); font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: {
                            var dirs = 0, files = 0;
                            for (var i = 0; i < root.items.length; i++) {
                                if (root.items[i].isDir) dirs++;
                                else files++;
                            }
                            return root.items.length + " items  (" + dirs + " folders, " + files + " files)";
                        }
                        color: textMuted; font.family: fam; font.pixelSize: 12; wrapMode: Text.Wrap
                    }
                    Text {
                        visible: root.diskFreeText !== ""
                        width: parent.width
                        text: root.diskFreeText
                        color: textMuted; font.family: fam; font.pixelSize: 11
                    }
                    Rectangle { width: parent.width; height: 1; color: lineCol }
                    Text {
                        text: "Location"
                        color: textPrimary; font.family: Fonts.forWeight(Font.DemiBold, fam); font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: root.currentPath
                        color: textMuted; font.family: fam; font.pixelSize: 11; elide: Text.ElideMiddle
                    }
                    Rectangle {
                        id: inspCopyDirBtn
                        width: parent.width; height: 28; radius: 8
                        property bool copied: false
                        scale: inspCopyDirMa.pressed ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                        color: copied ? root.accentBlue
                             : (inspCopyDirHover.hovered ? (dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                                                         : (dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)))
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Timer { id: copiedDirTimer; interval: 1400; onTriggered: inspCopyDirBtn.copied = false }
                        Text {
                            anchors.centerIn: parent
                            text: inspCopyDirBtn.copied ? "Copied!" : "Copy Folder Path"
                            color: inspCopyDirBtn.copied ? "white" : textPrimary
                            font.family: Fonts.forWeight(inspCopyDirBtn.copied ? Font.DemiBold : Font.Normal, fam)
                            font.weight: inspCopyDirBtn.copied ? Font.DemiBold : Font.Normal
                            font.pixelSize: 12
                        }
                        HoverHandler { id: inspCopyDirHover }
                        MouseArea {
                            id: inspCopyDirMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                copyPath(root.currentPath);
                                inspCopyDirBtn.copied = true;
                                copiedDirTimer.restart();
                            }
                        }
                    }
                }

                // Preview Stage (Single vs Stacked Multi-Select like Finder!)
                Item {
                    width: parent.width; height: 145
                    visible: items.length > 0

                    // Stacked cards when multi-selected
                    Repeater {
                        model: multi ? Math.min(3, items.length) : 0
                        delegate: Image {
                            required property int index
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: (index - 1) * 10
                            anchors.verticalCenterOffset: (index - 1) * -6
                            rotation: (index - 1) * 5
                            width: 96; height: 96
                            source: items[index] ? ("file://" + (items[index].thumb || items[index].icon)) : ""
                            fillMode: Image.PreserveAspectFit; asynchronous: true
                        }
                    }

                    // Single preview
                    Image {
                        anchors.centerIn: parent
                        visible: !!single && (single.thumb !== "" || single.icon !== "")
                        width: parent.width - 16; height: 136
                        source: single ? ("file://" + (single.thumb || single.icon)) : ""
                        fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                    }
                }

                Text {
                    visible: items.length > 0
                    width: parent.width; wrapMode: Text.WrapAnywhere
                    text: multi ? (items.length + " items") : (single ? single.displayName : "")
                    color: textPrimary; font.family: Fonts.forWeight(Font.DemiBold, fam); font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    visible: items.length > 0
                    text: multi
                        ? ("Total — " + root.formatBytes(root.totalSelectedBytes()))
                        : (single.kind + " — " + (single.isDir ? single.sizeText : root.formatBytes(single.size)))
                    color: textMuted; font.family: fam; font.pixelSize: 12
                }

                Rectangle { width: parent.width; height: 1; color: lineCol; visible: !!single }

                // Information rows
                Column {
                    width: parent.width; spacing: 6; visible: !!single
                    Text { text: "Information"; color: textPrimary; font.family: Fonts.forWeight(Font.DemiBold, fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: "Created:  " + (single ? root.formatDate(single.ctime) : ""); color: textMuted; font.family: fam; font.pixelSize: 11; elide: Text.ElideRight }
                    Text { width: parent.width; text: "Modified:  " + (single ? root.formatDate(single.mtime) : ""); color: textMuted; font.family: fam; font.pixelSize: 11; elide: Text.ElideRight }
                }

                // Interactive Tags (always visible when single item is selected)
                Column {
                    width: parent.width; spacing: 8; visible: !!single
                    Text { text: "Tags"; color: textPrimary; font.family: Fonts.forWeight(Font.DemiBold, fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                    Row {
                        spacing: 7
                        Repeater {
                            model: root.sidebarTags
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool hasTag: !!single && single.tags && single.tags.indexOf(modelData.name) >= 0
                                width: 18; height: 18; radius: 9
                                color: modelData.color
                                border.width: hasTag ? 2 : 1
                                border.color: hasTag ? (dark ? "white" : "#1D1D1F") : Qt.rgba(0, 0, 0, 0.2)
                                scale: hasTag ? 1.15 : (inspTagH.hovered ? 1.1 : 1.0)
                                opacity: hasTag ? 1.0 : 0.72
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                                HoverHandler { id: inspTagH }
                                MacToolTip { visible: inspTagH.hovered; text: (hasTag ? "Remove " : "Add ") + modelData.name + " Tag" }
                                TapHandler {
                                    onTapped: {
                                        if (single) {
                                            root.send({ op: "setTag", paths: [single.path], tag: modelData.name, toggle: true });
                                            if (single.isDir) {
                                                root.send({ op: "setFolderColor", paths: [single.path], color: hasTag ? "" : modelData.color });
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Flow {
                        width: parent.width; spacing: 6; visible: !!single && single.tags && single.tags.length > 0
                        Repeater {
                            model: single ? (single.tags || []) : []
                            delegate: Rectangle {
                                required property string modelData
                                width: tagChipRow.implicitWidth + 14; height: 22; radius: 11
                                color: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
                                Row {
                                    id: tagChipRow; anchors.centerIn: parent; spacing: 5
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: root.tagColor(modelData) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; color: textPrimary; font.family: fam; font.pixelSize: 11 }
                                }
                                TapHandler { onTapped: tagClicked(modelData) }
                            }
                        }
                    }
                }

                // Quick Copy Path Button
                Rectangle {
                    id: inspCopyBtn
                    visible: !!single
                    width: parent.width; height: 28; radius: 8
                    property bool copied: false
                    scale: inspCopyMa.pressed ? 0.96 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    color: copied ? root.accentBlue
                         : (inspCopyHover.hovered ? (dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09))
                                                  : (dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)))
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Timer { id: copiedTimer; interval: 1400; onTriggered: inspCopyBtn.copied = false }
                    Text {
                        anchors.centerIn: parent
                        text: inspCopyBtn.copied ? "Copied!" : "Copy Path"
                        color: inspCopyBtn.copied ? "white" : textPrimary
                        font.family: Fonts.forWeight(inspCopyBtn.copied ? Font.DemiBold : Font.Normal, fam)
                        font.weight: inspCopyBtn.copied ? Font.DemiBold : Font.Normal
                        font.pixelSize: 12
                    }
                    HoverHandler { id: inspCopyHover }
                    MouseArea {
                        id: inspCopyMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (single) {
                                copyPath(single.path);
                                inspCopyBtn.copied = true;
                                copiedTimer.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
