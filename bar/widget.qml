import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "hancore.voxtype-enhance"

    property string runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        return xdg && xdg.length > 0 ? xdg + "/voxtype" : "/run/user/1000/voxtype";
    }
    property string daemonState: "idle"
    property int spinnerFrame: 0
    readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    FileView {
        id: stateFile
        path: root.runtimeDir + "/state"
        watchChanges: true
        printErrors: false
        onLoaded: root.daemonState = (text() || "idle").trim()
        onLoadFailed: root.daemonState = "idle"
        onFileChanged: reload()
    }

    Timer {
        interval: 120
        repeat: true
        running: root.daemonState === "transcribing"
        onTriggered: root.spinnerFrame = (root.spinnerFrame + 1) % root.spinnerFrames.length
    }

    onDaemonStateChanged: {
        if (root.daemonState !== "transcribing") root.spinnerFrame = 0;
    }

    function injectPanel() {
        if (!panelLoader.item) return;
        panelLoader.item.bar = root.bar;
        panelLoader.item.settings = root.settings;
        panelLoader.item.anchorItem = button;
        panelLoader.item.hostWidget = root;
    }

    function open() {
        if (panelLoader.item) {
            panelLoader.item.open();
            return;
        }
        panelLoader.active = true;
        Qt.callLater(function() {
            if (panelLoader.item) panelLoader.item.open();
        });
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close();
    }

    function toggle() {
        if (root.opened) root.close();
        else root.open();
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("../VoxtypePanel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
    }

    BarIconButton {
        id: button
        bar: root.bar
        text: root.daemonState === "transcribing" ? root.spinnerFrames[root.spinnerFrame] : "󰍬"
        tooltipText: root.daemonState === "recording" ? "Voxtype recording"
            : root.daemonState === "transcribing" ? "Voxtype transcribing"
            : "Voxtype settings"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle();
        }
    }
}
