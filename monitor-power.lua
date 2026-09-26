-- Keep monitors that were switched off from the menu off across config
-- reloads.
--
-- In ~/.config/hypr/hyprland.lua, after require("hypr.monitors"):
--
--   dofile(os.getenv("HOME")
--     .. "/.config/omarchy/plugins/dev.cstav.omarchy.plugin.monitor-power/monitor-power.lua").apply()
--
-- dofile rather than require, because the plugin's directory name is full of
-- dots and require reads every dot as a slash.
--
-- apply() must run on every reload. Turning a monitor back on IS a reload
-- (bin/monitor-power drops it from the state file first), so a monitor rule
-- written here is the only thing keeping an "off" monitor off.

local M = {}

local function state_file()
  local runtime = os.getenv("XDG_RUNTIME_DIR")
  if not runtime or runtime == "" then return nil end
  return runtime .. "/omarchy-monitor-power/off"
end

-- Outputs switched off during this Hyprland session. A file left behind by an
-- earlier session is ignored, so every session starts with all monitors on.
function M.off_outputs()
  local path = state_file()
  local file = path and io.open(path, "r")
  if not file then return {} end

  local outputs = {}
  local first = file:read("l")
  if first == "instance " .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") then
    for line in file:lines() do
      local name = line:match("^([%w_.%-]+)")
      if name then outputs[#outputs + 1] = name end
    end
  end
  file:close()
  return outputs
end

function M.apply()
  for _, name in ipairs(M.off_outputs()) do
    hl.monitor({ output = name, disabled = true })
  end
end

return M
