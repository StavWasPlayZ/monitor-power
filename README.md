# Monitor Power

An [Omarchy](https://omarchy.org/) shell plugin that switches single monitors
off and back on from the Omarchy menu.

**Trigger › Monitors** lists every monitor, left to right. A monitor that is on
has a ✓ next to it. Pick a row to switch that monitor off, and pick it again to
switch it back on.

```
Monitors
  Left · DP-3 ✓
  Middle · DP-4 ✓
  Right · HDMI-A-2
```

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

- **The menu rows.** Plugins cannot add rows to the Omarchy menu at runtime;
  the menu reads its rows only from JSONC files. So the plugin's service
  writes one static row per monitor into
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`, between
  `// >>> monitor-power >>>` markers. It rewrites them when the shell starts
  and whenever Hyprland reports a monitor it has not seen before. The menu
  works out each ✓ (`checked`) itself every time it opens. A monitor that is
  unplugged keeps its row, and the row stays hidden (`when`) until the monitor
  is back.
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
bin/monitor-power known <output>    exit 0 when the output is connected
bin/monitor-power list              every connected output and its state
bin/monitor-power sync-menu         write the Trigger > Monitors rows
bin/monitor-power remove-menu       take those rows out again
```

Output names are the ones `hyprctl monitors all` prints (`DP-3`, `HDMI-A-2`,
...).

## Uninstall

```bash
~/.config/omarchy/plugins/dev.cstav.omarchy.plugin.monitor-power/bin/monitor-power remove-menu
omarchy plugin remove dev.cstav.omarchy.plugin.monitor-power
```

Then delete the `dofile(...)` line from `hyprland.lua`.
