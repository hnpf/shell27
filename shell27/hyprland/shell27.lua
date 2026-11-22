-- >>> shell27 module (added by install.sh) >>>
-- autostart (remove other bars / docks / notification daemons first).
-- install.sh adds this for you; shell27-start waits for the compositor and restarts the shell if it crashes.
local function shell27IconTheme()
    local home = os.getenv("HOME") or ""
    for _, path in ipairs({ home .. "/.config/gtk-3.0/settings.ini", home .. "/.config/gtk-4.0/settings.ini" }) do
        local file = io.open(path, "r")
        if file then
            for line in file:lines() do
                local name = line:match("^%s*gtk%-icon%-theme%-name%s*=%s*(.-)%s*$")
                if name and name ~= "" then file:close(); return name end
            end
            file:close()
        end
    end
    return nil
end

if not os.getenv("QS_ICON_THEME") and not os.getenv("QT_QPA_PLATFORMTHEME") then
    local iconTheme = shell27IconTheme()
    if iconTheme and iconTheme:match("^[%w_.+%-]+$") then hl.env("QS_ICON_THEME", iconTheme) end
end

hl.on("hyprland.start", function()
    local pluginPath = (os.getenv("HOME") or "") .. "/.local/share/shell27/plugins/hyprglass.so"
    local pluginFile = io.open(pluginPath, "r")
    if pluginFile then
        pluginFile:close()
        hl.exec_cmd("hyprctl plugin load " .. string.format("%q", pluginPath))
    end
    hl.exec_cmd("awww-daemon")
    -- Install/update Hypridle's before_sleep_cmd hook (lid close is covered when it suspends).
    hl.exec_cmd("sh ~/.config/quickshell/shell27-lock/enable-sleep-lock.sh")
    hl.exec_cmd("sh ~/.local/bin/shell27-start shell27")
end)
-- The Settings window floats and centres itself: the shell registers its own window rule at start-up, so this file needs none.

-- keybinds (the name after -c is the config folder name, case-sensitive)
local qs = "qs -c shell27 ipc call "

hl.bind("SUPER + Z",          hl.dsp.exec_cmd(qs .. "settings toggle"))
hl.bind("SUPER + B",          hl.dsp.exec_cmd(qs .. "bar toggle"))
hl.bind("SUPER + SHIFT + B",  hl.dsp.exec_cmd(qs .. "dock toggle"))
hl.bind("SUPER + V",          hl.dsp.exec_cmd(qs .. "spotlight clipboard"))
hl.bind("SUPER + period",     hl.dsp.exec_cmd(qs .. "spotlight emoji"))
hl.bind("SUPER + Space",      hl.dsp.exec_cmd(qs .. "spotlight toggle"))
hl.bind("ALT + TAB",          hl.dsp.exec_cmd(qs .. "switcher next"))
hl.bind("CTRL + ALT + W",     hl.dsp.exec_cmd(qs .. "wallpapers toggle"))
hl.bind("PRINT",              hl.dsp.exec_cmd(qs .. "screenshot region"))
hl.bind("SUPER + SHIFT + R",      hl.dsp.exec_cmd("qs kill -c shell27; sleep 0.5; qs -c shell27"))

-- Siri Voice-only Mode
hl.bind("SUPER + F5", hl.dsp.exec_cmd("qs -c shell27 ipc call siri voice_toggle"))

-- Siri Visual Intelligence
hl.bind("SUPER + SHIFT + F5", hl.dsp.exec_cmd(qs .. "screenshot visual"))

-- Hardware keys (laptop buttons too): volume, mute, brightness, media. shell27 handles them itself and shows its
-- on-screen display. If the shell is not running, wpctl / brightnessctl do the work instead.
-- "locked" keeps the keys working on the lock screen. Any earlier bind on the same key is dropped first, so a key never fires twice.
local function hw(action, fallback)
    return "sh -c '" .. qs .. "hardware " .. action .. " >/dev/null 2>&1 || " .. fallback .. "'"
end
local hwkeys = {
    { "XF86AudioRaiseVolume",  hw("volumeUp",       "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),   true  },
    { "XF86AudioLowerVolume",  hw("volumeDown",     "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        true  },
    { "XF86AudioMute",         hw("mute",           "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       false },
    { "XF86AudioMicMute",      hw("micMute",        "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     false },
    { "XF86MonBrightnessUp",   hw("brightnessUp",   "brightnessctl -q -c backlight set 5%+ 2>/dev/null || ddcutil setvcp 10 + 5"),                      true  },
    { "XF86MonBrightnessDown", hw("brightnessDown", "brightnessctl -q -n1 -c backlight set 5%- 2>/dev/null || ddcutil setvcp 10 - 5"),                  true  },
    { "XF86KbdBrightnessUp",   "brightnessctl -q -d '*kbd_backlight*' set 10%+",                         true  },
    { "XF86KbdBrightnessDown", "brightnessctl -q -d '*kbd_backlight*' set 10%-",                         true  },
    { "XF86AudioPlay",         "playerctl play-pause",                                                   false },
    { "XF86AudioPause",        "playerctl pause",                                                        false },
    { "XF86AudioNext",         "playerctl next",                                                         false },
    { "XF86AudioPrev",         "playerctl previous",                                                     false },
}
for _, k in ipairs(hwkeys) do
    pcall(hl.unbind, k[1])
    hl.bind(k[1], hl.dsp.exec_cmd(k[2]), { locked = true, repeating = k[3] })
end

-- shell27-lock (lock screen)
hl.bind("SUPER + L",          hl.dsp.exec_cmd("sh ~/.config/quickshell/shell27-lock/lock-via-ipc.sh"))
-- <<< shell27 module <<<
