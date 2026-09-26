// Monitor Power overlay: the monitors drawn where they sit in the layout.
// A monitor that is on has a filled tile; one that is off is a dim, empty
// one. Only the selected tile has an outline.
//
// Opened from Trigger > Monitors in the Omarchy menu. Styled off the [menu]
// theme surface, so it looks and keys like the menu: arrows (or h/j/k/l) move
// between monitors by where they are on the desk, Enter or Space flips the
// selected one, Esc leaves. A click flips a monitor too.
//
// All the work is bin/monitor-power's: `json` describes the monitors, and
// `toggle <output>` switches one. A monitor that is off still has a tile, at
// the place it was in when it went off.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by the shell's panel loader when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string ctl: decodeURIComponent(
    Qt.resolvedUrl("bin/monitor-power").toString().replace(/^file:\/\//, ""))

  property bool opened: false
  property bool loaded: false
  property bool loadFailed: false
  property var monitors: []
  property int selectedIndex: -1
  property bool cursorActive: false
  // Output name to the state it is switching to, while its toggle runs. The
  // tile shows the new state straight away instead of after the reload.
  property var pending: ({})

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.cursorActive = true
    root.selectedIndex = -1
    root.reload()
    root.opened = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function ping() { return "ok" }

  // ------------------------------------------------------------------ data

  property bool reloadPending: false

  function reload() {
    if (listProc.running) { root.reloadPending = true; return }
    listProc.running = true
  }

  function applyList(raw, exitCode) {
    var list = null
    if (exitCode === 0) {
      try { list = JSON.parse(raw) } catch (e) { list = null }
    }
    root.loadFailed = !Array.isArray(list)
    if (root.loadFailed) {
      console.warn("monitor-power: no usable reply from bin/monitor-power json (exit " + exitCode + ")")
      list = []
    }

    var previous = root.selectedIndex >= 0 && root.selectedIndex < root.monitors.length
      ? root.monitors[root.selectedIndex].name : ""
    root.monitors = root.laidOut(list)
    root.loaded = true

    var next = -1
    for (var i = 0; i < root.monitors.length; i++) {
      if (previous && root.monitors[i].name === previous) { next = i; break }
      if (!previous && root.monitors[i].focused) next = i
    }
    root.selectedIndex = next >= 0 ? next : (root.monitors.length ? 0 : -1)
  }

  // Monitors with no box (disabled by something other than this plugin) go in
  // a row under the rest, so they can still be switched back on. Everything is
  // then sorted top to bottom, left to right, which is also the Tab order.
  function laidOut(list) {
    var maxBottom = 0, nextX = 0
    for (var i = 0; i < list.length; i++) {
      var g = list[i].geometry
      if (g) maxBottom = Math.max(maxBottom, g.y + g.height)
    }
    var out = []
    for (var j = 0; j < list.length; j++) {
      var m = list[j]
      var box = m.geometry
      if (!box) {
        box = { x: nextX, y: maxBottom + 120, width: 1920, height: 1080 }
        nextX += 2040
      }
      out.push({ name: m.name, make: m.make || "", model: m.model || "", on: !!m.on,
                 focused: !!m.focused, x: box.x, y: box.y, w: box.width, h: box.height })
    }
    out.sort(function (a, b) { return a.y - b.y || a.x - b.x || (a.name < b.name ? -1 : 1) })
    return out
  }

  function isOn(monitor) {
    return root.pending[monitor.name] !== undefined ? root.pending[monitor.name] : monitor.on
  }

  // ---------------------------------------------------------- interactions

  function flip(index) {
    if (index < 0 || index >= root.monitors.length) return
    var monitor = root.monitors[index]
    if (root.pending[monitor.name] !== undefined) return
    var turningOn = !root.isOn(monitor)

    if (!turningOn) {
      var lit = 0
      for (var i = 0; i < root.monitors.length; i++) if (root.isOn(root.monitors[i])) lit++
      if (lit <= 1) {
        Quickshell.execDetached(["notify-send", "-a", "Monitor Power", "Monitor Power",
                                 monitor.name + " is the only monitor on - keeping it on."])
        return
      }
    }

    var next = Object.assign({}, root.pending)
    next[monitor.name] = turningOn
    root.pending = next

    // The overlay lives on the focused monitor. Switching that one off takes
    // the overlay's surface away with it, so leave first.
    if (!turningOn && monitor.focused) root.close()

    Quickshell.execDetached([root.ctl, "toggle", monitor.name])
    settle.restart()
  }

  // execDetached reports nothing back, so the result is read off Hyprland: the
  // monitor events trigger a reload, and this catches a toggle that changed
  // nothing (or an event that came before the switch was done).
  property Timer settle: Timer {
    interval: 1500
    onTriggered: {
      root.pending = ({})
      root.reload()
    }
  }

  function selectedMonitor() {
    return root.selectedIndex >= 0 && root.selectedIndex < root.monitors.length
      ? root.monitors[root.selectedIndex] : null
  }

  // Move to the nearest monitor in that direction, by the centers of the
  // boxes. Sideways distance counts double, so → goes to the monitor beside
  // this one before one that is further right but also lower down.
  function move(dx, dy) {
    root.cursorActive = true
    var from = root.selectedMonitor()
    if (!from) { if (root.monitors.length) root.selectedIndex = 0; return }
    var fx = from.x + from.w / 2, fy = from.y + from.h / 2
    var best = -1, bestScore = Infinity
    for (var i = 0; i < root.monitors.length; i++) {
      if (i === root.selectedIndex) continue
      var m = root.monitors[i]
      var along = dx !== 0 ? (m.x + m.w / 2 - fx) * dx : (m.y + m.h / 2 - fy) * dy
      var across = dx !== 0 ? Math.abs(m.y + m.h / 2 - fy) : Math.abs(m.x + m.w / 2 - fx)
      if (along <= 0) continue
      var score = along + across * 2
      if (score < bestScore) { bestScore = score; best = i }
    }
    if (best >= 0) root.selectedIndex = best
  }

  function cycle(delta) {
    if (!root.monitors.length) return
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + root.monitors.length) % root.monitors.length
  }

  // Pointer hover only takes the cursor once the pointer has moved, so the
  // card opening under a resting pointer does not steal the keyboard's pick.
  property real pointerX: -1
  property real pointerY: -1
  function selectFromPointer(index, item, position) {
    var x = item.x + position.x
    var y = item.y + position.y
    if (root.pointerX === x && root.pointerY === y) return
    root.pointerX = x
    root.pointerY = y
    root.cursorActive = true
    root.selectedIndex = index
  }

  // -------------------------------------------------------------- plumbing

  property Process listProc: Process {
    command: ["bash", "-c", "timeout -k 1 5 \"$1\" json", "monitor-power", root.ctl]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function (exitCode) {
      root.applyList(listOut.text, exitCode)
      if (root.reloadPending) {
        root.reloadPending = false
        root.reload()
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened) return
      var name = String(event.name || "")
      if (name === "monitoraddedv2" || name === "monitorremovedv2") {
        if (!reloadThrottle.running) reloadThrottle.start()
      }
    }
  }

  property Timer reloadThrottle: Timer {
    interval: 250
    onTriggered: {
      if (!root.opened) return
      root.pending = ({})
      root.reload()
    }
  }

  // ----------------------------------------------------------------- theme

  // Shares the [menu] surface tokens, so a theme that styles the Omarchy menu
  // styles this the same way.
  property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, Math.max(1, Style.space(2)))

  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int tileGap: Style.space(8)

  property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
  readonly property real innerWidth: cardWidth - contentMargin * 2 - Border.left(borderSpec) - Border.right(borderSpec)

  // The layout's bounding box in logical pixels.
  readonly property var bounds: {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (var i = 0; i < root.monitors.length; i++) {
      var m = root.monitors[i]
      minX = Math.min(minX, m.x); minY = Math.min(minY, m.y)
      maxX = Math.max(maxX, m.x + m.w); maxY = Math.max(maxY, m.y + m.h)
    }
    if (!root.monitors.length) return { x: 0, y: 0, w: 1920, h: 1080 }
    return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
  }
  readonly property real mapHeight: Math.max(Style.space(140),
    Math.min(Style.space(380), innerWidth * bounds.h / bounds.w))
  readonly property real mapScale: Math.min(innerWidth / bounds.w, mapHeight / bounds.h)
  readonly property real mapOffsetX: (innerWidth - bounds.w * mapScale) / 2
  readonly property real mapOffsetY: (mapHeight - bounds.h * mapScale) / 2

  property int cardHeight: Math.min(contentMargin * 2 + mapHeight
    + Border.top(borderSpec) + Border.bottom(borderSpec), panel.height - Style.gapsOut * 2)

  // -------------------------------------------------------------------- UI

  PanelWindow {
    id: panel
    visible: root.opened && root.loaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-monitor-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) {
        root.pointerX = -1
        root.pointerY = -1
        Qt.callLater(function () { keyCatcher.forceActiveFocus() })
      }
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          var key = event.key
          if (key === Qt.Key_Escape) root.close()
          else if (key === Qt.Key_Left || key === Qt.Key_H) root.move(-1, 0)
          else if (key === Qt.Key_Right || key === Qt.Key_L) root.move(1, 0)
          else if (key === Qt.Key_Up || key === Qt.Key_K) root.move(0, -1)
          else if (key === Qt.Key_Down || key === Qt.Key_J) root.move(0, 1)
          else if (key === Qt.Key_Tab) root.cycle(1)
          else if (key === Qt.Key_Backtab) root.cycle(-1)
          else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) root.flip(root.selectedIndex)
          else return
          event.accepted = true
        }
      }

      Item {
        id: map
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

          Repeater {
            model: root.monitors

            delegate: BorderSurface {
              id: tile
              required property var modelData
              required property int index

              readonly property bool hasCursor: root.cursorActive && tile.index === root.selectedIndex
              readonly property bool on: root.isOn(tile.modelData)
              readonly property bool roomy: tile.height >= Style.space(80)
              readonly property color textColor: tile.on ? root.selectedText : root.foreground

              x: root.mapOffsetX + (tile.modelData.x - root.bounds.x) * root.mapScale + root.tileGap / 2
              y: root.mapOffsetY + (tile.modelData.y - root.bounds.y) * root.mapScale + root.tileGap / 2
              width: Math.max(Style.space(40), tile.modelData.w * root.mapScale - root.tileGap)
              height: Math.max(Style.space(40), tile.modelData.h * root.mapScale - root.tileGap)
              radius: root.cornerRadius
              color: tile.on ? root.selectedBackground : "transparent"
              borderSpec: tile.hasCursor ? root.selectedBorderSpec : Border.none()

              Behavior on color { ColorAnimation { duration: 120 } }

              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                spacing: Style.space(tile.roomy ? 6 : 3)

                // Nerd Font monitor glyph (U+F0379), from the menu's own font.
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: tile.roomy
                  horizontalAlignment: Text.AlignHCenter
                  text: "󰍹"
                  color: tile.textColor
                  opacity: tile.on ? 0.85 : 0.35
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: tile.modelData.name
                  color: tile.textColor
                  opacity: tile.on ? 1 : 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: tile.roomy && text.length > 0
                  horizontalAlignment: Text.AlignHCenter
                  text: (tile.modelData.make + " " + tile.modelData.model).trim()
                  color: tile.textColor
                  opacity: tile.on ? 0.6 : 0.3
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(tile.index, tile, { x: tileMouse.mouseX, y: tileMouse.mouseY })
                onPositionChanged: function (mouse) { root.selectFromPointer(tile.index, tile, mouse) }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = tile.index
                  root.flip(tile.index)
                }
              }
            }
          }
      }
    }
  }
}
