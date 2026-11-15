---- MONITORS ----

hl.monitor({ output = "DP-1", mode = "1920x1080@200", position = "1920x0", scale = "auto" })
hl.monitor({ output = "DP-2", mode = "1920x1080@79",  position = "0x0",     scale = "auto" })

---- MY PROGRAMS ----

local terminal    = "kitty" 
local fileManager = "nautilus --new-window"
local menu        = "hyprlauncher"
local browser     = "zen-browser"
local editor      = "code"
local qs = "qs -c shell27 ipc call "

---- ENVIRONMENT VARIABLES ----

local cursorTheme = "MacTahoe-light"
local cursorSize  = "28"
local gtkTheme    = "adw-gtk3-dark"
local iconTheme   = "MacOS-Like-Dark"


hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XCURSOR_THEME", cursorTheme)
hl.env("XCURSOR_SIZE", cursorSize)
hl.env("HYPRCURSOR_THEME", cursorTheme)
hl.env("HYPRCURSOR_SIZE", cursorSize)
hl.env("WLR_RENDERER_ALLOW_SOFTWARE", "0")
hl.env("AQ_NO_MODIFIERS", "1")

---- AUTOSTART ----

hl.on("hyprland.start", function ()
    -- Polkit Authentication Agent
    hl.exec_cmd("systemctl --user start hyprpolkitagent")

	-- Hyprglass
	hl.exec_cmd("hyprctl plugin load " .. os.getenv("HOME") .. "/hyprglass/hyprglass.so")
	
    -- Hyprland compositor cursor
    hl.exec_cmd("hyprctl setcursor " .. cursorTheme .. " " .. cursorSize)

    -- GTK / GNOME cursor, theme & icons
    hl.exec_cmd('gsettings set org.gnome.desktop.interface gtk-theme "' .. gtkTheme .. '"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface icon-theme "' .. iconTheme .. '"')
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")

    -- KDE / Qt icons
    hl.exec_cmd('kwriteconfig6 --file kdeglobals --group Icons --key Theme "' .. iconTheme .. '" 2>/dev/null || true')

	-- buffer start on launch
--    hl.exec_cmd("~/.local/bin/HyprSaved start")


end)

---- LOOK AND FEEL ----

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 20,
        border_size = 0,

        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = false,
        allow_tearing = false,
        
        layout = "dwindle",
    },

    decoration = {
            rounding       = 18,
            rounding_power = 2,
    
            active_opacity   = 1.0,
            inactive_opacity = 0.97, -- Keep inactive windows fully opaque so text stays crisp!
    		
            shadow = {
                enabled      = true,
                range        = 4,
                render_power = 3,
                color        = 0xee1a1a1a,
            },
    
            blur = {
                enabled   = true,
                size      = 3,   -- Reduced from 3 for a lighter, more subtle frosted effect
                passes    = 2,   -- Reduced from 2 so it doesn't look heavily frosted/muddy
                vibrancy  = 0.1696,
            },
        },

    animations = {
        enabled = true,
    },

    dwindle   = { preserve_split = true },
    master    = { new_status = "master" },
    scrolling = { fullscreen_on_one_column = true },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
    },
})

---- CURVES & ANIMATIONS ----

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5}, {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 4.5,  spring = "easy" })

hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })

hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })

-- Improved regular workspace transitions
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4,    spring = "easy",         style = "slidefade 20%" })

-- Special Workspace dropdown / exit animations
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 3.8, spring = "easy",         style = "slidefadevert -50%" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2.8, bezier = "easeOutQuint", style = "slidefadevert -50%" })

hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

---- INPUT & GESTURES ----

hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        accel_profile = "flat",
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })

---- KEYBINDINGS ----

local mainMod = "SUPER"

-- Applications & Windows
hl.bind(mainMod .. " + Return",      hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",           hl.dsp.window.close())
hl.bind(mainMod .. " + W",           hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + C",           hl.dsp.exec_cmd(editor))
hl.bind(mainMod .. " + ALT + space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + M",           hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"))
hl.bind(mainMod .. " + E",           hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + R",           hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P",           hl.dsp.window.pseudo())
--hl.bind(mainMod .. " + J",           hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + F",           hl.dsp.window.fullscreen({ action = "toggle" }))


---- HYPRSAVED ----

-- Toggle buffer ON / OFF (Save resources when not gaming/recording)
--hl.bind(mainMod .. " + SHIFT + J", hl.dsp.exec_cmd("~/.local/bin/HyprSaved toggle"))

-- Save the last 30 seconds
--hl.bind(mainMod .. " + J",         hl.dsp.exec_cmd("~/.local/bin/HyprSaved save"))


---- NAVIGATION ----

-- Focus Navigation
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Workspaces 1-10
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    -- ALT moves window and follows focus:
    hl.bind(mainMod .. " + ALT + " .. key,   hl.dsp.window.move({ workspace = i, follow = true }))
    -- SHIFT moves window silently without leaving current workspace:
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Special Workspace (Scratchpad) Toggle
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))

-- Smart Special Workspace Window Mover (SUPER + ALT + S)
local function toggle_special_window()
    local win = hl.get_active_window()
    if not win then return end

    local special = hl.get_active_special_workspace()
    local active_ws = hl.get_active_workspace()

    if special ~= nil or (win.workspace and tostring(win.workspace.name or ""):find("special")) then
        if active_ws then
            hl.dispatch(hl.dsp.window.move({ workspace = active_ws.id }))
        else
            hl.dispatch(hl.dsp.window.move({ workspace = "+0" }))
        end
        if special ~= nil then
            hl.dispatch(hl.dsp.workspace.toggle_special("magic"))
        end
    else
        hl.dispatch(hl.dsp.window.move({ workspace = "special:magic", follow = false }))
    end
end
hl.bind(mainMod .. " + ALT + S", toggle_special_window)

-- Workspace scrolling
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Drag / resize windows with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Audio & Brightness Controls
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- System Settings
hl.bind("SUPER + I",          hl.dsp.exec_cmd(qs .. "settings toggle"))

-- Toggle TopBar
hl.bind("SUPER + SHIFT + d", hl.dsp.exec_cmd("qs -c shell27 ipc call bar toggle"), { locked = true })

-- Toggle Dock
hl.bind("SUPER + d", hl.dsp.exec_cmd("qs -c shell27 ipc call dock toggle"), { locked = true })

-- Media Controls
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- float all goes here:

local float_all_enabled = false
local forced_floated_windows = {}

hl.bind(mainMod .. " + SHIFT + F", function()
    float_all_enabled = not float_all_enabled
    if float_all_enabled then
        hl.exec_cmd("notify-send -i preferences-system-windows 'Float All' 'Enabled - all windows will float' -t 2000")
        local windows = hl.get_windows()
        for _, window in ipairs(windows) do
            -- only float and track if it wasn't already floating on its own
            if not window.floating then
                table.insert(forced_floated_windows, window.address)
                hl.dispatch(hl.dsp.window.float({ window = window, action = "on" }))
            end
        end
    else
        hl.exec_cmd("notify-send -i window-close 'Float All' 'Disabled' -t 2000")
        -- restore windows that were forced to float back to tiling
        for _, addr in ipairs(forced_floated_windows) do
            hl.dispatch(hl.dsp.window.float({ window = addr, action = "off" }))
        end
        forced_floated_windows = {}
    end
end)

hl.on("window.open", function(window)
    if float_all_enabled then
        table.insert(forced_floated_windows, window.address)
        hl.dispatch(hl.dsp.window.float({ window = window, action = "on" }))
    end
end)

---- WORKSPACE RULES ----

-- Special Workspace: Increased 30px outer margins
hl.workspace_rule({
    workspace = "special:magic",
    gaps_out  = 40,
    gaps_in   = 8,
})

---- WINDOW RULES ----

hl.window_rule({
    name = "zen-shit",
    match = { class = "zen" },
	float           = true,
	size            = "1294 886",
	persistent_size = true,
})

hl.window_rule({
    name = "maps-small-float",
    match = { class = "org.gnome.Maps" },
	float           = true,
	size            = "930 740",
	persistent_size = true,
})

hl.window_rule({
    name = "music-small-float",
    match = { class = "org.gnome.Music" },
	float           = true,
	size            = "972 672",
	persistent_size = true,
})

hl.window_rule({
    name = "console-small-float",
    match = { class = "org.gnome.Console" },
	float           = true,
	size            = "840 529",
	persistent_size = true,
})

hl.window_rule({
    name = "notes-small-float",
    match = { class = "org.gnome.TextEditor" },
	float           = true,
	size            = "597 728",
	persistent_size = true,
})

hl.window_rule({
    name = "systemmonitor-small-float",
    match = { class = "org.gnome.SystemMonitor" },
	float           = true,
	size            = "950 690",
	persistent_size = true,
})

hl.window_rule({
    name = "calendar-small-float",
    match = { class = "org.gnome.Calendar" },
	float           = true,
	size            = "813 636",
	persistent_size = true,
})

hl.window_rule({
    name = "appstore-small-float",
    match = { class = "org.gnome.Software" },
	float           = true,
	size            = "1074 778",
	persistent_size = true,
})

hl.window_rule({
    name = "localsend-small-float",
    match = { class = "org.localsend.localsend_app" },
	float           = true,
	size            = "1007 712",
	persistent_size = true,
})

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "lock-calculator-dims",
    match = { class = "^(org.gnome.Calculator)$" },
    float           = true,
    size            = "360 616",
    persistent_size = true,
})

hl.window_rule({
    name = "windowed-nautilus",
    match = { class = "^(org.gnome.Nautilus)$" },
    float           = true,
    size            = "1010 680",
    persistent_size = true,
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class      = "^",
        title      = "^",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name = "persist-portal-picker-dims",
    match = { class = "^(xdg-desktop-portal-gtk)$" },
    float           = true,
    persistent_size = true,
})

hl.window_rule({
    name = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

hl.layer_rule({ name = "macdock",  match = { namespace = "macdock"  }, blur = true, ignore_alpha = 0.2,  no_anim = true })
hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macshot",  match = { namespace = "macshot"  }, no_anim = true })
hl.layer_rule({ name = "macspot",  match = { namespace = "macspot"  }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macswitch",  match = { namespace = "macswitch"  }, blur = true, ignore_alpha = 0.05, no_anim = true })


-- >>> shell27 (added by install.sh) >>>
-- Load the generated shell27 autostart and keybind module.
require("shell27")
-- <<< shell27 <<<
dofile(os.getenv("HOME") .. "/.config/hypr/genie.lua")
