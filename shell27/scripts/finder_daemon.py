#!/usr/bin/env python3
import concurrent.futures
import hashlib
import json
import mimetypes
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import threading
import time
import zipfile
from pathlib import Path
from urllib.parse import unquote

HOME = Path.home()
CONFIG_DIR = HOME / ".config" / "shell27"
META_PATH = CONFIG_DIR / "finder-meta.json"
SIDEBAR_PATH = CONFIG_DIR / "finder-sidebar.json"
CONFIG_PATH = CONFIG_DIR / "finder-config.json"
# Short-lived session state shared by all Finder windows, not a preference.
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or (HOME / ".cache" / "shell27"))
CLIPBOARD_PATH = RUNTIME_DIR / "shell27-finder-clipboard.json"
THUMB_DIR = HOME / ".cache" / "shell27" / "finder-thumbs"
TRASH_FILES = HOME / ".local" / "share" / "Trash" / "files"
TRASH_INFO = HOME / ".local" / "share" / "Trash" / "info"

CONFIG_DIR.mkdir(parents=True, exist_ok=True)
THUMB_DIR.mkdir(parents=True, exist_ok=True)

OUT_LOCK = threading.Lock()
META_LOCK = threading.RLock()
SIDEBAR_LOCK = threading.RLock()
CONFIG_LOCK = threading.RLock()
THUMB_POOL = concurrent.futures.ThreadPoolExecutor(max_workers=4)
THUMB_INFLIGHT = set()

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg", ".ico", ".avif"}
VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"}
TEXT_EXTS = {
    ".txt", ".md", ".markdown", ".json", ".qml", ".js", ".ts", ".py", ".sh",
    ".rs", ".c", ".cpp", ".h", ".hpp", ".css", ".html", ".xml", ".yaml", ".yml",
    ".toml", ".ini", ".conf", ".log", ".csv", ".desktop"
}

TAG_DEFS = [
    {"name": "Red", "color": "#FF3B30"},
    {"name": "Orange", "color": "#FF9500"},
    {"name": "Yellow", "color": "#FFCC00"},
    {"name": "Green", "color": "#28CD41"},
    {"name": "Blue", "color": "#007AFF"},
    {"name": "Purple", "color": "#AF52DE"},
    {"name": "Gray", "color": "#8E8E93"},
]

KIND_LABELS = {
    ".md": "Markdown Document",
    ".txt": "Plain Text Document",
    ".pdf": "PDF Document",
    ".docx": "Word Document",
    ".doc": "Word Document",
    ".xlsx": "Excel Spreadsheet",
    ".csv": "CSV Spreadsheet",
    ".pptx": "PowerPoint Presentation",
    ".pages": "Pages Document",
    ".zip": "ZIP Archive",
    ".tar": "TAR Archive",
    ".gz": "GZip Archive",
    ".xz": "XZ Archive",
    ".7z": "7-Zip Archive",
    ".py": "Python Script",
    ".qml": "QML Source",
    ".js": "JavaScript File",
    ".json": "JSON Document",
    ".sh": "Shell Script",
    ".png": "PNG Image",
    ".jpg": "JPEG Image",
    ".jpeg": "JPEG Image",
    ".webp": "WebP Image",
    ".gif": "GIF Image",
    ".svg": "SVG Image",
    ".mp4": "MPEG-4 Movie",
    ".mov": "QuickTime Movie",
    ".mkv": "Matroska Video",
    ".mp3": "MP3 Audio",
    ".wav": "Waveform Audio",
    ".flac": "FLAC Audio",
    ".desktop": "Application",
    ".appimage": "AppImage Application",
}


def emit(obj):
    line = json.dumps(obj, ensure_ascii=False)
    with OUT_LOCK:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def load_meta():
    with META_LOCK:
        if META_PATH.exists():
            try:
                return json.loads(META_PATH.read_text(encoding="utf-8"))
            except Exception:
                pass
        return {"tags": {}, "folderColors": {}}


def save_meta(meta):
    with META_LOCK:
        tmp = META_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(META_PATH)


def read_tags(path_str, meta):
    tags = []
    try:
        raw = os.getxattr(path_str, "user.xdg.tags")
        tags = [t.strip() for t in raw.decode("utf-8", errors="ignore").split(",") if t.strip()]
    except Exception:
        pass
    if not tags:
        tags = list(meta.get("tags", {}).get(path_str, []))
    return tags


def write_tags(path_str, tags):
    clean = []
    for t in tags:
        if t and t not in clean:
            clean.append(t)
    try:
        if clean:
            os.setxattr(path_str, "user.xdg.tags", ",".join(clean).encode("utf-8"))
        else:
            try:
                os.removexattr(path_str, "user.xdg.tags")
            except OSError:
                pass
    except Exception:
        pass
    meta = load_meta()
    if clean:
        meta.setdefault("tags", {})[path_str] = clean
    else:
        meta.get("tags", {}).pop(path_str, None)
    save_meta(meta)
    return clean


ICON_CACHE = HOME / ".cache" / "shell27" / "icon-index.json"

class IconResolver:
    def __init__(self):
        self.theme_dark = True
        self.index = {"dark": {}, "light": {}}
        if not self._load_cache():
            self._build_index()
            self._save_cache()

    def _load_cache(self):
        if ICON_CACHE.exists():
            try:
                data = json.loads(ICON_CACHE.read_text(encoding="utf-8"))
                if "dark" in data and "light" in data and len(data["dark"]) > 0:
                    self.index = data
                    return True
            except Exception:
                pass
        return False

    def _save_cache(self):
        try:
            ICON_CACHE.parent.mkdir(parents=True, exist_ok=True)
            ICON_CACHE.write_text(json.dumps(self.index, ensure_ascii=False), encoding="utf-8")
        except Exception:
            pass

    def _theme_roots(self, dark):
        if dark:
            names = ["MacOS-Like-Dark", "MacTahoe-dark", "MacTahoe", "Papirus-Dark", "Papirus", "hicolor"]
        else:
            names = ["MacOS-Like-Light", "MacTahoe-light", "MacTahoe", "Papirus-Light", "Papirus", "hicolor"]
        bases = [HOME / ".local" / "share" / "icons", Path("/usr/share/icons")]
        roots = []
        for n in names:
            for b in bases:
                p = b / n
                if p.is_dir():
                    roots.append(p)
        return roots

    def _build_index(self):
        preferred_sizes = ["128", "scalable", "64", "96", "48", "32", "256", "128x128", "64x64", "48x48", "32x32", "256x256"]
        for mode, dark in [("dark", True), ("light", False)]:
            table = {}
            for root in reversed(self._theme_roots(dark)):
                for dirpath, _, filenames in os.walk(root):
                    dp = Path(dirpath)
                    if "symbolic" in dp.parts:
                        continue
                    score = 1
                    for i, s in enumerate(preferred_sizes):
                        if s in dp.parts:
                            score = 100 - i
                            break
                    for fn in filenames:
                        if not fn.endswith((".svg", ".png")):
                            continue
                        stem = os.path.splitext(fn)[0]
                        if fn.endswith(".svg"):
                            score_f = score + 5
                        else:
                            score_f = score
                        prev = table.get(stem)
                        if prev is None or score_f >= prev[0]:
                            table[stem] = (score_f, str(dp / fn))
            self.index[mode] = {k: v[1] for k, v in table.items()}

    def lookup(self, names, dark=True):
        table = self.index["dark" if dark else "light"]
        for name in names:
            if not name:
                continue
            if os.path.isabs(name) and os.path.exists(name):
                return name
            if name in table:
                return table[name]
        # Fallback cross-mode
        other = self.index["light" if dark else "dark"]
        for name in names:
            if name and name in other:
                return other[name]
        return ""


ICONS = IconResolver()


def parse_desktop(path: Path):
    name = path.stem
    icon = ""
    no_display = False
    try:
        in_entry = False
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            s = line.strip()
            if s.startswith("["):
                in_entry = (s == "[Desktop Entry]")
                continue
            if not in_entry or "=" not in s:
                continue
            k, v = s.split("=", 1)
            k = k.strip()
            v = v.strip()
            if k == "Name" and name == path.stem:
                name = v
            elif k == "Icon":
                icon = v
            elif k == "NoDisplay" and v.lower() == "true":
                no_display = True
    except Exception:
        pass
    return name, icon, no_display


def resolve_item_icon(path: Path, is_dir: bool, dark: bool, desktop_icon: str = ""):
    if is_dir:
        special = {
            str(HOME): ["folder-home", "user-home", "folder"],
            str(HOME / "Desktop"): ["folder-desktop", "user-desktop", "folder"],
            str(HOME / "Documents"): ["folder-documents", "folder-text", "folder"],
            str(HOME / "Downloads"): ["folder-downloads", "folder-download", "folder"],
            str(HOME / "Pictures"): ["folder-pictures", "folder-images", "folder"],
            str(HOME / "Music"): ["folder-music", "folder-sound", "folder"],
            str(HOME / "Videos"): ["folder-videos", "folder-video", "folder"],
            str(HOME / "Public"): ["folder-publicshare", "folder-network", "folder"],
            str(HOME / "Applications"): ["folder-activities", "folder-applications", "folder"],
            str(HOME / "iCloud Drive"): ["folder-cloud", "folder-sync", "folder"],
        }
        names = special.get(str(path), ["folder", "inode-directory"])
        return ICONS.lookup(names, dark)

    ext = path.suffix.lower()
    if ext == ".desktop" and desktop_icon:
        res = ICONS.lookup([desktop_icon, "application-x-executable"], dark)
        if res:
            return res

    mime, _ = mimetypes.guess_type(str(path))
    candidates = []
    if mime:
        candidates.append(mime.replace("/", "-"))
    ext_map = {
        ".md": ["text-markdown", "text-x-markdown", "text-x-generic"],
        ".markdown": ["text-markdown", "text-x-generic"],
        ".pdf": ["application-pdf", "x-office-document"],
        ".docx": ["application-vnd.openxmlformats-officedocument.wordprocessingml.document", "x-office-document", "application-msword"],
        ".doc": ["application-msword", "x-office-document"],
        ".xlsx": ["application-vnd.openxmlformats-officedocument.spreadsheetml.sheet", "x-office-spreadsheet"],
        ".csv": ["text-csv", "x-office-spreadsheet"],
        ".pptx": ["application-vnd.openxmlformats-officedocument.presentationml.presentation", "x-office-presentation"],
        ".zip": ["application-zip", "package-x-generic"],
        ".tar": ["application-x-tar", "package-x-generic"],
        ".gz": ["application-gzip", "package-x-generic"],
        ".xz": ["application-x-xz", "package-x-generic"],
        ".7z": ["application-x-7z-compressed", "package-x-generic"],
        ".py": ["text-x-python", "text-x-script"],
        ".qml": ["text-x-qml", "text-x-script", "text-x-c++src"],
        ".js": ["application-javascript", "text-javascript", "text-x-script"],
        ".json": ["application-json", "text-x-script"],
        ".sh": ["application-x-shellscript", "text-x-script"],
        ".html": ["text-html"],
        ".css": ["text-css"],
        ".mp3": ["audio-mpeg", "audio-x-generic"],
        ".wav": ["audio-x-wav", "audio-x-generic"],
        ".flac": ["audio-flac", "audio-x-generic"],
        ".mp4": ["video-mp4", "video-x-generic"],
        ".mov": ["video-quicktime", "video-x-generic"],
        ".mkv": ["video-x-matroska", "video-x-generic"],
        ".png": ["image-png", "image-x-generic"],
        ".jpg": ["image-jpeg", "image-x-generic"],
        ".jpeg": ["image-jpeg", "image-x-generic"],
        ".webp": ["image-webp", "image-x-generic"],
        ".svg": ["image-svg+xml", "image-x-generic"],
        ".appimage": ["application-x-executable"],
    }
    candidates.extend(ext_map.get(ext, []))
    if mime and mime.startswith("text/"):
        candidates.append("text-plain")
    elif mime and mime.startswith("image/"):
        candidates.append("image-x-generic")
    elif mime and mime.startswith("video/"):
        candidates.append("video-x-generic")
    elif mime and mime.startswith("audio/"):
        candidates.append("audio-x-generic")
    candidates.extend(["text-x-generic", "application-octet-stream", "unknown"])
    return ICONS.lookup(candidates, dark)


def thumb_cache_path(path_str: str, mtime: float):
    key = hashlib.sha1(f"{path_str}:{int(mtime)}".encode("utf-8")).hexdigest()
    return THUMB_DIR / f"{key}.png"


def make_thumbnail(path_str: str, mtime: float):
    out = thumb_cache_path(path_str, mtime)
    if out.exists():
        return str(out)
    ext = Path(path_str).suffix.lower()
    if ext == ".svg":
        return path_str
    try:
        if ext in IMAGE_EXTS:
            try:
                from PIL import Image, ImageOps
                with Image.open(path_str) as im:
                    im = ImageOps.exif_transpose(im)
                    im.thumbnail((256, 256))
                    im.save(out, "PNG")
                return str(out)
            except Exception:
                return path_str
        elif ext in VIDEO_EXTS and shutil.which("ffmpegthumbnailer"):
            subprocess.run(
                ["ffmpegthumbnailer", "-i", path_str, "-o", str(out), "-s", "256"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4
            )
            if out.exists():
                return str(out)
        elif ext == ".pdf" and shutil.which("pdftoppm"):
            prefix = str(out.with_suffix(""))
            subprocess.run(
                ["pdftoppm", "-png", "-f", "1", "-l", "1", "-scale-to", "256", path_str, prefix],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4
            )
            for cand in [Path(prefix + "-1.png"), Path(prefix + "-01.png")]:
                if cand.exists():
                    cand.replace(out)
                    return str(out)
    except Exception:
        pass
    return ""


def schedule_thumb(path_str: str, mtime: float, req_id: str):
    if path_str in THUMB_INFLIGHT:
        return
    THUMB_INFLIGHT.add(path_str)

    def task():
        try:
            tp = make_thumbnail(path_str, mtime)
            if tp:
                emit({"event": "thumb", "reqId": req_id, "path": path_str, "thumb": tp})
        finally:
            THUMB_INFLIGHT.discard(path_str)

    THUMB_POOL.submit(task)


def format_size(n: int):
    if n < 1024:
        return f"{n} bytes"
    for unit in ["KB", "MB", "GB", "TB"]:
        n /= 1024.0
        if n < 1024.0 or unit == "TB":
            return f"{n:.1f} {unit}" if n < 10 else f"{n:.0f} {unit}"
    return "0 bytes"


def kind_for(path: Path, is_dir: bool):
    if is_dir:
        return "Folder"
    ext = path.suffix.lower()
    if ext in KIND_LABELS:
        return KIND_LABELS[ext]
    mime, _ = mimetypes.guess_type(str(path))
    if mime:
        if mime.startswith("image/"):
            return f"{ext.lstrip('.').upper()} Image" if ext else "Image"
        if mime.startswith("text/"):
            return "Text Document"
    return f"{ext.lstrip('.').upper()} File" if ext else "Document"


def build_entry(p: Path, meta: dict, dark: bool, req_id: str, display_override: str = "", icon_override: str = ""):
    path_str = str(p)
    try:
        st = p.lstat()
        is_link = stat.S_ISLNK(st.st_mode)
        if is_link:
            try:
                st = p.stat()
            except OSError:
                pass
        is_dir = stat.S_ISDIR(st.st_mode)
        size = 0 if is_dir else st.st_size
        mtime = st.st_mtime
        ctime = st.st_ctime
    except OSError:
        is_dir = p.is_dir()
        is_link = p.is_symlink()
        size = 0
        mtime = 0
        ctime = 0

    ext = p.suffix.lower()
    display_name = display_override or p.name
    desktop_icon = icon_override
    if not is_dir and ext == ".desktop" and not desktop_icon:
        dname, dicon, _ = parse_desktop(p)
        display_name = display_override or dname
        desktop_icon = dicon

    icon_path = resolve_item_icon(p, is_dir, dark, desktop_icon)
    thumb_path = ""
    if not is_dir and (ext in IMAGE_EXTS or ext in VIDEO_EXTS or ext == ".pdf"):
        cached = thumb_cache_path(path_str, mtime)
        if cached.exists():
            thumb_path = str(cached)
        elif ext in IMAGE_EXTS:
            thumb_path = path_str
            schedule_thumb(path_str, mtime, req_id)
        else:
            schedule_thumb(path_str, mtime, req_id)

    child_count = -1
    if is_dir:
        try:
            with os.scandir(path_str) as it:
                child_count = sum(1 for _ in it)
        except OSError:
            child_count = 0

    tags = read_tags(path_str, meta)
    folder_color = meta.get("folderColors", {}).get(path_str, "") if is_dir else ""

    return {
        "name": p.name,
        "displayName": display_name,
        "path": path_str,
        "isDir": is_dir,
        "isLink": is_link,
        "isImage": ext in IMAGE_EXTS,
        "isVideo": ext in VIDEO_EXTS,
        "isText": ext in TEXT_EXTS,
        "isPdf": ext == ".pdf",
        "isDesktop": ext == ".desktop",
        "ext": ext,
        "size": size,
        "sizeText": f"{child_count} items" if is_dir and child_count >= 0 else ("--" if is_dir else format_size(size)),
        "mtime": int(mtime * 1000),
        "ctime": int(ctime * 1000),
        "kind": kind_for(p, is_dir),
        "icon": icon_path,
        "thumb": thumb_path,
        "tags": tags,
        "folderColor": folder_color,
        "childCount": child_count,
    }


def list_virtual(kind: str, show_hidden: bool, dark: bool, req_id: str, tag_filter: str = ""):
    meta = load_meta()
    items = []
    if kind == "recents":
        candidates = []
        skip = {".git", "node_modules", "__pycache__", ".cache", ".local", ".npm", ".cargo"}
        for base in [HOME / "Desktop", HOME / "Documents", HOME / "Downloads", HOME / "Pictures", HOME / "Projects"]:
            if not base.is_dir():
                continue
            for root, dirs, files in os.walk(base):
                dirs[:] = [d for d in dirs if d not in skip and (show_hidden or not d.startswith("."))]
                for fn in files:
                    if not show_hidden and fn.startswith("."):
                        continue
                    fp = Path(root) / fn
                    try:
                        candidates.append((fp.stat().st_mtime, fp))
                    except OSError:
                        pass
                if len(candidates) > 500:
                    break
        candidates.sort(key=lambda x: x[0], reverse=True)
        for _, fp in candidates[:80]:
            items.append(build_entry(fp, meta, dark, req_id))
    elif kind == "applications":
        seen = set()
        app_dirs = [HOME / "Applications", HOME / ".local" / "share" / "applications", Path("/usr/share/applications")]
        for d in app_dirs:
            if not d.is_dir():
                continue
            try:
                for p in sorted(d.iterdir(), key=lambda x: x.name.lower()):
                    if p.suffix.lower() == ".desktop":
                        dname, dicon, no_disp = parse_desktop(p)
                        if no_disp:
                            continue
                        if dname.lower() in seen:
                            continue
                        seen.add(dname.lower())
                        items.append(build_entry(p, meta, dark, req_id, dname, dicon))
                    elif d == HOME / "Applications":
                        items.append(build_entry(p, meta, dark, req_id))
            except OSError:
                pass
        items.sort(key=lambda x: x["displayName"].lower())
    elif kind == "trash":
        if TRASH_FILES.is_dir():
            for p in TRASH_FILES.iterdir():
                items.append(build_entry(p, meta, dark, req_id))
    elif kind == "tag":
        all_tagged = set(meta.get("tags", {}).keys())
        for path_str in all_tagged:
            p = Path(path_str)
            if not p.exists():
                continue
            tags = read_tags(path_str, meta)
            if not tag_filter or tag_filter == "All" or tag_filter in tags:
                items.append(build_entry(p, meta, dark, req_id))
    elif kind == "network":
        gvfs = Path(f"/run/user/{os.getuid()}/gvfs")
        if gvfs.is_dir():
            for p in gvfs.iterdir():
                items.append(build_entry(p, meta, dark, req_id))
    return items


def sort_items(items, sort_by: str, sort_asc: bool):
    def key_fn(it):
        folder_rank = 0 if it["isDir"] else 1
        if sort_by == "date":
            val = it["mtime"]
        elif sort_by == "size":
            val = it["size"]
        elif sort_by == "kind":
            val = it["kind"].lower()
        elif sort_by == "tag":
            val = (it["tags"][0].lower() if it["tags"] else "zzz")
        else:
            val = it["displayName"].lower()
        return val

    if sort_by == "name":
        dirs = sorted([i for i in items if i["isDir"]], key=lambda x: x["displayName"].lower(), reverse=not sort_asc)
        files = sorted([i for i in items if not i["isDir"]], key=lambda x: x["displayName"].lower(), reverse=not sort_asc)
        return dirs + files
    return sorted(items, key=key_fn, reverse=not sort_asc)


def handle_list(cmd):
    req_id = cmd.get("reqId", "")
    path = cmd.get("path", str(HOME))
    show_hidden = bool(cmd.get("showHidden", False))
    dark = bool(cmd.get("dark", True))
    sort_by = cmd.get("sortBy", "name")
    sort_asc = bool(cmd.get("sortAsc", True))
    query = str(cmd.get("search", "")).strip().lower()

    meta = load_meta()
    virtual_prefix = "finder://"
    disk_free = ""
    items = []

    if path.startswith(virtual_prefix):
        v = path[len(virtual_prefix):]
        if v.startswith("tag/"):
            items = list_virtual("tag", show_hidden, dark, req_id, unquote(v[4:]))
        else:
            items = list_virtual(v, show_hidden, dark, req_id)
        try:
            du = shutil.disk_usage(HOME)
            disk_free = f"{du.free / (1024**3):.2f} GB available"
        except Exception:
            pass
    else:
        target = Path(path).expanduser()
        if not target.exists() and path == str(HOME / "iCloud Drive"):
            target.mkdir(parents=True, exist_ok=True)
        if target.is_dir():
            try:
                with os.scandir(target) as it:
                    for entry in it:
                        if not show_hidden and entry.name.startswith("."):
                            continue
                        items.append(build_entry(Path(entry.path), meta, dark, req_id))
            except PermissionError:
                emit({"event": "error", "reqId": req_id, "message": "Permission denied"})
            try:
                du = shutil.disk_usage(target)
                disk_free = f"{du.free / (1024**3):.2f} GB available"
            except Exception:
                pass

    if query:
        search_root = target if (not path.startswith(virtual_prefix) and target.is_dir()) else HOME
        matched = []
        max_results = 300

        def do_search(s_dir):
            try:
                for root_dir, dirs, files in os.walk(str(s_dir), followlinks=False):
                    if not show_hidden:
                        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "__pycache__", ".git", ".cache", ".local", ".cargo")]
                    else:
                        dirs[:] = [d for d in dirs if d not in ("node_modules", "__pycache__", ".git", ".cache", ".cargo")]

                    try:
                        rel = os.path.relpath(root_dir, str(s_dir))
                        if rel != "." and rel.count(os.sep) > 6:
                            dirs[:] = []
                            continue
                    except Exception:
                        pass

                    for d in dirs:
                        if query in d.lower():
                            dp = Path(root_dir) / d
                            matched.append(build_entry(dp, meta, dark, req_id))
                            if len(matched) >= max_results:
                                return

                    for f in files:
                        if not show_hidden and f.startswith("."):
                            continue
                        if query in f.lower():
                            fp = Path(root_dir) / f
                            matched.append(build_entry(fp, meta, dark, req_id))
                            if len(matched) >= max_results:
                                return
            except Exception:
                pass

        do_search(search_root)

        # Fallback to HOME search if 0 results in search_root and search_root != HOME
        if len(matched) == 0 and search_root != HOME:
            do_search(HOME)

        # Tag matches
        for path_str, tag_list in meta.get("tags", {}).items():
            if any(query in t.lower() for t in tag_list):
                tp = Path(path_str)
                if tp.exists() and all(it["path"] != path_str for it in matched):
                    matched.append(build_entry(tp, meta, dark, req_id))
                    if len(matched) >= max_results:
                        break

        items = matched

    items = sort_items(items, sort_by, sort_asc)
    emit({
        "event": "listed",
        "reqId": req_id,
        "path": path,
        "items": items,
        "diskFree": disk_free,
        "count": len(items),
    })


def default_sidebar_categories():
    favorites = [
        {"id": "airdrop", "label": "AirDrop", "path": "finder://airdrop", "glyph": "airdrop"},
        {"id": "recents", "label": "Recents", "path": "finder://recents", "glyph": "clock"},
        {"id": "applications", "label": "Applications", "path": "finder://applications", "glyph": "apps"},
        {"id": "desktop", "label": "Desktop", "path": str(HOME / "Desktop"), "glyph": "desktop"},
        {"id": "documents", "label": "Documents", "path": str(HOME / "Documents"), "glyph": "doc"},
        {"id": "downloads", "label": "Downloads", "path": str(HOME / "Downloads"), "glyph": "downloads"},
    ]
    for extra, g in [("Pictures", "photo"), ("Music", "music"), ("Projects", "folder")]:
        ep = HOME / extra
        if ep.is_dir():
            favorites.append({"id": extra.lower(), "label": extra, "path": str(ep), "glyph": g})

    cloud = [
        {"id": "icloud", "label": "iCloud Drive", "path": str(HOME / "iCloud Drive"), "glyph": "cloud"},
        {"id": "shared", "label": "Shared", "path": str(HOME / "Public") if (HOME / "Public").exists() else "finder://network", "glyph": "shared"},
    ]
    locations = [
        {"id": "root", "label": "Macintosh HD", "path": "/", "glyph": "drive"},
    ]
    for base in [Path(f"/run/media/{os.getuid()}"), Path(f"/run/media/{HOME.name}"), Path("/mnt")]:
        if base.is_dir():
            try:
                for m in sorted(base.iterdir()):
                    if m.is_dir() and any(m.iterdir()):
                        locations.append({"id": f"mnt-{m.name}", "label": m.name, "path": str(m), "glyph": "external"})
            except Exception:
                pass
    locations.append({"id": "network", "label": "Network", "path": "finder://network", "glyph": "network"})
    locations.append({"id": "trash", "label": "Trash", "path": "finder://trash", "glyph": "trash"})

    return [
        {"id": "favorites", "label": "Favorites", "items": favorites, "isCustom": False},
        {"id": "locations", "label": "Locations", "items": locations, "isCustom": False},
        {"id": "cloud", "label": "iCloud", "items": cloud, "isCustom": False},
    ]


def load_sidebar():
    with SIDEBAR_LOCK:
        if SIDEBAR_PATH.exists():
            try:
                data = json.loads(SIDEBAR_PATH.read_text(encoding="utf-8"))
                if isinstance(data, list) and len(data) > 0:
                    return data
            except Exception:
                pass
        defs = default_sidebar_categories()
        save_sidebar(defs)
        return defs


def save_sidebar(categories):
    with SIDEBAR_LOCK:
        try:
            SIDEBAR_PATH.write_text(json.dumps(categories, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass


def handle_sidebar(cmd):
    categories = load_sidebar()
    favorites = []
    locations = []
    cloud = []
    for cat in categories:
        cid = cat.get("id", "")
        if cid == "favorites":
            favorites = cat.get("items", [])
        elif cid == "locations":
            locations = cat.get("items", [])
        elif cid == "cloud":
            cloud = cat.get("items", [])
    emit({
        "event": "sidebar",
        "categories": categories,
        "favorites": favorites,
        "locations": locations,
        "cloud": cloud,
        "tags": TAG_DEFS,
    })


def handle_add_sidebar_item(cmd):
    cat_id = cmd.get("categoryId", "favorites")
    label = cmd.get("label", "").strip()
    path = cmd.get("path", "").strip()
    glyph = cmd.get("glyph", "folder")
    if not path:
        return
    if not label:
        label = Path(path).name or path
    item_id = hashlib.sha1(path.encode("utf-8")).hexdigest()[:8]
    categories = load_sidebar()
    found = False
    for cat in categories:
        if cat.get("id") == cat_id:
            items = cat.setdefault("items", [])
            if not any(it.get("path") == path for it in items):
                items.append({"id": item_id, "label": label, "path": path, "glyph": glyph})
            found = True
            break
    if not found and categories:
        categories[0].setdefault("items", []).append({"id": item_id, "label": label, "path": path, "glyph": glyph})
    save_sidebar(categories)
    handle_sidebar(cmd)


def handle_remove_sidebar_item(cmd):
    target_path = cmd.get("path", "")
    target_id = cmd.get("id", "")
    categories = load_sidebar()
    for cat in categories:
        items = cat.get("items", [])
        cat["items"] = [it for it in items if it.get("path") != target_path and it.get("id") != target_id]
    save_sidebar(categories)
    handle_sidebar(cmd)


def handle_move_sidebar_item(cmd):
    cat_id = cmd.get("categoryId", "")
    target_path = cmd.get("path", "")
    direction = int(cmd.get("dir", 0))
    categories = load_sidebar()
    for cat in categories:
        if not cat_id or cat.get("id") == cat_id:
            items = cat.get("items", [])
            idx = -1
            for i, it in enumerate(items):
                if it.get("path") == target_path or it.get("id") == target_path:
                    idx = i
                    break
            if idx >= 0:
                nidx = idx + direction
                if 0 <= nidx < len(items):
                    items[idx], items[nidx] = items[nidx], items[idx]
                    save_sidebar(categories)
                    break
    handle_sidebar(cmd)


def handle_reorder_sidebar_item(cmd):
    """Drag-reorder: move item from fromIndex to toIndex within a category."""
    cat_id = cmd.get("categoryId", "")
    from_idx = int(cmd.get("fromIndex", -1))
    to_idx = int(cmd.get("toIndex", -1))
    if from_idx < 0 or to_idx < 0 or from_idx == to_idx:
        handle_sidebar(cmd)
        return
    categories = load_sidebar()
    for cat in categories:
        if cat.get("id") == cat_id:
            items = cat.get("items", [])
            if 0 <= from_idx < len(items) and 0 <= to_idx <= len(items):
                item = items.pop(from_idx)
                # Adjust target index after removal
                if to_idx > from_idx:
                    to_idx -= 1
                to_idx = max(0, min(len(items), to_idx))
                items.insert(to_idx, item)
                save_sidebar(categories)
            break
    handle_sidebar(cmd)


def handle_add_sidebar_category(cmd):
    label = cmd.get("label", "New Section").strip() or "New Section"
    cat_id = "custom-" + hashlib.sha1(f"{label}:{time.time()}".encode("utf-8")).hexdigest()[:8]
    categories = load_sidebar()
    categories.append({"id": cat_id, "label": label, "items": [], "isCustom": True})
    save_sidebar(categories)
    handle_sidebar(cmd)


def handle_remove_sidebar_category(cmd):
    cat_id = cmd.get("categoryId", "")
    categories = load_sidebar()
    categories = [cat for cat in categories if cat.get("id") != cat_id]
    save_sidebar(categories)
    handle_sidebar(cmd)


def handle_move_sidebar_category(cmd):
    cat_id = cmd.get("categoryId", "")
    direction = int(cmd.get("dir", 0))
    categories = load_sidebar()
    idx = -1
    for i, cat in enumerate(categories):
        if cat.get("id") == cat_id:
            idx = i
            break
    if idx >= 0:
        nidx = idx + direction
        if 0 <= nidx < len(categories):
            categories[idx], categories[nidx] = categories[nidx], categories[idx]
            save_sidebar(categories)
    handle_sidebar(cmd)


def handle_reset_sidebar(cmd):
    if SIDEBAR_PATH.exists():
        try:
            SIDEBAR_PATH.unlink()
        except Exception:
            pass
    handle_sidebar(cmd)


def handle_open(cmd):
    path_str = cmd.get("path", "")
    p = Path(path_str)
    if not p.exists():
        return
    if p.suffix.lower() == ".desktop":
        subprocess.Popen(["gio", "launch", path_str], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    open_sh = CONFIG_DIR / "scripts" / "open-path.sh"
    if open_sh.exists():
        subprocess.Popen(["bash", str(open_sh), path_str], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.Popen(["xdg-open", path_str], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def handle_mkdir(cmd):
    parent = Path(cmd.get("parent", str(HOME)))
    name = cmd.get("name", "untitled folder").strip() or "untitled folder"
    target = parent / name
    i = 2
    while target.exists():
        target = parent / f"{name} {i}"
        i += 1
    target.mkdir(parents=True, exist_ok=True)
    emit({"event": "mutated", "path": str(parent), "select": str(target)})


def handle_rename(cmd):
    old_path = Path(cmd.get("path", ""))
    new_name = cmd.get("newName", "").strip()
    if not old_path.exists() or not new_name or "/" in new_name:
        return
    new_path = old_path.parent / new_name
    if new_path.exists():
        emit({"event": "error", "message": f'"{new_name}" already exists.'})
        return
    old_path.rename(new_path)
    meta = load_meta()
    if str(old_path) in meta.get("tags", {}):
        meta["tags"][str(new_path)] = meta["tags"].pop(str(old_path))
    if str(old_path) in meta.get("folderColors", {}):
        meta["folderColors"][str(new_path)] = meta["folderColors"].pop(str(old_path))
    save_meta(meta)
    emit({"event": "mutated", "path": str(old_path.parent), "select": str(new_path)})


def handle_bulk_rename(cmd):
    """Bulk rename with two modes: 'template' and 'findReplace'."""
    paths = cmd.get("paths", [])
    mode = cmd.get("mode", "template")
    if not paths:
        return

    meta = load_meta()
    renamed = []
    parent_dirs = set()

    if mode == "template":
        template = cmd.get("template", "{name}")
        start = max(1, int(cmd.get("startNumber", 1)))
        pad = max(1, int(cmd.get("padding", 1)))

        for i, p_str in enumerate(paths):
            p = Path(p_str)
            if not p.exists():
                continue
            stem = p.stem
            ext = p.suffix  # includes the dot
            counter = start + i
            counter_str = str(counter).zfill(pad)

            new_name = template
            new_name = new_name.replace("{name}", stem)
            new_name = new_name.replace("{n}", counter_str)
            new_name = new_name.replace("{ext}", ext.lstrip(".") if ext else "")

            # If the template doesn't include the extension and the original had one, append it
            if ext and not new_name.endswith(ext) and "{ext}" not in template:
                new_name += ext

            new_path = p.parent / new_name
            if new_path == p:
                continue
            if new_path.exists():
                continue  # skip conflicts silently
            p.rename(new_path)
            # migrate metadata
            if str(p) in meta.get("tags", {}):
                meta["tags"][str(new_path)] = meta["tags"].pop(str(p))
            if str(p) in meta.get("folderColors", {}):
                meta["folderColors"][str(new_path)] = meta["folderColors"].pop(str(p))
            renamed.append(str(new_path))
            parent_dirs.add(str(p.parent))

    elif mode == "findReplace":
        find = cmd.get("find", "")
        replace = cmd.get("replace", "")
        case_sensitive = cmd.get("caseSensitive", True)
        if not find:
            return

        for p_str in paths:
            p = Path(p_str)
            if not p.exists():
                continue
            old_name = p.name
            if case_sensitive:
                if find not in old_name:
                    continue
                new_name = old_name.replace(find, replace)
            else:
                lower_name = old_name.lower()
                lower_find = find.lower()
                if lower_find not in lower_name:
                    continue
                # case-insensitive replace
                result = []
                i = 0
                while i < len(old_name):
                    if old_name[i:i+len(find)].lower() == lower_find:
                        result.append(replace)
                        i += len(find)
                    else:
                        result.append(old_name[i])
                        i += 1
                new_name = "".join(result)

            if new_name == old_name or not new_name.strip():
                continue
            new_path = p.parent / new_name
            if new_path.exists():
                continue
            p.rename(new_path)
            if str(p) in meta.get("tags", {}):
                meta["tags"][str(new_path)] = meta["tags"].pop(str(p))
            if str(p) in meta.get("folderColors", {}):
                meta["folderColors"][str(new_path)] = meta["folderColors"].pop(str(p))
            renamed.append(str(new_path))
            parent_dirs.add(str(p.parent))

    if renamed:
        save_meta(meta)
    for d in parent_dirs:
        emit({"event": "mutated", "path": d})


def handle_duplicate(cmd):
    src = Path(cmd.get("path", ""))
    if not src.exists():
        return
    stem, suf = src.stem, src.suffix
    dst = src.parent / f"{stem} copy{suf}"
    i = 2
    while dst.exists():
        dst = src.parent / f"{stem} copy {i}{suf}"
        i += 1
    if src.is_dir():
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)
    emit({"event": "mutated", "path": str(src.parent), "select": str(dst)})


def handle_trash(cmd):
    paths = cmd.get("paths", [])
    parent = ""
    for ps in paths:
        p = Path(ps)
        if not p.exists():
            continue
        parent = str(p.parent)
        res = subprocess.run(["gio", "trash", ps], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode != 0 and p.exists():
            TRASH_FILES.mkdir(parents=True, exist_ok=True)
            dst = TRASH_FILES / p.name
            if dst.exists():
                dst = TRASH_FILES / f"{p.stem}-{int(time.time())}{p.suffix}"
            shutil.move(ps, str(dst))
    emit({"event": "mutated", "path": parent})


def handle_empty_trash(cmd):
    for d in (TRASH_FILES, TRASH_INFO):
        if d.is_dir():
            for entry in d.iterdir():
                try:
                    if entry.is_dir() and not entry.is_symlink():
                        shutil.rmtree(entry, ignore_errors=True)
                    else:
                        entry.unlink(missing_ok=True)
                except Exception:
                    pass
    emit({"event": "mutated", "path": "finder://trash"})


def handle_list_apps(cmd):
    ps = cmd.get("path", "")
    dark = bool(cmd.get("dark", True))
    mime, _ = mimetypes.guess_type(ps)
    if not mime and ps:
        try:
            r = subprocess.run(["xdg-mime", "query", "filetype", ps], capture_output=True, text=True, timeout=2)
            if r.returncode == 0 and r.stdout.strip():
                mime = r.stdout.strip()
        except Exception:
            pass
    mime = mime or "application/octet-stream"
    default_desktop = ""
    try:
        r = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            default_desktop = r.stdout.strip()
    except Exception:
        pass

    app_dirs = [
        HOME / ".local" / "share" / "applications",
        Path("/usr/local/share/applications"),
        Path("/usr/share/applications"),
    ]
    seen = set()
    apps = []
    for d in app_dirs:
        if not d.is_dir():
            continue
        try:
            for f in d.iterdir():
                if f.suffix != ".desktop" or f.name in seen:
                    continue
                seen.add(f.name)
                try:
                    txt = f.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    continue
                in_entry = False
                name = exec_cmd = icon_name = ""
                no_display = False
                for raw in txt.splitlines():
                    s = raw.strip()
                    if s.startswith("["):
                        in_entry = (s == "[Desktop Entry]")
                        continue
                    if not in_entry or "=" not in s:
                        continue
                    k, v = s.split("=", 1)
                    if k == "Name" and not name:
                        name = v.strip()
                    elif k == "Exec" and not exec_cmd:
                        exec_cmd = v.strip()
                    elif k == "Icon" and not icon_name:
                        icon_name = v.strip()
                    elif k == "NoDisplay" and v.strip().lower() == "true":
                        no_display = True
                    elif k == "Type" and v.strip() != "Application":
                        no_display = True
                if no_display or not name or not exec_cmd:
                    continue
                icon_path = ICONS.lookup([icon_name, "application-x-executable"], dark=dark) if icon_name else ""
                apps.append({
                    "desktopId": f.name,
                    "name": name,
                    "exec": exec_cmd,
                    "icon": icon_path,
                    "isDefault": f.name == default_desktop,
                })
        except Exception:
            continue
    apps.sort(key=lambda a: (0 if a["isDefault"] else 1, a["name"].lower()))
    emit({"event": "appsList", "path": ps, "mime": mime, "defaultDesktop": default_desktop, "apps": apps})


def handle_open_with(cmd):
    ps = cmd.get("path", "")
    exec_str = cmd.get("exec", "")
    app = cmd.get("app", "")
    desktop_id = cmd.get("desktopId", "")
    mime = cmd.get("mime", "")
    set_default = bool(cmd.get("setDefault", False))
    if not ps or not Path(ps).exists():
        return
    if set_default and desktop_id and mime:
        try:
            subprocess.run(["xdg-mime", "default", desktop_id, mime], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
        except Exception:
            pass
    if exec_str:
        import shlex
        tokens = shlex.split(exec_str)
        cleaned = []
        replaced = False
        for t in tokens:
            if t in ("%f", "%F", "%u", "%U"):
                cleaned.append(ps)
                replaced = True
            elif t.startswith("%"):
                continue
            else:
                cleaned.append(t)
        if not replaced:
            cleaned.append(ps)
        if cleaned:
            subprocess.Popen(cleaned, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return
    if app:
        subprocess.Popen([app, ps], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    else:
        subprocess.Popen(["xdg-open", ps], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def find_7z_bin():
    for name in ("7z", "7zz", "7za"):
        found = shutil.which(name)
        if found:
            return found
    return ""


def handle_compress(cmd):
    paths = [Path(p) for p in cmd.get("paths", []) if Path(p).exists()]
    if not paths:
        return
    parent = paths[0].parent
    fmt = cmd.get("format", "zip").lower().lstrip(".")
    if fmt not in ("zip", "tar.gz", "tar.xz", "7z"):
        fmt = "zip"
    raw_name = (cmd.get("name", "") or "").strip()
    if raw_name:
        for sfx in (".zip", ".tar.gz", ".tar.xz", ".7z"):
            if raw_name.lower().endswith(sfx):
                raw_name = raw_name[:-len(sfx)]
                break
    base_name = raw_name or (paths[0].stem if len(paths) == 1 else "Archive")
    password = cmd.get("password", "") or ""

    out_file = parent / f"{base_name}.{fmt}"
    i = 2
    while out_file.exists():
        out_file = parent / f"{base_name} {i}.{fmt}"
        i += 1

    seven_z = find_7z_bin()

    emit({"event": "busy", "label": f"Compressing {out_file.name}…"})
    try:
        if fmt == "zip" and password:
            if shutil.which("zip"):
                args = ["zip", "-1", "-r", "-q", "-P", password, str(out_file)] + [p.name for p in paths]
                res = subprocess.run(args, cwd=str(parent), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180)
                if res.returncode != 0:
                    emit({"event": "error", "message": res.stderr.strip() or "Zip compression failed"})
                    return
            elif seven_z:
                args = [seven_z, "a", "-y", "-mx=1", "-tzip", "-mem=AES256", f"-p{password}", str(out_file)] + [p.name for p in paths]
                res = subprocess.run(args, cwd=str(parent), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180)
                if res.returncode != 0:
                    emit({"event": "error", "message": res.stderr.strip() or "Zip compression failed"})
                    return
            else:
                emit({"event": "error", "message": "Neither zip nor 7z is installed for password-protected zip"})
                return
        elif fmt == "7z":
            if seven_z:
                args = [seven_z, "a", "-y", "-mx=3", "-t7z"]
                if password:
                    args += ["-mhe=on", f"-p{password}"]
                args.append(str(out_file))
                args += [p.name for p in paths]
                res = subprocess.run(args, cwd=str(parent), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180)
                if res.returncode != 0:
                    emit({"event": "error", "message": res.stderr.strip() or "7z compression failed"})
                    return
            elif shutil.which("bsdtar") and not password:
                args = ["bsdtar", "-a", "-cf", str(out_file)] + [p.name for p in paths]
                res = subprocess.run(args, cwd=str(parent), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180)
                if res.returncode != 0:
                    emit({"event": "error", "message": res.stderr.strip() or "7z compression failed"})
                    return
            else:
                emit({"event": "error", "message": "7z (p7zip) is not installed on this system"})
                return
        elif fmt in ("tar.gz", "tar.xz"):
            if fmt == "tar.gz":
                with tarfile.open(out_file, "w:gz", compresslevel=3) as tf:
                    for p in paths:
                        tf.add(p, arcname=p.name)
            else:
                with tarfile.open(out_file, "w:xz") as tf:
                    for p in paths:
                        tf.add(p, arcname=p.name)
        else:
            with zipfile.ZipFile(out_file, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as zf:
                for p in paths:
                    if p.is_dir():
                        for root_dir, _, files in os.walk(p):
                            for fn in files:
                                fp = Path(root_dir) / fn
                                zf.write(fp, fp.relative_to(parent))
                    else:
                        zf.write(p, p.name)
        emit({"event": "mutated", "path": str(parent), "select": str(out_file)})
    finally:
        emit({"event": "busyDone"})


def handle_extract(cmd):
    ps = cmd.get("path", "")
    password = cmd.get("password", "")
    p = Path(ps)
    if not p.exists() or not p.is_file():
        return
    parent = p.parent
    stem = p.name
    for sfx in (".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".zip", ".rar", ".tar", ".7z"):
        if stem.lower().endswith(sfx):
            stem = stem[:-len(sfx)]
            break
    out_dir = parent / stem
    i = 2
    while out_dir.exists():
        out_dir = parent / f"{stem} {i}"
        i += 1
    out_dir.mkdir(parents=True, exist_ok=True)
    lower = p.name.lower()

    def cleanup_empty():
        try:
            if out_dir.exists() and not any(out_dir.iterdir()):
                out_dir.rmdir()
        except Exception:
            pass

    emit({"event": "busy", "label": f"Extracting {p.name}…"})
    try:
        if lower.endswith(".zip"):
            try:
                with zipfile.ZipFile(p, "r") as zf:
                    pwd_bytes = password.encode("utf-8") if password else None
                    zf.extractall(out_dir, pwd=pwd_bytes)
                emit({"event": "mutated", "path": str(parent), "select": str(out_dir)})
                return
            except RuntimeError as e:
                msg = str(e).lower()
                if "encrypted" in msg or "password" in msg:
                    cleanup_empty()
                    emit({"event": "extractPasswordRequired", "path": ps, "wrongPassword": bool(password)})
                    return
                # Fallback to 7z/unzip for AES-encrypted zips unsupported by Python's zipfile
            except Exception:
                pass

        if lower.endswith((".tar", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2")):
            with tarfile.open(p, "r:*") as tf:
                tf.extractall(out_dir)
            emit({"event": "mutated", "path": str(parent), "select": str(out_dir)})
            return

        # .rar, .7z, or AES-encrypted .zip via 7z / unzip / bsdtar
        seven_z = find_7z_bin()
        if seven_z:
            p_arg = f"-p{password}" if password else "-p"
            res = subprocess.run(
                [seven_z, "x", str(p), f"-o{out_dir}", "-y", p_arg],
                stdin=subprocess.DEVNULL,
                start_new_session=True,
                capture_output=True,
                text=True,
                timeout=120,
            )
        elif lower.endswith(".zip") and shutil.which("unzip"):
            args = ["unzip", "-o", "-q"]
            if password:
                args += ["-P", password]
            else:
                args += ["-P", ""]
            args += [str(p), "-d", str(out_dir)]
            res = subprocess.run(args, stdin=subprocess.DEVNULL, start_new_session=True, capture_output=True, text=True, timeout=120)
        elif shutil.which("bsdtar"):
            res = subprocess.run(
                ["bsdtar", "-xf", str(p), "-C", str(out_dir)],
                stdin=subprocess.DEVNULL,
                start_new_session=True,
                capture_output=True,
                text=True,
                timeout=120,
            )
        else:
            cleanup_empty()
            emit({"event": "error", "message": "No extraction tool available for this archive"})
            return

        if res.returncode != 0:
            combined = (res.stdout + "\n" + res.stderr).lower()
            cleanup_empty()
            if "password" in combined or "encrypted" in combined or "wrong" in combined or "crc failed" in combined or "passphrase" in combined or res.returncode == 82:
                emit({"event": "extractPasswordRequired", "path": ps, "wrongPassword": bool(password)})
                return
            emit({"event": "error", "message": res.stderr.strip() or "Extraction failed"})
            return
        emit({"event": "mutated", "path": str(parent), "select": str(out_dir)})
    finally:
        emit({"event": "busyDone"})


def handle_paste(cmd):
    mode = cmd.get("mode", "copy")
    sources = cmd.get("sources", [])
    dest = Path(cmd.get("dest", ""))
    if not dest.is_dir():
        return
    for ps in sources:
        src = Path(ps)
        if not src.exists() or src.parent == dest and mode == "move":
            continue
        dst = dest / src.name
        i = 2
        while dst.exists():
            dst = dest / f"{src.stem} {i}{src.suffix}"
            i += 1
        if mode == "move":
            shutil.move(str(src), str(dst))
        elif src.is_dir():
            shutil.copytree(str(src), str(dst))
        else:
            shutil.copy2(str(src), str(dst))
    emit({"event": "mutated", "path": str(dest)})


def handle_clipboard_set(cmd):
    """Persist Finder's file clipboard so tabs and separate windows agree."""
    paths = [str(Path(p)) for p in cmd.get("paths", []) if p]
    mode = "move" if cmd.get("mode") == "move" else "copy"
    try:
        CLIPBOARD_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = CLIPBOARD_PATH.with_name(CLIPBOARD_PATH.name + ".tmp")
        tmp.write_text(json.dumps({"paths": paths, "mode": mode}), encoding="utf-8")
        tmp.replace(CLIPBOARD_PATH)
        emit({"event": "clipboardSet", "paths": paths, "mode": mode})
    except Exception as e:
        emit({"event": "error", "message": f"Could not save clipboard: {e}"})


def handle_clipboard_get(cmd):
    paths = []
    mode = "copy"
    try:
        data = json.loads(CLIPBOARD_PATH.read_text(encoding="utf-8"))
        paths = [str(p) for p in data.get("paths", []) if p]
        mode = "move" if data.get("mode") == "move" else "copy"
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    # Preserve the destination requested before navigation changes again.
    emit({"event": "clipboard", "paths": paths, "mode": mode,
          "dest": cmd.get("dest", "")})


def handle_set_tag(cmd):
    paths = cmd.get("paths", [])
    tag = cmd.get("tag", "")
    toggle = bool(cmd.get("toggle", True))
    meta = load_meta()
    for ps in paths:
        cur = read_tags(ps, meta)
        if toggle:
            if tag in cur:
                cur = [t for t in cur if t != tag]
            else:
                cur.append(tag)
        else:
            cur = [tag] if tag else []
        write_tags(ps, cur)
    parent = str(Path(paths[0]).parent) if paths else ""
    emit({"event": "mutated", "path": parent})


def handle_set_folder_color(cmd):
    paths = cmd.get("paths", [])
    color = cmd.get("color", "")
    meta = load_meta()
    for ps in paths:
        if color:
            meta.setdefault("folderColors", {})[ps] = color
        else:
            meta.get("folderColors", {}).pop(ps, None)
    save_meta(meta)
    parent = str(Path(paths[0]).parent) if paths else ""
    emit({"event": "mutated", "path": parent})


def handle_preview_text(cmd):
    path_str = cmd.get("path", "")
    req_id = cmd.get("reqId", "")
    p = Path(path_str)
    text = ""
    if p.is_file():
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                text = f.read(32768)
        except Exception as e:
            text = f"Unable to preview file: {e}"
    emit({"event": "previewText", "reqId": req_id, "path": path_str, "text": text})


def default_config():
    return {
        "viewMode": "icon",
        "sortBy": "name",
        "sortAsc": True,
        "showHidden": False,
        "showPathBar": False,
        "showStatusBar": True,
        "showPreview": False,
        "showTabBar": False,
        "sidebarCollapsed": False,
        "iconScale": 80,
        "themeMode": "auto",
        "lastPath": str(HOME),
        "lastTabs": [],
        "activeTabIndex": 0,
    }


def load_config():
    with CONFIG_LOCK:
        cfg = default_config()
        if CONFIG_PATH.exists():
            try:
                loaded = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    cfg.update(loaded)
            except Exception:
                pass
        return cfg


def save_config(cfg):
    with CONFIG_LOCK:
        try:
            CONFIG_PATH.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
        except Exception:
            pass


def handle_get_config(cmd):
    cfg = load_config()
    emit({"event": "config", "config": cfg})


def handle_save_config(cmd):
    incoming = cmd.get("config", {})
    if isinstance(incoming, dict):
        cfg = load_config()
        cfg.update(incoming)
        save_config(cfg)


DESKTOP_FILE = Path.home() / ".local" / "share" / "applications" / "finder.desktop"
LAUNCHER_SCRIPT = Path(__file__).resolve().parent / "finder-launch"


def get_default_file_manager():
    try:
        res = subprocess.run(
            ["xdg-mime", "query", "default", "inode/directory"],
            capture_output=True, text=True, timeout=3, start_new_session=True,
        )
        cur = (res.stdout or "").strip()
        return cur == "finder.desktop", cur
    except Exception:
        return False, ""


def handle_get_default_file_manager(_cmd):
    is_def, cur = get_default_file_manager()
    emit({"event": "defaultFileManager", "isDefault": is_def, "current": cur})


def handle_set_default_file_manager(_cmd):
    DESKTOP_FILE.parent.mkdir(parents=True, exist_ok=True)
    exec_cmd = f'"{LAUNCHER_SCRIPT}" %u' if LAUNCHER_SCRIPT.exists() else f'qs -p "{Path(__file__).resolve().parent.parent / "Finder.qml"}"'
    desktop_content = (
        "[Desktop Entry]\n"
        "Version=1.0\n"
        "Type=Application\n"
        "Name=Finder\n"
        "GenericName=File Manager\n"
        "Comment=Browse files, folders, and archives\n"
        f"Exec={exec_cmd}\n"
        "Icon=system-file-manager\n"
        "Terminal=false\n"
        "MimeType=inode/directory;\n"
        "Categories=System;FileManager;Utility;\n"
        "Keywords=files;folders;directory;finder;\n"
        "StartupNotify=true\n"
    )
    DESKTOP_FILE.write_text(desktop_content, encoding="utf-8")
    try:
        subprocess.run(
            ["xdg-mime", "default", "finder.desktop", "inode/directory"],
            check=True, capture_output=True, text=True, timeout=5, start_new_session=True,
        )
        subprocess.run(
            ["update-desktop-database", str(DESKTOP_FILE.parent)],
            capture_output=True, text=True, timeout=5, start_new_session=True,
        )
    except Exception as e:
        emit({"event": "error", "message": f"Failed to set default file manager: {e}"})
        return
    is_def, cur = get_default_file_manager()
    emit({"event": "defaultFileManager", "isDefault": is_def, "current": cur})
    emit({"event": "busyDone", "label": "Finder is now the default file manager"})


def handle_picker_result(cmd):
    out_file = cmd.get("outFile", "")
    paths = cmd.get("paths", [])
    cancelled = bool(cmd.get("cancelled", False))
    payload = "" if cancelled else "\n".join(str(p) for p in paths)
    if out_file:
        try:
            Path(out_file).write_text(payload, encoding="utf-8")
        except Exception:
            pass
    emit({"event": "pickerSaved"})


def main():
    bg_threads = []
    def run_bg(fn, c):
        t = threading.Thread(target=fn, args=(c,), daemon=True)
        t.start()
        bg_threads.append(t)

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
        except Exception:
            continue
        op = cmd.get("op", "")
        try:
            if op == "sidebar":
                handle_sidebar(cmd)
            elif op == "list":
                handle_list(cmd)
            elif op == "open":
                handle_open(cmd)
            elif op == "listApps":
                handle_list_apps(cmd)
            elif op == "openWith":
                handle_open_with(cmd)
            elif op == "compress":
                run_bg(handle_compress, cmd)
            elif op == "extract":
                run_bg(handle_extract, cmd)
            elif op == "mkdir":
                handle_mkdir(cmd)
            elif op == "rename":
                handle_rename(cmd)
            elif op == "bulkRename":
                handle_bulk_rename(cmd)
            elif op == "duplicate":
                handle_duplicate(cmd)
            elif op == "trash":
                handle_trash(cmd)
            elif op == "emptyTrash":
                handle_empty_trash(cmd)
            elif op == "paste":
                handle_paste(cmd)
            elif op == "clipboardSet":
                handle_clipboard_set(cmd)
            elif op == "clipboardGet":
                handle_clipboard_get(cmd)
            elif op == "setTag":
                handle_set_tag(cmd)
            elif op == "setFolderColor":
                handle_set_folder_color(cmd)
            elif op == "previewText":
                handle_preview_text(cmd)
            elif op == "addSidebarItem":
                handle_add_sidebar_item(cmd)
            elif op == "removeSidebarItem":
                handle_remove_sidebar_item(cmd)
            elif op == "moveSidebarItem":
                handle_move_sidebar_item(cmd)
            elif op == "reorderSidebarItem":
                handle_reorder_sidebar_item(cmd)
            elif op == "addSidebarCategory":
                handle_add_sidebar_category(cmd)
            elif op == "removeSidebarCategory":
                handle_remove_sidebar_category(cmd)
            elif op == "moveSidebarCategory":
                handle_move_sidebar_category(cmd)
            elif op == "resetSidebar":
                handle_reset_sidebar(cmd)
            elif op == "getConfig":
                handle_get_config(cmd)
            elif op == "saveConfig":
                handle_save_config(cmd)
            elif op == "getDefaultFileManager":
                handle_get_default_file_manager(cmd)
            elif op == "setDefaultFileManager":
                handle_set_default_file_manager(cmd)
            elif op == "pickerResult":
                handle_picker_result(cmd)
        except Exception as e:
            emit({"event": "error", "message": str(e)})
    for t in bg_threads:
        if t.is_alive():
            t.join()


if __name__ == "__main__":
    main()
