import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "hancore.voxtype-enhance"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property string configTool: Qt.resolvedUrl("scripts/voxtype-config.py").toString().replace("file://", "")
    property bool loading: false
    property real downloadProgress: -1
    property string pendingAction: ""
    property string statusText: ""
    property string engine: "sensevoice"
    property string model: "small-int8"
    property string modelId: ""
    property var installedModels: []
    property string language: "zh"
    property string outputMode: "universal"
    property string pasteKeys: "ctrl+v"

    // These are the three Sasayaki models.  Engine names and Voxtype's
    // internal model names stay implementation details of the config bridge.
    readonly property var models: [
        { id: "sensevoice-int8", title: "SenseVoice Small · int8", detail: "229 MB · multilingual", engine: "sensevoice", backendModel: "small-int8" },
        { id: "sensevoice-full", title: "SenseVoice Small · full precision", detail: "894 MB · higher quality", engine: "sensevoice", backendModel: "small" },
        { id: "paraformer-zh-int8", title: "Paraformer Large · int8", detail: "232 MB · Chinese-first", engine: "paraformer", backendModel: "paraformer-zh" }
    ]
    readonly property var languages: [
        { key: "zh", title: "中文" },
        { key: "en", title: "English" },
        { key: "ja", title: "日本語" },
        { key: "ko", title: "한국어" },
        { key: "auto", title: "Auto detect" }
    ]

    function open() { root.controller.show(); refresh(); }
    function close() { root.controller.hide(); }
    function toggle() { root.opened ? root.close() : root.open(); }
    function refresh() { if (!readProcess.running) readProcess.running = true; }
    function setValue(setting, value) {
        if (writeProcess.running) return;
        writeProcess.command = ["python3", root.configTool, "set", setting, value];
        root.loading = true;
        root.pendingAction = setting === "model" ? "model" : "setting";
        if (setting === "model") root.modelId = value;
        root.downloadProgress = setting === "model" ? 0 : -1;
        root.statusText = setting === "model" ? "Downloading and verifying model…" : "Applying…";
        writeProcess.running = true;
    }
    function updateDownloadProgress(line) {
        if (!line.startsWith("VOXTYPE_ENHANCE_PROGRESS ")) return;
        const fields = line.split(" ");
        if (fields.length >= 2) root.downloadProgress = Number(fields[1]);
    }
    function modelInstalled(modelId) {
        return root.installedModels.indexOf(modelId) >= 0;
    }
    function clearPluginData() {
        if (writeProcess.running) return;
        writeProcess.command = ["python3", root.configTool, "clear"];
        root.loading = true;
        root.pendingAction = "clear";
        root.downloadProgress = -1;
        root.statusText = "Clearing models and restoring defaults…";
        writeProcess.running = true;
    }
    function applySnapshot(raw) {
        try {
            const data = JSON.parse(raw);
            if (data.error) {
                root.statusText = data.error;
                return;
            }
            root.engine = data.engine || "whisper";
            root.model = data.model || "small";
            root.installedModels = data.installed_models || [];
            root.modelId = data.model_id || "";
            root.language = data.language || "auto";
            root.outputMode = data.mode || "type";
            root.pasteKeys = data.paste_keys || "ctrl+v";
        } catch (error) {
            root.statusText = "Could not read Voxtype configuration";
        }
    }
    function rowColor(active) {
        return active
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
            : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07);
    }

    Process {
        id: readProcess
        command: ["python3", root.configTool, "get"]
        running: false
        property string buffer: ""
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) { readProcess.buffer += line; } }
        onRunningChanged: {
            if (!running) { root.applySnapshot(buffer); buffer = ""; }
        }
    }

    Process {
        id: writeProcess
        command: ["python3", root.configTool, "set", "mode", "paste"]
        running: false
        property string buffer: ""
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) { writeProcess.buffer += line; } }
        stderr: SplitParser { splitMarker: "\n"; onRead: function(line) { root.updateDownloadProgress(line); } }
        onRunningChanged: {
            if (!running) {
                root.loading = false;
                root.downloadProgress = -1;
                if (buffer.length > 0) root.applySnapshot(buffer);
                if (buffer.indexOf('"error"') < 0) {
                    root.statusText = root.pendingAction === "clear"
                        ? "Defaults restored; select a model to download."
                        : "Voxtype restarted with the new setting";
                }
                root.pendingAction = "";
                buffer = "";
                clearStatus.restart();
            }
        }
    }

    Timer { id: clearStatus; interval: 3500; repeat: false; onTriggered: root.statusText = "" }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(390))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()

            Column {
                id: content
                width: parent.width
                spacing: Style.space(12)

                Text {
                    text: "Voxtype Enhance"
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                }
                Text {
                    text: "Configure dictation without leaving Omarchy. Changes restart Voxtype."
                    color: Color.muted
                    wrapMode: Text.WordWrap
                    width: parent.width
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                }

                Text { text: "Model"; color: Color.muted; font.pixelSize: Style.font.caption }
                Column {
                    width: parent.width; spacing: Style.space(6)
                    Repeater {
                        model: root.models
                        delegate: Rectangle {
                            required property var modelData
                            width: content.width
                            height: Style.space(48)
                            property bool selected: root.modelId === modelData.id && (root.modelInstalled(modelData.id) || root.loading)
                            color: root.rowColor(selected)
                            border.width: 1; border.color: selected ? Color.accent : Color.muted
                            Column {
                                anchors.fill: parent; anchors.margins: Style.space(7); spacing: 1
                                Text { text: modelData.title; color: root.barForeground; font.bold: true; font.pixelSize: Style.font.body }
                                Text {
                                    text: root.loading && root.modelId === modelData.id
                                        ? (root.downloadProgress >= 0
                                            ? "Downloading and verifying · " + Math.round(root.downloadProgress * 100) + "%"
                                            : "Downloading and verifying…")
                                        : (root.modelInstalled(modelData.id) ? modelData.detail : "Not downloaded · click to download")
                                    color: root.loading && root.modelId === modelData.id ? Color.accent : Color.muted
                                    font.pixelSize: Style.font.caption
                                }
                            }
                            Rectangle {
                                id: progressTrack
                                visible: root.loading && root.modelId === modelData.id
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: Style.space(3)
                                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                                clip: true
                                Rectangle {
                                    height: parent.height
                                    width: root.downloadProgress >= 0 ? parent.width * root.downloadProgress : parent.width * 0.32
                                    color: Color.accent
                                    x: root.downloadProgress >= 0 ? 0 : -width
                                    SequentialAnimation on x {
                                        running: progressTrack.visible && root.downloadProgress < 0
                                        loops: Animation.Infinite
                                        NumberAnimation { from: -progressTrack.width * 0.32; to: progressTrack.width; duration: 1000; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.setValue("model", modelData.id) }
                        }
                    }
                }

                Text { text: "Language"; color: Color.muted; font.pixelSize: Style.font.caption }
                Row {
                    width: parent.width; spacing: Style.space(6)
                    Repeater {
                        model: root.languages
                        delegate: Rectangle {
                            required property var modelData
                            width: (content.width - Style.space(24)) / 5
                            height: Style.space(34)
                            color: root.rowColor(root.language === modelData.key)
                            border.width: 1; border.color: root.language === modelData.key ? Color.accent : Color.muted
                            Text { anchors.centerIn: parent; text: modelData.title; color: root.barForeground; font.pixelSize: Style.font.caption }
                            MouseArea { anchors.fill: parent; onClicked: root.setValue("language", modelData.key) }
                        }
                    }
                }

                Text { text: "Output"; color: Color.muted; font.pixelSize: Style.font.caption }
                Row {
                    width: parent.width; spacing: Style.space(6)
                    Repeater {
                        model: [
                            { key: "universal", title: "Omarchy universal paste", detail: "Terminal-aware clipboard insertion" },
                            { key: "type", title: "Type", detail: "Simulated keyboard input" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (content.width - Style.space(6)) / 2
                            height: Style.space(52)
                            color: root.rowColor(root.outputMode === modelData.key)
                            border.width: 1; border.color: root.outputMode === modelData.key ? Color.accent : Color.muted
                            Column { anchors.fill: parent; anchors.margins: Style.space(7); spacing: 1
                                Text { text: modelData.title; color: root.barForeground; font.bold: true; font.pixelSize: Style.font.caption }
                                Text {
                                    text: modelData.detail
                                    color: Color.muted
                                    font.pixelSize: Style.font.caption
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.setValue("mode", modelData.key) }
                        }
                    }
                }

                Text {
                    text: root.statusText.length > 0 ? root.statusText : "Universal paste uses Shift+Insert in terminals and Ctrl+V in graphical apps."
                    color: root.statusText.length > 0 ? Color.accent : Color.muted
                    wrapMode: Text.WordWrap; width: parent.width
                    font.pixelSize: Style.font.caption
                }

                Text {
                    text: "Clear plugin data"
                    color: root.loading ? Color.muted : Color.accent
                    font.pixelSize: Style.font.caption
                    opacity: root.loading ? 0.5 : 1
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.loading
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearPluginData()
                    }
                }
            }
        }
    }
}
