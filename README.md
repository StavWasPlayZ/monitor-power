# Monitor Power

An [Omarchy](https://omarchy.org/) shell plugin that switches single monitors
off and back on.

**Trigger › Monitors** in the Omarchy menu opens a map of your monitors, each
drawn where it sits in your layout and labelled with its connector (`DP-3`,
`HDMI-A-2`, ...). A monitor that is on has a filled tile; one that is off is
dim and empty. Click a tile, or pick it with the arrow keys (or h/j/k/l) and
press Enter or Space, to switch it. Esc closes the map.

Every monitor is on when a session starts. The plugin refuses to switch off
the last monitor that is still on.

## Install

```bash
gh repo clone StavWasPlayZ/monitor-power \
  ~/.config/omarchy/plugins/dev.cstav.omarchy.plugin.monitor-power
omarchy plugin enable dev.cstav.omarchy.plugin.monitor-power
omarchy restart shell
```

The folder name must be the plugin id, not the repo name.

Then add this to `~/.config/hypr/hyprland.lua`, anywhere after
`require("hypr.monitors")`:

```lua
dofile(os.getenv("HOME")
  .. "/.config/omarchy/plugins/dev.cstav.omarchy.plugin.monitor-power/monitor-power.lua").apply()
```

Without that line, the next config reload (which happens on every save of a
Hyprland config file) turns switched-off monitors back on.

## How it works

- **The menu row.** Plugins cannot add rows to the Omarchy menu at runtime;
  the menu reads its rows only from JSONC files. So the plugin's service
  writes the one Trigger › Monitors row into
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`, between
  `// >>> monitor-power >>>` markers, when the shell starts. The row opens the
  overlay (`omarchy-shell shell summon dev.cstav.omarchy.plugin.monitor-power`).
- **The map.** `Overlay.qml` draws each connected monitor from
  `bin/monitor-power json`, scaled to fit. A monitor that is off is drawn at
  the place it was in when it went off.
- **Off.** The output is disabled, not blanked with DPMS. A blanked panel can
  fall asleep, drop off the DisplayPort link and reconnect as a new monitor,
  which Hyprland switches back on, every few seconds. A disabled output stays
  dark. Its workspaces move to another monitor while it is off.
- **On.** One monitor rule restores the output's recorded mode, position and
  scale with `disabled = false`, and then a config reload restores the rest of
  your `monitors.lua` for it. Hyprland moves its workspaces back.

  A config reload alone does not work as the "on" step. It enables the output
  before a sleeping panel wakes, so the output first appears with no mode
  (0x0, scale 0). Chromium-based browsers running on Wayland crash when they
  see that output (Brave did, with SIGTRAP).
- **State.** The list of outputs that are off lives in
  `$XDG_RUNTIME_DIR/omarchy-monitor-power/off`, tagged with the Hyprland
  instance. `monitor-power.lua` reapplies it on every reload and ignores it
  after Hyprland restarts.

## Command line

```
bin/monitor-power toggle <output>   off if it is on, on if it is off
bin/monitor-power off <output>      disable the output
bin/monitor-power on <output>...    enable them again
bin/monitor-power is-on <output>    exit 0 when the output is enabled
bin/monitor-power list              every connected output and its state
bin/monitor-power json              the same, with each output's layout box
bin/monitor-power install-menu      add the Trigger > Monitors menu row
bin/monitor-power remove-menu       take that row out again
```

Output names are the ones `hyprctl monitors all` prints (`DP-3`, `HDMI-A-2`,
...).

## Uninstall

```bash
~/.config/omarchy/plugins/dev.cstav.omarchy.plugin.monitor-power/bin/monitor-power remove-menu
omarchy plugin remove dev.cstav.omarchy.plugin.monitor-power
```

Then delete the `dofile(...)` line from `hyprland.lua`.
