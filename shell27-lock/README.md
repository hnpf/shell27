# shell27-lock Hyprland IPC integration

shell27-lock has a dedicated Quickshell IPC endpoint, `lockscreen.lock`. The helper `lock-via-ipc.sh` makes the keybind self-starting: it starts an IPC-capable shell27-lock instance if needed, waits for it to become ready, then requests the lock. Each lock process exits after unlock; the helper starts a fresh one for the next lock because a Wayland session-lock object should not be reused.

## Install

Copy this `shell27-lock` directory to `~/.config/quickshell/shell27-lock/` so `shell.qml` is at `~/.config/quickshell/shell27-lock/shell.qml`.

To lock before suspend (including the usual laptop lid-close action), run:

```sh
sh ~/.config/quickshell/shell27-lock/enable-sleep-lock.sh
```

The shell27 Hyprland module runs this setup automatically at compositor startup. It adds shell27-lock to Hypridle's
`before_sleep_cmd`, keeps any existing Hypridle settings and pre-sleep command, creates a one-time backup of the
original config, and restarts Hypridle to apply the change. This covers lid close when the system's logind policy
actually suspends on lid close; if lid close is configured to do nothing, change that system power policy too.

In your Lua-driven Hyprland config, add:

```lua
hl.bind("SUPER + L", hl.dsp.exec_cmd("sh ~/.config/quickshell/shell27-lock/lock-via-ipc.sh"))
```

This uses the `hl.bind` / `hl.dsp.exec_cmd` style. Change `SUPER + L` if that key is already used, and adjust the helper path if you installed shell27-lock elsewhere.

Spotify tracks that expose a Spotify track URI or `open.spotify.com/track/...` URL can use the track's looping Canvas
video as the animated background in expanded artwork mode. Other tracks continue to use their album artwork. Lyrics
prefer synchronized NetEase/LRCLIB results and use Genius as a plain-text fallback; Genius lyrics are not time-synced.

## Direct IPC

If an IPC-capable shell27-lock instance is currently running, the direct IPC command is:

```sh
qs -c shell27-lock ipc call lockscreen lock
```

The helper launches the IPC-capable process with `SHELL27_LOCK_DAEMON=1`. Existing setups that run `qs -c shell27-lock` directly (for example from `shell27-lock.sh`/hypridle) keep the original one-shot behavior: the session locks immediately and shell27-lock exits after unlock.

Preview mode is unchanged: `SHELL27_LOCK_PREVIEW=1 qs -c shell27-lock` opens the visual preview and does not request a real lock.
