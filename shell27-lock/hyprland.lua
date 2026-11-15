-- Paste this into your existing Lua-driven Hyprland config.
-- The wrapper starts shell27-lock in IPC daemon mode if needed, waits for its endpoint,
-- and then locks. Update the path if you installed shell27-lock elsewhere.
hl.bind("SUPER + L", hl.dsp.exec_cmd("sh ~/.config/quickshell/shell27-lock/lock-via-ipc.sh"))
