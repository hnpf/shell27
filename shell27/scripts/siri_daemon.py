#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Siri Edge Glow & Voice AI Assistant Daemon for shell27 (Quickshell)
--------------------------------------------------------------------
- Offline Wake Word listener ("Hey Siri", "Siri")
- Free Google Speech Recognition (STT)
- Google Gemini API (Free tier / GenAI SDK)
- TTS Speech synthesis (espeak-ng / piper)
- Quickshell IPC Bridge (qs -c shell27 ipc call siri ...)
"""

import sys
import os
import gc
from collections import deque
import json
import time
import argparse
import subprocess
import threading
import re
import urllib.request
import urllib.parse
import shutil
import signal
from pathlib import Path

# ── AUTO-RESPAWN WITH VIRTUAL ENVIRONMENT ──
SCRIPT_DIR = Path(__file__).resolve().parent
SHELL27_DIR = SCRIPT_DIR.parent
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share"))
VENV_PYTHON = DATA_HOME / "shell27" / "venv" / "bin" / "python"
if not VENV_PYTHON.exists():
    VENV_PYTHON = SHELL27_DIR / "venv" / "bin" / "python"
LIB_DIR = SHELL27_DIR / "lib"

# Set LD_LIBRARY_PATH so OpenSSL 3 works seamlessly
if LIB_DIR.exists() and str(LIB_DIR) not in os.environ.get("LD_LIBRARY_PATH", ""):
    os.environ["LD_LIBRARY_PATH"] = str(LIB_DIR) + ((":" + os.environ["LD_LIBRARY_PATH"]) if "LD_LIBRARY_PATH" in os.environ else "")

if VENV_PYTHON.exists() and sys.executable != str(VENV_PYTHON) and "-c" not in sys.argv:
    try:
        os.execve(str(VENV_PYTHON), [str(VENV_PYTHON)] + sys.argv, os.environ)
    except Exception as e:
        print(f"[Warning] Failed to re-exec with venv python: {e}", file=sys.stderr)

# ── CONFIGURATION LOADER ──
CONFIG_FILE = SHELL27_DIR / "gemini_config.json"
SETTINGS_FILE = SHELL27_DIR / "siri_settings.json"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
DAEMON_PID_FILE = RUNTIME_DIR / f"shell27-siri-{os.getuid()}.pid"
DAEMON_LOCK_FILE = RUNTIME_DIR / f"shell27-siri-{os.getuid()}.lock"

DEFAULT_CONFIG = {
    "api_key": os.getenv("GEMINI_API_KEY", "YOUR_GEMINI_API_KEY_HERE"),
    "model": "gemini-3.1-flash-lite",
    "wake_words": ["hey siri", "siri", "hello siri", "hi siri", "hey google:", "ok google"],
    "live_voice_streaming": True,
    "language": "auto",       # "auto", "vi-VN", "en-US"
    "tts_engine": "edge-tts", # "edge-tts", "piper"
    "tts_voice_en": "en-US-JennyNeural",
    "tts_voice_vi": "vi-VN-NamMinhNeural",
    "speech_rate": 165
}

def load_config() -> dict:
    config = DEFAULT_CONFIG.copy()
    # Read siri_settings.json first
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                user_conf = json.load(f)
                config.update(user_conf)
        except Exception as e:
            print(f"[Config] Error reading {SETTINGS_FILE}: {e}")
    # Read gemini_config.json fallback
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                gem_conf = json.load(f)
                if gem_conf.get("api_key") and gem_conf.get("api_key") != "YOUR_GEMINI_API_KEY_HERE":
                    config["api_key"] = gem_conf.get("api_key")
                if gem_conf.get("model"):
                    config["model"] = gem_conf.get("model")
        except Exception as e:
            print(f"[Config] Error reading {CONFIG_FILE}: {e}")
    # Environment variable override
    env_key = os.getenv("GEMINI_API_KEY")
    if env_key:
        config["api_key"] = env_key
    return config

CONFIG = load_config()

def spoken_responses_enabled() -> bool:
    try:
        with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
            response_type = json.load(f).get("preferred_response_type", "spoken")
    except Exception:
        response_type = CONFIG.get("preferred_response_type", "spoken")
    return response_type != "silent"

# ── QUICKSHELL IPC WRAPPER ──
class SiriIPC:
    @staticmethod
    def call(action: str, *args):
        """Invoke Quickshell IPC method on target 'siri'."""
        cmd = ["qs", "-c", "shell27", "ipc", "call", "siri", action] + [str(a) for a in args]
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.0)
        except Exception:
            pass

    @classmethod
    def activate(cls, on: bool = True):
        cls.call("activate", "true" if on else "false")

    @classmethod
    def set_state(cls, state: str):
        # "idle", "listening", "thinking", "speaking"
        cls.call("state", state)

    @classmethod
    def set_prompt(cls, text: str):
        cls.call("prompt", text)

    @classmethod
    def set_response(cls, text: str):
        cls.call("response", text)

    @classmethod
    def set_sources(cls, sources: list[str]):
        cls.call("sources", json.dumps(sources))

    @classmethod
    def voice_timeout(cls, reason: str = ""):
        if reason:
            cls.call("voice_timeout", reason)
        else:
            cls.call("voice_timeout")

    @classmethod
    def set_audio_level(cls, level: float):
        cls.call("audioLevel", f"{level:.2f}")

    @classmethod
    def set_voice_active(cls, active: bool):
        cls.call("voiceActive", "true" if active else "false")

    @classmethod
    def open_type(cls):
        cls.call("open_type")

    @classmethod
    def visual_message(cls, text: str, image_path: str):
        cls.call("visual_message", text, image_path)

    @classmethod
    def dismiss(cls):
        cls.call("dismiss")


class SiriAppIPC:
    @staticmethod
    def call(action: str, *args):
        cmd = ["qs", "-c", "shell27", "ipc", "call", "siri_app", action] + [str(a) for a in args]
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.0)
        except Exception:
            pass

    @classmethod
    def response(cls, chat_id: str, text: str):
        cls.call("response", chat_id, text)

    @classmethod
    def user_message(cls, chat_id: str, text: str):
        cls.call("user_message", chat_id, text)

    @classmethod
    def voice_state(cls, chat_id: str, active: bool):
        cls.call("voice_state", chat_id, "true" if active else "false")

    @classmethod
    def sources(cls, chat_id: str, value: list[str]):
        cls.call("sources", chat_id, json.dumps(value))


def emit_siri_app_event(event: str, chat_id: str, value):
    print("SIRI_APP_EVENT:" + json.dumps({"event": event, "chatId": chat_id, "value": value}), flush=True)


# ── SYSTEM CONTROL TOOLS (GEMINI FUNCTION CALLING & LOCAL ROUTER) ──
def launch_app(app_name: str) -> str:
    """
    Launch an application on Linux (supporting Native apps and Flatpaks).
    Uses a multi-step Waterfall Fallback mechanism:
    1. Flatpak ID matching (flatpak list --app)
    2. Desktop entry lookup in application directories & gtk-launch
    3. Hyprland dispatcher (hyprctl dispatch exec) / direct PATH execution
    All processes are spawned asynchronously without blocking the daemon.
    """
    if not app_name or not app_name.strip():
        return "Please specify the application name to launch."

    clean_name = app_name.strip().lower()

    # ── STEP 1: FLATPAK ID MATCHING ──
    try:
        res = subprocess.run(
            ["flatpak", "list", "--app", "--columns=application,name"],
            capture_output=True, text=True, timeout=2.0
        )
        if res.returncode == 0:
            lines = res.stdout.strip().split("\n")
            for line in lines[1:]:  # Skip header
                parts = line.split("\t") if "\t" in line else line.split(None, 1)
                if parts:
                    app_id = parts[0].strip()
                    app_display_name = parts[1].strip() if len(parts) > 1 else app_id
                    id_tail = app_id.split(".")[-1].lower()

                    # Match against ID, display name, or end of ID (e.g. spotify -> com.spotify.Client)
                    if (clean_name in app_id.lower() or
                        clean_name in app_display_name.lower() or
                        clean_name == id_tail):
                        subprocess.Popen(
                            ["flatpak", "run", app_id],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True
                        )
                        return f"Opening {app_display_name}."
    except Exception as e:
        print(f"[LaunchApp] Flatpak check error: {e}")

    # ── STEP 2: DESKTOP ENTRY LOOKUP & GTK-LAUNCH ──
    desktop_dirs = [
        os.path.expanduser("~/.local/share/applications"),
        "/usr/share/applications",
        "/var/lib/flatpak/exports/share/applications",
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications")
    ]
    matched_desktop = None
    for d in desktop_dirs:
        if not os.path.isdir(d):
            continue
        try:
            for entry in os.listdir(d):
                if entry.endswith(".desktop"):
                    entry_base = entry[:-8].lower()
                    if clean_name == entry_base or clean_name in entry_base:
                        matched_desktop = entry[:-8]
                        break
                    # Check Name= line inside .desktop file
                    try:
                        filepath = os.path.join(d, entry)
                        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                            for fline in f:
                                if fline.startswith("Name=") and clean_name in fline[5:].strip().lower():
                                    matched_desktop = entry[:-8]
                                    break
                        if matched_desktop:
                            break
                    except Exception:
                        pass
            if matched_desktop:
                break
        except Exception:
            pass

    if matched_desktop:
        try:
            subprocess.Popen(
                ["gtk-launch", matched_desktop],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            return f"Opening {app_name}."
        except Exception as e:
            print(f"[LaunchApp] gtk-launch error: {e}")

    # ── STEP 3: HYPRLAND DISPATCHER OR DIRECT COMMAND EXECUTION ──
    try:
        if os.getenv("HYPRLAND_INSTANCE_SIGNATURE"):
            subprocess.Popen(
                ["hyprctl", "dispatch", "exec", clean_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            return f"Opening {app_name}."
    except Exception:
        pass

    try:
        subprocess.Popen(
            [clean_name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        return f"Opening {app_name}."
    except Exception as e:
        return f"Could not find or launch application '{app_name}'."

def open_url(url: str) -> str:
    """Open a web URL in the default browser using xdg-open."""
    clean_url = url.strip()
    if not clean_url.startswith(("http://", "https://")):
        clean_url = "https://" + clean_url
    try:
        subprocess.Popen(["xdg-open", clean_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return f"Opened {clean_url} in browser."
    except Exception as e:
        return f"Failed to open URL {url}: {e}"

def play_music(platform: str, query: str) -> str:
    """Play music or search on Spotify (playerctl or web), YouTube, or Apple Music."""
    p = platform.lower().strip()
    q = query.strip()
    encoded_q = urllib.parse.quote(q)

    if "spotify" in p:
        try:
            res = subprocess.run(["playerctl", "-p", "spotify", "status"], capture_output=True, text=True)
            if "Playing" in res.stdout or "Paused" in res.stdout:
                subprocess.run(["playerctl", "-p", "spotify", "play"])
                return f"Resumed playback on Spotify for {q}."
        except Exception:
            pass
        open_url(f"https://open.spotify.com/search/{encoded_q}")
        return f"Playing {q} on Spotify."

    elif "youtube" in p:
        open_url(f"https://www.youtube.com/results?search_query={encoded_q}")
        return f"Searching and playing {q} on YouTube."

    elif "apple" in p:
        open_url(f"https://music.apple.com/us/search?term={encoded_q}")
        return f"Searching {q} on Apple Music."

    else:
        open_url(f"https://www.youtube.com/results?search_query={encoded_q}")
        return f"Playing {q}."

def fetch_weather(location: str = "") -> dict:
    """
    Get detailed real-time weather data and forecast for a given location or city.
    If no location is specified, use the city resolved by the Weather widget.
    Returns structured metrics including temperature, feels-like, humidity, condition, rain chance, and UV index.
    """
    import unicodedata
    loc = location.strip() if location and location.strip() else ""
    if not loc:
        try:
            widget_settings = json.loads((Path.home() / ".config" / "macwidgets" / "settings.json").read_text(encoding="utf-8"))
            loc = str(widget_settings.get("weatherLocation") or "").strip()
            if not loc and widget_settings.get("locMode") == "city":
                loc = str(widget_settings.get("cityName") or "").strip()
        except Exception:
            pass
    if not loc:
        return {"error": "The Weather widget has not resolved a location yet."}

    # Remove accents for wttr.in URL parameter
    clean_loc = "".join(c for c in unicodedata.normalize("NFD", loc) if unicodedata.category(c) != "Mn").replace("đ", "d").replace("Đ", "D")
    loc_param = clean_loc.replace(" ", "+")

    try:
        req = urllib.request.Request(f"https://wttr.in/{loc_param}?format=j1", headers={"User-Agent": "curl/8.0"})
        with urllib.request.urlopen(req, timeout=4.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            curr = data.get("current_condition", [{}])[0]
            today = data.get("weather", [{}])[0]
            hourly = today.get("hourly", [{}])

            # Calculate maximum chance of rain today
            rain_chances = []
            for h in hourly:
                try:
                    rain_chances.append(int(h.get("chanceofrain", 0)))
                except (ValueError, TypeError):
                    pass
            max_rain_chance = max(rain_chances) if rain_chances else 0

            desc_list = curr.get("weatherDesc", [{}])
            weather_desc = desc_list[0].get("value", "Clear") if desc_list else "Clear"

            return {
                "location": loc.title(),
                "temperature_c": curr.get("temp_C", "N/A"),
                "feels_like_c": curr.get("FeelsLikeC", "N/A"),
                "humidity_percent": curr.get("humidity", "N/A"),
                "condition": weather_desc,
                "wind_speed_kmph": curr.get("windspeedKmph", "N/A"),
                "uv_index": curr.get("uvIndex", "N/A"),
                "max_temp_c": today.get("maxtempC", "N/A"),
                "min_temp_c": today.get("mintempC", "N/A"),
                "chance_of_rain_percent": max_rain_chance
            }
    except Exception as e:
        return {
            "location": loc,
            "error": f"Could not retrieve weather: {e}"
        }

def search_files(keyword: str) -> str:
    """Quickly search files and directories in home folder or .config matching the keyword."""
    clean_kw = keyword.strip().replace("'", "").replace('"', "")
    home = os.path.expanduser("~")
    try:
        if subprocess.run(["which", "fd"], capture_output=True).returncode == 0:
            res = subprocess.run(["fd", "-i", "-t", "f", "-max-depth", "4", clean_kw, home], capture_output=True, text=True, timeout=4)
            files = [line.strip() for line in res.stdout.strip().split("\n") if line.strip()][:5]
            if files:
                return "Found files:\n" + "\n".join(files)
        res = subprocess.run(["find", home, "-maxdepth", "4", "-iname", f"*{clean_kw}*", "-not", "-path", "*/.cache/*", "-not", "-path", "*/.git/*"], capture_output=True, text=True, timeout=4)
        files = [line.strip() for line in res.stdout.strip().split("\n") if line.strip()][:5]
        if files:
            return "Found files:\n" + "\n".join(files)
        return f"No files matching '{keyword}' found."
    except Exception as e:
        return f"Error searching files: {e}"


def take_screenshot(region: str = "full") -> str:
    """Take a full or region screenshot using grim, copy to clipboard, and play shutter sound."""
    pictures_dir = Path.home() / "Pictures" / "Screenshots"
    pictures_dir.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%d_%H-%M-%S")
    filepath = pictures_dir / f"Screenshot_{timestamp}.png"

    try:
        if region in ["selection", "area", "region"]:
            res = subprocess.run(f"grim -g \"$(slurp)\" '{filepath}'", shell=True, capture_output=True)
        else:
            res = subprocess.run(["grim", str(filepath)], capture_output=True)

        if res.returncode == 0 and filepath.exists():
            # Copy image to clipboard
            try:
                subprocess.run(f"wl-copy < '{filepath}'", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
            # Play authentic camera shutter sound
            shutter_sound = Path.home() / ".local" / "share" / "sounds" / "shell27" / "shutter.wav"
            if not shutter_sound.exists():
                shutter_sound = Path("/usr/share/sounds/freedesktop/stereo/camera-shutter.oga")
            if shutter_sound.exists():
                subprocess.Popen(["pw-play", str(shutter_sound)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return "Screenshot captured and saved to Screenshots."
        else:
            return "Could not capture screenshot."
    except Exception as e:
        return f"Screenshot error: {e}"


# ── LOCAL-FIRST INTENT ROUTER (0 AI TOKENS) ──
def normalize_text(text: str) -> str:
    """Normalize text by converting to lowercase and stripping accents."""
    import unicodedata
    n = "".join(c for c in unicodedata.normalize("NFD", text.lower().strip()) if unicodedata.category(c) != "Mn")
    return n.replace("đ", "d").replace("Đ", "D")

def handle_local_intent(query: str):
    """
    Local-First Intent Router:
    Execute system tasks locally with 0 AI tokens.
    Weather inquiries are forwarded directly to Gemini AI with fetch_weather tool.
    Returns response string if handled, or None to fallback to Gemini AI.
    """
    raw_q = query.strip()
    norm_q = normalize_text(raw_q)
    if not norm_q:
        return None

    # 0. SCREENSHOT
    screenshot_keywords = ["screenshot", "capture screen", "take a screenshot", "take screenshot", "screen capture", "snip"]
    for sk in screenshot_keywords:
        if sk in norm_q:
            is_selection = any(k in norm_q for k in ["area", "selection", "select", "crop", "region"])
            return take_screenshot("selection" if is_selection else "full")

    # SYSTEM CONTROLS (Dark Mode, Brightness, Volume)
    if any(k in norm_q for k in ["dark mode", "turn on dark mode", "enable dark mode"]):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"], stdout=subprocess.DEVNULL)
        return "Switched to Dark Mode."
    elif any(k in norm_q for k in ["light mode", "turn on light mode", "enable light mode"]):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-light"], stdout=subprocess.DEVNULL)
        return "Switched to Light Mode."
    elif any(k in norm_q for k in ["Hey", "Hi", "Hello", "Greetings", "Good morning", "Good afternoon", "Good evening"]):
        subprocess.run(["echo", "hello world"], stdout=subprocess.DEVNULL)
        return "Hello."
    elif any(k in norm_q for k in ["increase brightness", "brightness up", "turn up brightness", "raise brightness"]):
        subprocess.run(["brightnessctl", "s", "+10%"], stdout=subprocess.DEVNULL)
        return "Increased screen brightness."
    elif any(k in norm_q for k in ["decrease brightness", "brightness down", "turn down brightness", "lower brightness"]):
        subprocess.run(["brightnessctl", "s", "10%-"], stdout=subprocess.DEVNULL)
        return "Decreased screen brightness."
    elif any(k in norm_q for k in ["volume up", "increase volume", "turn up volume", "raise volume", "louder"]):
        subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "10%+"], stdout=subprocess.DEVNULL)
        return "Increased volume."
    elif any(k in norm_q for k in ["volume down", "decrease volume", "turn down volume", "lower volume", "softer", "quieter"]):
        subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "10%-"], stdout=subprocess.DEVNULL)
        return "Decreased volume."
    elif any(k in norm_q for k in ["mute", "unmute", "toggle mute", "silence"]):
        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"], stdout=subprocess.DEVNULL)
        return "Toggled mute."

    # 1. MUSIC PLAYBACK
    music_keywords = ["play music", "play song", "play track", "play"]
    for mk in music_keywords:
        if norm_q.startswith(mk + " ") or norm_q == mk:
            track = re.sub(rf'^.*?{mk}\s*', '', norm_q).strip()
            is_spotify = "spotify" in norm_q
            track = re.sub(r'\b(on)?\s*(youtube|spotify)\b', '', track).strip()
            if not track:
                track = "lofi chill"
            if is_spotify:
                return play_music("spotify", track)
            else:
                return play_music("youtube", track)

    # 2. WEB SEARCH
    search_keywords = ["search for", "google", "search"]
    for sk in search_keywords:
        if norm_q.startswith(sk + " "):
            term = re.sub(rf'^{sk}\s*', '', raw_q).strip()
            if term:
                open_url(f"https://www.google.com/search?q={urllib.parse.quote(term)}")
                return f"Searching Google for '{term}'."

    # 3. LAUNCH APPS
    app_keywords = ["launch", "open application", "open app", "open", "run"]
    for ak in app_keywords:
        if norm_q.startswith(ak + " "):
            app_target = norm_q[len(ak):].strip()
            if app_target.startswith(("music", "song", "track", "web", "site", "page")):
                continue
            app_map = {
                "browser": "firefox",
                "web browser": "firefox",
                "terminal": "kitty",
                "console": "kitty",
                "vs code": "code",
                "vscode": "code",
                "file manager": "dolphin",
                "files": "dolphin",
                "music": "spotify"
            }
            exec_name = app_map.get(app_target, app_target)
            return launch_app(exec_name)

    # 4. SEARCH FILES
    file_keywords = ["search file", "find file", "search files", "find files"]
    for fk in file_keywords:
        if fk in norm_q:
            kw = re.sub(rf'^.*?{fk}\s*', '', norm_q).strip()
            if kw:
                return search_files(kw)

    # Fallback to Gemini AI for reasoning, weather, code, translation, etc.
    return None


# ── GEMINI API INTEGRATION ──
def extract_answer_sources(text: str) -> tuple[str, list[str]]:
    marker = re.search(r"(?im)^\s*(?:sources|references)\s*:", text)
    if not marker:
        return text.strip(), []

    urls = []
    for candidate in re.findall(r"https://[^\s<>\]\)\"'|]+", text[marker.end():], flags=re.IGNORECASE):
        url = candidate.rstrip(".,;:!?)\"]}")
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme == "https" and parsed.hostname and url not in urls:
            urls.append(url)
        if len(urls) == 2:
            break
    return text[:marker.start()].strip(), urls


def query_gemini(prompt: str, image_path: str | None = None, app_chat_id: str | None = None,
                 app_stdout: bool = False) -> str:
    """Send a text or image question to Gemini and return its text response."""
    global CONFIG
    CONFIG = load_config()

    api_key = CONFIG.get("api_key", "").strip()
    if not api_key or api_key == "YOUR_GEMINI_API_KEY_HERE":
        return "Please configure your Gemini API key in Settings -> Apple Intelligence & Siri."

    preferred_model = CONFIG.get("visual_model") if image_path and CONFIG.get("visual_model") else CONFIG.get("model", "gemini-3.1-flash-lite")
    fallback_models = [preferred_model, "gemini-3.1-flash-lite", "gemini-3.5-flash", "gemini-3.8-flash"]
    models_to_try = []
    for m in fallback_models:
        if m and m not in models_to_try:
            models_to_try.append(m)

    system_instruction = (
        "You are Siri, Apple's intelligent assistant on the shell27 Operating System. "
        "Keep your answers direct, concise, natural for speech, and helpful. "
        "Use available tools when asked to launch apps, open URLs, play music, fetch weather, or search files. "
        "When answering weather inquiries using the fetch_weather tool, synthesize a natural, friendly spoken reply "
        "(mention temperature, feels-like if significantly different, conditions, and practical advice like bringing an umbrella if rain chance is high). "
        "If the user does not specify a location for weather, use the Weather widget's configured city. "
        "For factual answers, finish with a separate final SOURCES block containing exactly two credible HTTPS URLs, "
        "one per line. Keep the URLs out of the spoken answer, and never invent sources. "
        "Do not use markdown bolding (**) or bullet points (*) because your reply will be read aloud by TTS."
    )

    from google import genai
    from google.genai import types

    client = genai.Client(
        api_key=api_key,
        http_options=types.HttpOptions(timeout=12000)
    )
    config = types.GenerateContentConfig(
        system_instruction=system_instruction,
        tools=[launch_app, open_url, play_music, fetch_weather, search_files, take_screenshot],
        temperature=0.3
    )
    message = prompt
    if image_path:
        message = [prompt, types.Part.from_bytes(data=Path(image_path).read_bytes(), mime_type="image/png")]

    last_error = ""
    for model_name in models_to_try:
        try:
            chat = client.chats.create(model=model_name, config=config)
            response = chat.send_message(message)
            if response and response.text:
                answer, sources = extract_answer_sources(response.text.strip())
                if app_stdout:
                    emit_siri_app_event("sources", app_chat_id or "", sources)
                elif app_chat_id is None:
                    SiriIPC.set_sources(sources)
                else:
                    SiriAppIPC.sources(app_chat_id, sources)
                return answer
            last_error = f"{model_name} returned an empty response."
        except Exception as e:
            last_error = str(e)

    return f"I'm sorry, I encountered an issue contacting Gemini: {last_error[:120]}"


# ── TEXT TO SPEECH (TTS) & SINGLE-SPEAKER MUTEX ──
IS_SPEAKING = False
LAST_SPEAK_FINISH = 0.0
LAST_SPOKEN_TEXT = ""
CURRENT_PLAYER_PROC = None
SPEECH_LOCK = threading.Lock()
SPEECH_PID_FILE = "/tmp/shell27_siri_speech.pid"
VOICE_MUTE_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / f"shell27-siri-muted-{os.getuid()}"

def stop_all_speech():
    """Immediately stop all ongoing speech synthesis and playback across processes."""
    global CURRENT_PLAYER_PROC, IS_SPEAKING
    IS_SPEAKING = False

    # 1. Terminate current process player if active
    if CURRENT_PLAYER_PROC is not None:
        try:
            CURRENT_PLAYER_PROC.kill()
        except Exception:
            pass
        CURRENT_PLAYER_PROC = None

    # 2. Terminate the previous Siri audio process, never its owning daemon
    if os.path.exists(SPEECH_PID_FILE):
        try:
            with open(SPEECH_PID_FILE, "r") as pf:
                old_pid = int(pf.read().strip())
            old_cmdline = Path(f"/proc/{old_pid}/cmdline").read_bytes().decode(errors="replace")
            if old_pid != os.getpid() and ("siri_speech_" in old_cmdline or "espeak-ng" in old_cmdline):
                os.kill(old_pid, 15)
        except Exception:
            pass
        try:
            os.remove(SPEECH_PID_FILE)
        except OSError:
            pass

    # 3. Kill any rogue mpv or espeak-ng instances playing Siri audio
    try:
        subprocess.run(["pkill", "-9", "-f", "siri_speech"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    try:
        subprocess.run(["killall", "-9", "espeak-ng"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def is_vietnamese(text: str) -> bool:
    """Check if the response contains Vietnamese characters."""
    return bool(re.search(r'[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]', text, re.IGNORECASE))

def map_to_neural_voice(voice: str, is_vi: bool) -> str:
    """Map voice name to pristine Microsoft Edge Neural voices (studio grade, no buzzing)."""
    if is_vi:
        if any(k in voice for k in ["m1", "m2", "NamMinh", "nam"]):
            return "vi-VN-NamMinhNeural"
        return "vi-VN-HoaiMyNeural"
    else:
        if any(k in voice for k in ["m3", "Guy", "male"]):
            return "en-US-GuyNeural"
        elif any(k in voice for k in ["Aria", "aria"]):
            return "en-US-AriaNeural"
        elif any(k in voice for k in ["Ryan", "ryan"]):
            return "en-GB-RyanNeural"
        elif any(k in voice for k in ["gb", "Sonia", "british"]):
            return "en-GB-SoniaNeural"
        elif any(k in voice for k in ["Natasha", "natasha", "australian"]):
            return "en-AU-NatashaNeural"
        return "en-US-JennyNeural"

def speak(text: str, force: bool = False):
    """Read text aloud with pristine Neural TTS (edge-tts), strictly ensuring ONLY ONE speaker plays."""
    global IS_SPEAKING, LAST_SPEAK_FINISH, LAST_SPOKEN_TEXT, CURRENT_PLAYER_PROC
    if not force and not spoken_responses_enabled():
        return
    if VOICE_MUTE_FILE.exists():
        return
    clean_text = re.sub(r'[*_#`~]', '', text).strip()
    if not clean_text:
        return

    # Strictly kill any ongoing or overlapping speech before starting this one!
    stop_all_speech()

    with SPEECH_LOCK:
        IS_SPEAKING = True
        LAST_SPOKEN_TEXT = clean_text.lower()

        is_vi = is_vietnamese(clean_text)
        cfg_voice = CONFIG.get("tts_voice_vi" if is_vi else "tts_voice_en", "vi" if is_vi else "en-us+f3")
        neural_voice = map_to_neural_voice(cfg_voice, is_vi)

        # Calculate speech rate string (e.g. "+5%", "-10%")
        speech_rate = CONFIG.get("speech_rate", 165)
        rate_percent = int(round((speech_rate - 165) / 165.0 * 80))
        rate_str = f"{rate_percent:+d}%"

        # Pulsing thread while TTS is playing
        stop_pulse = threading.Event()
        level_queue = deque([0.30, 0.55, 0.70, 0.45, 0.65, 0.40, 0.75, 0.50], maxlen=16)

        def pulse_loop():
            idx = 0
            q_len = len(level_queue)
            while not stop_pulse.is_set():
                SiriIPC.set_audio_level(level_queue[idx % q_len])
                idx += 1
                time.sleep(0.12)
            SiriIPC.set_audio_level(0.0)

        pulse_thread = threading.Thread(target=pulse_loop, daemon=True)
        pulse_thread.start()

        tmp_audio = f"/tmp/shell27_siri_speech_{os.getpid()}.mp3"
        played = False

        # 1. High Quality Edge Neural TTS (Pristine audio, no buzzing / no distortion)
        edge_bin = os.path.expanduser("~/.config/quickshell/shell27/venv/bin/edge-tts")
        if not os.path.exists(edge_bin):
            edge_bin = shutil.which("edge-tts")

        if edge_bin:
            try:
                res = subprocess.run(
                    [edge_bin, "--voice", neural_voice, "--rate", rate_str, "--text", clean_text, "--write-media", tmp_audio],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    env=os.environ,
                    timeout=18
                )
                if os.path.exists(tmp_audio) and os.path.getsize(tmp_audio) > 0:
                    CURRENT_PLAYER_PROC = subprocess.Popen(
                        ["mpv", "--no-terminal", "--really-quiet", "--volume=100", tmp_audio],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                    with open(SPEECH_PID_FILE, "w") as pf:
                        pf.write(str(CURRENT_PLAYER_PROC.pid))
                    CURRENT_PLAYER_PROC.wait()
                    CURRENT_PLAYER_PROC = None
                    played = True
            except Exception as e:
                print(f"[TTS] Neural TTS notice: {e}", file=sys.stderr)

        # 2. Fallback: Gentle notification sound if offline instead of harsh espeak-ng
        if not played:
            try:
                chime_sound = Path.home() / ".local" / "share" / "sounds" / "shell27" / "tink.wav"
                if chime_sound.exists():
                    subprocess.run(["pw-play", str(chime_sound)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

        # Cleanup temporary mp3 file
        if os.path.exists(tmp_audio):
            try:
                os.remove(tmp_audio)
            except OSError:
                pass

        if os.path.exists(SPEECH_PID_FILE):
            try:
                os.remove(SPEECH_PID_FILE)
            except OSError:
                pass

        stop_pulse.set()
        pulse_thread.join(timeout=0.5)

        # Acoustic cooldown: wait 0.8s to allow room sound reverberation to dissipate
        time.sleep(0.8)
        LAST_SPEAK_FINISH = time.time()
        IS_SPEAKING = False
        gc.collect()


# ── UNIFIED REAL-TIME AUDIO RECORDER & LEVEL STREAMER (ZERO-NUMPY PURE C AUDIOOP) ──
def record_speech_with_levels(recognizer=None, timeout=15.0, phrase_time_limit=30.0, silence_timeout=2.5, live_streaming=True):
    """
    Record speech using lightweight sounddevice and native C audioop (Zero numpy overhead).
    Continuously streams live microphone volume to QML edge glow waves.
    Automatically detects speech start and speech finish (VAD), returns sr.AudioData.
    Supports real-time partial STT streaming directly into TypeToSiri text box.
    Saves over 500MB+ virtual memory, zero segfaults!
    """
    import sounddevice as sd
    import audioop
    import speech_recognition as sr

    frames = []
    has_spoken = False
    is_voice_active = False
    has_opened_type = False
    silence_start = None
    start_time = time.time()
    last_ipc_send = 0.0
    last_stream_transcribe = 0.0
    stream_worker_busy = False
    frame_lock = threading.Lock()

    def partial_transcribe_worker(snapshot_bytes):
        nonlocal stream_worker_busy
        try:
            if recognizer is None:
                return
            part_audio = sr.AudioData(snapshot_bytes, 16000, 2)
            lang_pref = CONFIG.get("language", "auto")
            text = ""
            if lang_pref in ["auto", "en", "en-US"]:
                try:
                    text = recognizer.recognize_google(part_audio, language="en-US")
                except Exception:
                    pass
            else:
                try:
                    text = recognizer.recognize_google(part_audio, language=lang_pref)
                except Exception:
                    pass
            if text and text.strip():
                print(f"[Streaming STT] \"{text.strip()}\"")
                SiriIPC.set_prompt(text.strip())
        except Exception:
            pass
        finally:
            stream_worker_busy = False

    def audio_callback(indata, frame_count, time_info, status):
        nonlocal has_spoken, is_voice_active, has_opened_type, silence_start, last_ipc_send
        raw_chunk = bytes(indata)
        with frame_lock:
            frames.append(raw_chunk)

        # Ultra-fast native C calculation of audio RMS (0 memory allocations)
        rms = audioop.rms(raw_chunk, 2) / 32768.0

        now = time.time()
        # Voice Activity Detection (VAD)
        if rms > 0.005:
            has_spoken = True
            silence_start = None
            if not is_voice_active:
                is_voice_active = True
                SiriIPC.set_voice_active(True)
                if live_streaming and not has_opened_type:
                    has_opened_type = True
                    SiriIPC.open_type()
        elif has_spoken and silence_start is None:
            silence_start = time.time()
            if is_voice_active:
                is_voice_active = False
                SiriIPC.set_voice_active(False)

        # Throttled audio level indicator
        if now - last_ipc_send >= 0.05:
            last_ipc_send = now
            lvl = 1.0 if is_voice_active else 0.0
            SiriIPC.set_audio_level(lvl)

    try:
        with sd.InputStream(channels=1, samplerate=16000, dtype='int16', blocksize=512, callback=audio_callback):
            while True:
                time.sleep(0.04)
                now = time.time()
                elapsed = now - start_time

                # Silence timeout: if user stopped speaking for 2.5s, finalize and break!
                if has_spoken and silence_start and (now - silence_start >= silence_timeout):
                    print(f"[VAD] Silence detected for {silence_timeout}s. Finalizing request automatically...")
                    break

                # Max phrase limit
                if elapsed >= phrase_time_limit:
                    break

                # Timeout if no speech heard at all
                if not has_spoken and (elapsed >= timeout):
                    break

                # Live Voice Streaming: periodically transcribe accumulated audio in background
                if live_streaming and has_spoken and (now - last_stream_transcribe >= 0.85):
                    last_stream_transcribe = now
                    if not stream_worker_busy:
                        with frame_lock:
                            if len(frames) >= 16:
                                snapshot = b"".join(frames)
                                stream_worker_busy = True
                                threading.Thread(target=partial_transcribe_worker, args=(snapshot,), daemon=True).start()
    finally:
        SiriIPC.set_voice_active(False)
        SiriIPC.set_audio_level(0.0)

    if not has_spoken or not frames:
        return None

    raw_bytes = b"".join(frames)
    return sr.AudioData(raw_bytes, 16000, 2)


# ── ASSISTANT INTERACTION CYCLE ──
def run_assistant_cycle(recognizer=None, mic=None, voice_only=False):
    """
    1. Activate edge glow UI (listening state).
    2. Stream live microphone volume to edge glow waves.
    3. Convert speech to text via SpeechRecognition (free STT).
    4. Send prompt to Gemini AI or execute local app command.
    5. Speak response and update UI.
    6. Automatically dismiss Siri once task/speech is finished.
    """
    global CONFIG
    CONFIG = load_config()
    live_streaming = CONFIG.get("live_voice_streaming", True) and not voice_only

    import speech_recognition as sr
    if recognizer is None:
        recognizer = sr.Recognizer()

    print("\n[Siri] Activated! Listening for your request...")
    SiriIPC.activate(True)
    SiriIPC.set_state("listening")
    SiriIPC.set_prompt("Listening...")
    SiriIPC.set_response("")
    SiriIPC.set_sources([])

    user_query = ""

    try:
        audio = record_speech_with_levels(
            recognizer=recognizer,
            timeout=5.0 if voice_only else 15.0,
            phrase_time_limit=30.0,
            silence_timeout=5.0 if voice_only else 2.5,
            live_streaming=live_streaming
        )
        if not audio:
            print("[Siri] No speech heard in time.")
            if voice_only:
                SiriIPC.voice_timeout("No microphone was found. Voice-only mode will currently be unavailable.")
            else:
                SiriIPC.set_prompt("Listening timed out. Press Space to type.")
            SiriIPC.set_state("idle")
            return
    except Exception as e:
        print(f"[Siri] Microphone recording error: {e}")
        msg = "No microphone was found. Voice-only mode will currently be unavailable."
        if voice_only:
            SiriIPC.voice_timeout(msg)
        SiriIPC.set_prompt(msg)
        time.sleep(1.2)
        SiriIPC.set_state("idle")
        return

    print("[Siri] Processing speech (Silence 2.5s reached)...")
    SiriIPC.set_state("thinking")
    SiriIPC.set_prompt("Processing speech...")

    # Language selection
    lang_pref = CONFIG.get("language", "auto")
    try:
        if lang_pref in ["auto", "en", "en-US"]:
            user_query = recognizer.recognize_google(audio, language="en-US")
        else:
            user_query = recognizer.recognize_google(audio, language=lang_pref)
    except Exception as e:
        print(f"[Siri] Recognition error: {e}")
        if voice_only:
            SiriIPC.voice_timeout("Sorry, could not understand audio.")
        SiriIPC.set_prompt("Sorry, could not understand audio.")
        time.sleep(1.2)
        SiriIPC.set_state("idle")
        return

    print(f"[User]  \"{user_query}\"")
    SiriIPC.set_prompt(user_query)
    SiriIPC.set_state("thinking")

    try:
        # Check Local-First Intent Router (e.g. open apps, volume, mute)
        local_ans = handle_local_intent(user_query)
        if local_ans:
            print(f"[Local Router] ⚡ Handled locally: \"{local_ans}\"")
            answer = local_ans
            SiriIPC.set_state("speaking")
            SiriIPC.set_response(answer)
            speak(answer)
            SiriIPC.set_state("idle")
            print("[Siri] Task completed successfully.\n")
            return
        else:
            print("[Siri] Forwarding to Gemini AI...")
            try:
                answer = query_gemini(user_query)
            except Exception as e:
                print(f"[Siri] Gemini request failed: {e}")
                answer = "Sorry, I couldn't complete that request."

        print(f"[Siri] \"{answer}\"")

        SiriIPC.set_state("speaking")
        SiriIPC.set_response(answer)

        # Read answer aloud with Neural TTS
        speak(answer)

        # Once speech has finished, transition state to idle
        SiriIPC.set_state("idle")
        print("[Siri] Response spoken completely.\n")
    finally:
        del user_query
        gc.collect()


# ── DAEMON CONTINUOUS LISTENER ──
def _run_daemon():
    """Continuously listen for wake-words with robust echo cancellation."""
    import speech_recognition as sr

    recognizer = sr.Recognizer()
    recognizer.dynamic_energy_threshold = True
    recognizer.pause_threshold = 0.6

    wake_words = [w.lower() for w in CONFIG.get("wake_words", ["hey siri", "siri", "ơi siri"])]

    print("═════════════════════════════════════════════════════════════════")
    print(" Shell27 Siri Voice Assistant Daemon is Running.")
    print(f" Wake words: {', '.join(wake_words)}")
    print(f" Gemini Model: {CONFIG.get('model', 'gemini-3.1-flash-lite')}")
    print(" press Ctrl+C in this terminal to stop.")
    print("═════════════════════════════════════════════════════════════════\n")

    # Verify microphone
    try:
        mic = sr.Microphone()
        with mic as source:
            print("[Init] Calibrating microphone for ambient noise...")
            recognizer.adjust_for_ambient_noise(source, duration=1.0)
            print("[Init] Calibration complete. Ready!")
    except Exception as e:
        print(f"[Error] Failed to initialize microphone: {e}", file=sys.stderr)
        return

    cycle_count = 0
    while True:
        try:
            # ANTI-LOOP: If speaking or within 2.5s cooldown after speaking, skip mic recording
            # to strictly prevent speaker echo from triggering wake word!
            if IS_SPEAKING or (time.time() - LAST_SPEAK_FINISH < 2.5):
                time.sleep(0.3)
                continue

            with mic as source:
                audio = recognizer.listen(source, timeout=None, phrase_time_limit=4.0)

            # Re-check speaking flag after recording chunk
            if IS_SPEAKING or (time.time() - LAST_SPEAK_FINISH < 2.5):
                del audio
                continue

            # Recognize short wake word snippet
            try:
                heard = recognizer.recognize_google(audio, language="en-US").lower()

                # Self-Echo Filter: Ignore if snippet contains words from Siri's own recent response
                if LAST_SPOKEN_TEXT and any(w in LAST_SPOKEN_TEXT for w in heard.split() if len(w) > 3):
                    print(f"[Echo Filter] Discarded room speaker feedback: \"{heard}\"")
                    continue

                matched = any(w in heard for w in wake_words)
                if matched:
                    print(f"\n[Trigger] Detected wake word in: \"{heard}\"")
                    run_assistant_cycle(recognizer, mic)

            except sr.UnknownValueError:
                pass
            except sr.RequestError as e:
                time.sleep(1.0)
            finally:
                del audio
                cycle_count += 1
                if cycle_count >= 8:
                    cycle_count = 0
                    gc.collect()

        except KeyboardInterrupt:
            print("\n[Siri] Stopping daemon gracefully...")
            SiriIPC.activate(False)
            gc.collect()
            break
        except Exception as e:
            time.sleep(0.5)


def _managed_daemon_pid():
    try:
        pid = int(DAEMON_PID_FILE.read_text(encoding="utf-8").strip())
        os.kill(pid, 0)
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace").split("\0")
        if str(SCRIPT_DIR / "siri_daemon.py") in cmdline:
            return pid
    except (OSError, ValueError):
        pass
    return None


def start_daemon():
    import fcntl

    lock_file = open(DAEMON_LOCK_FILE, "w", encoding="utf-8")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("[Siri] Daemon is already running.")
        lock_file.close()
        return

    DAEMON_PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    try:
        _run_daemon()
    finally:
        try:
            if DAEMON_PID_FILE.read_text(encoding="utf-8").strip() == str(os.getpid()):
                DAEMON_PID_FILE.unlink()
        except OSError:
            pass
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()


def start_managed_daemon():
    import fcntl

    with open(DAEMON_LOCK_FILE, "w", encoding="utf-8") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("[Siri] Daemon is already running.")
            return

        pid = _managed_daemon_pid()
        if pid:
            print(f"[Siri] Daemon is already running (PID {pid}).")
            return

        try:
            DAEMON_PID_FILE.unlink()
        except FileNotFoundError:
            pass

        process = subprocess.Popen(
            [sys.executable, str(SCRIPT_DIR / "siri_daemon.py"), "--daemon"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
        DAEMON_PID_FILE.write_text(str(process.pid), encoding="utf-8")
        print(f"[Siri] Daemon started (PID {process.pid}).")


def stop_managed_daemon():
    pid = _managed_daemon_pid()
    if not pid:
        try:
            DAEMON_PID_FILE.unlink()
        except FileNotFoundError:
            pass
        print("[Siri] Daemon is not running.")
        return

    try:
        os.kill(pid, signal.SIGINT)
        print(f"[Siri] Stop requested (PID {pid}).")
    except ProcessLookupError:
        print("[Siri] Daemon is not running.")


# ── DIRECT QUERY TEST ──
def handle_query_mode(query_text: str, enable_tts: bool = True, image_path: str | None = None,
                      app_chat_id: str | None = None, app_stdout: bool = False):
    """Test Gemini API and UI response card directly without voice input."""
    print(f"\n[Test Query] Prompt: \"{query_text}\"")
    if app_chat_id is None and not app_stdout:
        SiriIPC.activate(True)
        if image_path:
            SiriIPC.visual_message(query_text, image_path)
        else:
            SiriIPC.open_type()
        SiriIPC.set_state("thinking")
        if not image_path:
            SiriIPC.set_prompt(query_text)
        SiriIPC.set_response("Processing request...")
        SiriIPC.set_sources([])
    elif app_stdout:
        emit_siri_app_event("sources", app_chat_id or "", [])
    else:
        SiriAppIPC.sources(app_chat_id, [])

    # Check Local-First Intent Router (0 AI Tokens)
    local_ans = handle_local_intent(query_text) if not image_path else None
    if local_ans:
        print(f"[Local Router] Handled locally (0 tokens): \"{local_ans}\"")
        answer = local_ans
    else:
        print("[Siri] Forwarding to Gemini AI...")
        try:
            answer = query_gemini(query_text, image_path=image_path, app_chat_id=app_chat_id, app_stdout=app_stdout)
        except Exception as e:
            print(f"[Siri] Gemini request failed: {e}")
            answer = "Sorry, I couldn't complete that request."

    print(f"[Response] {answer}")

    if app_stdout:
        emit_siri_app_event("response", app_chat_id or "", answer)
    elif app_chat_id is None:
        SiriIPC.set_state("speaking" if enable_tts else "idle")
        SiriIPC.set_response(answer)
    else:
        SiriAppIPC.response(app_chat_id, answer)

    if enable_tts:
        print("[TTS] Reading response aloud with Neural TTS...")
        speak(answer)
        if app_chat_id is None and not app_stdout:
            SiriIPC.set_state("idle")
        print("[Siri] Query response finished.")
    else:
        if app_chat_id is None and not app_stdout:
            SiriIPC.set_state("idle")
    gc.collect()
    print("[Done] Query finished successfully.")


def handle_app_query_mode(query_text: str, chat_id: str, image_path: str | None = None,
                          voice_reply: bool = False, standalone: bool = False):
    handle_query_mode(query_text, enable_tts=voice_reply, image_path=image_path, app_chat_id=chat_id,
                      app_stdout=standalone)


def handle_app_voice_mode(chat_id: str, standalone: bool = False):
    if standalone:
        emit_siri_app_event("voice", chat_id, True)
    else:
        SiriAppIPC.voice_state(chat_id, True)
    try:
        import speech_recognition as sr

        recognizer = sr.Recognizer()
        audio = record_speech_with_levels(recognizer=recognizer, timeout=15.0, phrase_time_limit=30.0,
                                          silence_timeout=2.5, live_streaming=False)
        if not audio:
            response = "I didn't hear anything. Try voice mode again."
            if standalone:
                emit_siri_app_event("response", chat_id, response)
            else:
                SiriAppIPC.response(chat_id, response)
            return
        language = CONFIG.get("language", "auto")
        transcript = recognizer.recognize_google(audio, language="en-US" if language in ("auto", "en", "en-US") else language)
        if standalone:
            emit_siri_app_event("user", chat_id, transcript)
        else:
            SiriAppIPC.user_message(chat_id, transcript)
        handle_app_query_mode(transcript, chat_id, voice_reply=True, standalone=standalone)
    except Exception as e:
        print(f"[Siri App] Voice input failed: {e}")
        response = "Voice input is unavailable or could not be understood."
        if standalone:
            emit_siri_app_event("response", chat_id, response)
        else:
            SiriAppIPC.response(chat_id, response)
    finally:
        if standalone:
            emit_siri_app_event("voice", chat_id, False)
        else:
            SiriAppIPC.voice_state(chat_id, False)


# ── CLI ENTRY POINT ──
def main():
    parser = argparse.ArgumentParser(description="Shell27 Siri Voice Assistant Daemon")
    parser.add_argument("--daemon", action="store_true", help="Start continuous wake-word listener daemon")
    parser.add_argument("--start-daemon", action="store_true", help="Start the listener in the background")
    parser.add_argument("--stop-daemon", action="store_true", help="Stop the background listener")
    parser.add_argument("--trigger", action="store_true", help="Trigger a single listening cycle right now")
    parser.add_argument("--awake", action="store_true", help="Awake Siri on-demand: open mic, listen, respond, and close mic immediately")
    parser.add_argument("--voice-only", action="store_true", help="Start Siri voice-only mode with a five-second empty-input timeout")
    parser.add_argument("--query", type=str, help="Send a text query to Gemini and test TTS/UI directly")
    parser.add_argument("--visual-query", nargs=2, metavar=("IMAGE", "PROMPT"), help="Send an image and prompt to Gemini")
    parser.add_argument("--app-query", nargs=2, metavar=("PROMPT", "CHAT_ID"), help="Send a text prompt to the Siri app")
    parser.add_argument("--app-visual-query", nargs=3, metavar=("IMAGE", "PROMPT", "CHAT_ID"), help="Send an image prompt to the Siri app")
    parser.add_argument("--app-voice", metavar="CHAT_ID", help="Listen for a prompt in a Siri app chat")
    parser.add_argument("--app-stdout", action="store_true", help="Return Siri app events on stdout instead of shell IPC")
    parser.add_argument("--visual-suggest", type=str, metavar="IMAGE", help="Suggest a contextual image lookup label")
    parser.add_argument("--no-tts", action="store_true", help="Disable TTS speech output for text query")
    parser.add_argument("--test-api", action="store_true", help="Test Gemini API connectivity")
    parser.add_argument("--test-tts", type=str, help="Test TTS synthesis with given text")
    parser.add_argument("--test-ipc", action="store_true", help="Test Quickshell edge glow and speech card")
    parser.add_argument("--stop-speech", action="store_true", help="Stop all currently playing speech immediately")
    parser.add_argument("--set-voice-muted", choices=["true", "false"], help="Mute or unmute Siri voice replies")
    parser.add_argument("--get-voice-muted", action="store_true", help="Print whether Siri voice replies are muted")

    args = parser.parse_args()

    if args.start_daemon:
        start_managed_daemon()
        return

    if args.stop_daemon:
        stop_managed_daemon()
        return

    if args.stop_speech:
        stop_all_speech()
        print("[TTS] Speech playback stopped immediately.")
        return

    if args.set_voice_muted is not None:
        if args.set_voice_muted == "true":
            VOICE_MUTE_FILE.touch()
            stop_all_speech()
        else:
            try:
                VOICE_MUTE_FILE.unlink()
            except FileNotFoundError:
                pass
        return

    if args.get_voice_muted:
        print("true" if VOICE_MUTE_FILE.exists() else "false")
        return

    if args.app_query:
        handle_app_query_mode(args.app_query[0], args.app_query[1], standalone=args.app_stdout)
        return

    if args.app_visual_query:
        CONFIG = load_config()
        if not CONFIG.get("visual_intelligence_enabled", True):
            message = "Visual Intelligence is disabled in Apple Intelligence settings."
            if args.app_stdout:
                emit_siri_app_event("response", args.app_visual_query[2], message)
            else:
                SiriAppIPC.response(args.app_visual_query[2], message)
            return
        handle_app_query_mode(args.app_visual_query[1], args.app_visual_query[2], image_path=args.app_visual_query[0],
                              standalone=args.app_stdout)
        return

    if args.app_voice:
        handle_app_voice_mode(args.app_voice, standalone=args.app_stdout)
        return

    if args.test_api:
        print("[API Test] Contacting Gemini API...")
        res = query_gemini("Say hello in one short sentence.")
        print(f"[API Result] {res}")
        return

    if args.test_tts:
        text_to_speak = args.test_tts
        if text_to_speak in ["", "true", "True", "auto", "default"]:
            import random
            text_to_speak = random.choice([
                "Hi, I'm Siri. Choose the voice you'd like me to use.",
                "Hi, I'm Siri. What can I help you with?",
                "Hi, I'm Siri. I can help you get things done.",
                "Hi, I'm Siri. How can I help you today?"
            ])
        print(f"[TTS Test] Speaking: {text_to_speak}")
        speak(text_to_speak, force=True)
        return

    if args.test_ipc:
        print("[IPC Test] Showing Siri Edge Glow and Speech Card...")
        SiriIPC.activate(True)
        SiriIPC.set_state("speaking")
        SiriIPC.set_prompt("What is Quickshell on Linux?")
        SiriIPC.set_response("Quickshell is a flexible framework for creating desktop shell interfaces with Qt and QML.")
        time.sleep(4.0)
        SiriIPC.activate(False)
        print("[IPC Test] Done.")
        return

    if args.visual_query:
        CONFIG = load_config()
        if not CONFIG.get("visual_intelligence_enabled", True):
            print("Visual Intelligence is disabled in Apple Intelligence settings.")
            return
        handle_query_mode(args.visual_query[1], enable_tts=False, image_path=args.visual_query[0])
        return

    if args.visual_suggest:
        suggestion_prompt = (
            "Inspect this image and return only JSON with keys suggestion and words. suggestion is one concise contextual "
            "lookup label, 2 to 4 words (food: Look Up Nutrition; plant: Identify This Plant; product: Find This Product; "
            "text: Read This Text; otherwise: Look Up). words is an array of visible text words, each with text, line, x, y, "
            "width, and height. Coordinates are normalized to 0..1000 relative to the image's top-left. Use tight boxes and "
            "include only clearly readable text. Return an empty array when there is no text. Example: "
            '{"suggestion":"Read This Text","words":[{"text":"Hello","line":1,"x":100,"y":200,"width":120,"height":45}]}'
        )
        suggestion_response = query_gemini(suggestion_prompt, image_path=args.visual_suggest).strip()
        vision_result = {}
        json_match = re.search(r"\{.*\}", suggestion_response, flags=re.DOTALL)
        if json_match:
            try:
                vision_result = json.loads(json_match.group(0))
            except json.JSONDecodeError:
                pass
        if not isinstance(vision_result, dict):
            vision_result = {}
        suggestion = str(vision_result.get("suggestion", "Look Up"))
        if not vision_result and suggestion_response:
            suggestion = suggestion_response.splitlines()[0]
        suggestion = suggestion.strip(" \"'`*.,:;-")
        if len(suggestion) > 32 or any(term in suggestion.lower() for term in ("error", "sorry", "configure", "api key")):
            suggestion = "Look Up"
        words = []
        try:
            ocr = subprocess.run(
                ["tesseract", args.visual_suggest, "stdout", "tsv"],
                capture_output=True, text=True, timeout=20
            )
            if ocr.returncode == 0:
                for row in ocr.stdout.splitlines()[1:]:
                    columns = row.split("\t", 11)
                    if len(columns) != 12 or columns[0] != "5" or not columns[11].strip():
                        continue
                    try:
                        confidence = float(columns[10])
                        x, y, width, height = (int(value) for value in columns[6:10])
                    except ValueError:
                        continue
                    if confidence < 20 or width <= 0 or height <= 0:
                        continue
                    words.append({
                        "x": x, "y": y, "width": width, "height": height,
                        "line": ":".join(columns[2:5]), "text": columns[11].strip()
                    })
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        if not words:
            try:
                from PIL import Image
                with Image.open(args.visual_suggest) as image:
                    image_width, image_height = image.size
                vision_words = vision_result.get("words", [])
                if not isinstance(vision_words, list):
                    vision_words = []
                for item in vision_words:
                    if not isinstance(item, dict):
                        continue
                    try:
                        x = max(0, min(1000, float(item["x"])))
                        y = max(0, min(1000, float(item["y"])))
                        width = max(0, min(1000 - x, float(item["width"])))
                        height = max(0, min(1000 - y, float(item["height"])))
                        text = str(item["text"]).strip()
                    except (KeyError, TypeError, ValueError):
                        continue
                    if text and width > 0 and height > 0:
                        words.append({
                            "x": round(x * image_width / 1000),
                            "y": round(y * image_height / 1000),
                            "width": round(width * image_width / 1000),
                            "height": round(height * image_height / 1000),
                            "line": str(item.get("line", "1")), "text": text
                        })
            except (ImportError, OSError):
                pass
        print(json.dumps({"suggestion": suggestion or "Look Up", "words": words}, ensure_ascii=False))
        return

    if args.query:
        handle_query_mode(args.query, enable_tts=not args.no_tts)
        return

    if args.trigger or args.awake or args.voice_only:
        import fcntl
        lock_file = "/tmp/shell27_siri_awake.lock"
        pid_file = "/tmp/shell27_siri_awake.pid"
        try:
            lock_fd = open(lock_file, "w")
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (IOError, BlockingIOError):
            print("[Siri] An awake cycle is already active. Toggling dismiss.")
            try:
                if os.path.exists(pid_file):
                    with open(pid_file, "r") as pf:
                        old_pid = int(pf.read().strip())
                    if old_pid != os.getpid():
                        os.kill(old_pid, 15)
            except Exception:
                pass
            SiriIPC.activate(False)
            return

        try:
            with open(pid_file, "w") as pf:
                pf.write(str(os.getpid()))
        except Exception:
            pass

        try:
            import speech_recognition as sr
            r = sr.Recognizer()
            r.dynamic_energy_threshold = True
            r.pause_threshold = 0.6
            run_assistant_cycle(r, voice_only=args.voice_only)
        finally:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
                lock_fd.close()
                if os.path.exists(lock_file):
                    os.remove(lock_file)
                if os.path.exists(pid_file):
                    os.remove(pid_file)
            except Exception:
                pass
        return

    # Default to daemon mode if called directly
    start_daemon()

if __name__ == "__main__":
    main()