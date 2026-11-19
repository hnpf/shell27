import QtQuick
import "../components"
import Quickshell

ShellRoot {
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/OpenRunde-Regular.otf") }
    FontLoader { source: Qt.resolvedUrl("../assets/fonts/OpenRunde-Semibold.otf") }
    SiriAppContent { id: siriApp }
}