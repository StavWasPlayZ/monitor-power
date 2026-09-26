// Keeps the Trigger > Monitors rows in the Omarchy menu in step with the
// monitors that exist.
//
// The menu reads its rows from JSONC only; a plugin cannot hand it rows at
// runtime. So bin/monitor-power writes one static row per monitor into
// ~/.config/omarchy/extensions/omarchy-menu.jsonc, and the menu works out
// the check mark (`checked:`) and whether to show the row (`when:`) itself
// each time it opens. All this service does is rewrite those rows when the
// shell starts and whenever Hyprland reports a monitor it has not seen yet.

import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: root

    readonly property string ctl: decodeURIComponent(
        Qt.resolvedUrl("bin/monitor-power").toString().replace(/^file:\/\//, "")
    )

    Process {
        id: sync
        command: [root.ctl, "sync-menu"]
        running: true

        stderr: SplitParser {
            onRead: function(line) { console.warn("Monitor Power:", line) }
        }
    }

    // Monitors arrive in bursts (a dock, a hotplug that bounces); one
    // rewrite after they settle is enough.
    Timer {
        id: settle
        interval: 1500
        onTriggered: sync.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitoraddedv2") settle.restart()
        }
    }
}
