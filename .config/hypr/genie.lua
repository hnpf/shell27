-- Genie minimize for shell27. Add to hyprland.lua:  dofile(os.getenv("HOME") .. "/.config/hypr/genie.lua")
local HOME = os.getenv("HOME")

-- hyprglass (BSD-3, https://github.com/shlok-shinde/hyprglass) built for your Hyprland version, see README.md
local plugin = HOME .. "/.local/lib/hyprglass.so"
local f = io.open(plugin, "r")
if f then
    f:close()
    pcall(hl.plugin.load, plugin)
    -- only the genie is wanted here: no glass effect on transparent windows
    pcall(hl.config, { plugin = { hyprglass = { enabled = false } } })
end

hl.bind("SUPER + M",         hl.dsp.exec_cmd(HOME .. "/.local/bin/shell27-genie min"))
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd(HOME .. "/.local/bin/shell27-genie restore"))
