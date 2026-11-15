#!/bin/sh
# shell27 session wallpaper: ii drew its own background, shell27 relies on a daemon.
# Applies shell27's remembered wallpaperPath (set by its Ctrl+Alt+W picker),
# falling back to the current ii wallpaper.
cfg="$HOME/.config/macdock/settings.json"
p=$(jq -r '.wallpaperPath // empty' "$cfg" 2>/dev/null)
[ -f "$p" ] || p=$(jq -r '.background.wallpaperPath // empty' "$HOME/.config/illogical-impulse/config.json" 2>/dev/null)
pgrep -x awww-daemon >/dev/null || { setsid awww-daemon >/dev/null 2>&1 & }
for i in $(seq 30); do awww query >/dev/null 2>&1 && break; sleep 0.2; done
[ -f "$p" ] && awww img "$p" --transition-type none
# animated wallpaper (video) set from shell27 Settings → Wallpaper: start it again on top of the still frame
"$HOME/.config/hypr-shell27/scripts/shell27-setwall.sh" --restore >/dev/null 2>&1
