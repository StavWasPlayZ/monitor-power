// Puts the Trigger > Monitors row in the Omarchy menu.
//
// The menu reads its rows from JSONC only; a plugin cannot hand it one at
// runtime. So bin/monitor-power writes the row into
// ~/.config/omarchy/extensions/omarchy-menu.jsonc when the shell starts. It
// leaves the file alone when the row is already there.

import QtQuick
import Quickshell.Io

Item {
    id: root

    readonly property string ctl: decodeURIComponent(
        Qt.resolvedUrl("bin/monitor-power").toString().replace(/^file:\/\//, "")
    )

    Process {
        command: [root.ctl, "install-menu"]
        running: true

        stderr: SplitParser {
            onRead: function(line) { console.warn("Monitor Power:", line) }
        }
    }
}
