#!/usr/bin/env python3
"""Fetch Apple Music Motion artwork for shell27-lock using public catalog data."""

import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/shell27-lock/apple-motion")
TOKEN_FILE = os.path.join(CACHE_DIR, "apple-token.json")
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/128.0 Safari/537.36"


def request(url, headers=None, timeout=8, limit=2 * 1024 * 1024):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read(limit + 1)


def token_expiry(token):
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        import base64
        return int(json.loads(base64.urlsafe_b64decode(payload)).get("exp", 0))
    except Exception:
        return 0


def apple_token():
    now = time.time()
    try:
        with open(TOKEN_FILE, encoding="utf-8") as token_file:
            data = json.load(token_file)
        token = data.get("token", "")
        if token and int(data.get("exp", 0)) > now + 900:
            return token
    except (OSError, ValueError, TypeError):
        pass

    try:
        html = request("https://music.apple.com", timeout=6, limit=2 * 1024 * 1024).decode("utf-8", "ignore")
        assets = re.findall(r'(/assets/[^"\']+\.js)', html)
        token_pattern = re.compile(r'["\'](eyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+)["\']')
        for asset in assets[:4]:
            try:
                script = request(urllib.parse.urljoin("https://music.apple.com", asset), timeout=6,
                                 limit=6 * 1024 * 1024).decode("utf-8", "ignore")
                match = token_pattern.search(script)
                if not match:
                    continue
                token = match.group(1)
                expiry = token_expiry(token)
                if expiry > now + 900:
                    os.makedirs(CACHE_DIR, exist_ok=True)
                    with open(TOKEN_FILE, "w", encoding="utf-8") as token_file:
                        json.dump({"token": token, "exp": expiry}, token_file)
                    return token
            except Exception:
                continue
    except Exception:
        pass
    return ""


def album_id(artist, title, album):
    queries = [" ".join(part for part in (artist, title) if part), title]
    if album and album != title:
        queries.append(" ".join(part for part in (artist, album) if part))
    for query in queries:
        if not query.strip():
            continue
        url = "https://itunes.apple.com/search?" + urllib.parse.urlencode({"term": query, "entity": "song", "limit": 5})
        try:
            result = json.loads(request(url, timeout=6).decode("utf-8", "ignore"))
            for item in result.get("results", []):
                collection_url = item.get("collectionViewUrl", "")
                if not collection_url:
                    continue
                if item.get("trackName", "").casefold() == title.casefold() or not title:
                    return collection_url
        except Exception:
            continue
    return ""


def motion_playlist(artist, title, album):
    collection_url = album_id(artist, title, album)
    match = re.search(r"music\.apple\.com/(?:([a-z]{2})/)?album/(?:[^/]+/)?(\d+)", collection_url)
    if not match:
        return ""
    token = apple_token()
    if not token:
        return ""
    region, collection = match.group(1) or "us", match.group(2)
    url = f"https://amp-api.music.apple.com/v1/catalog/{region}/albums/{collection}?extend=editorialVideo&platform=web"
    try:
        data = json.loads(request(url, headers={"Authorization": "Bearer " + token,
                                                  "Origin": "https://music.apple.com"}, timeout=8).decode("utf-8", "ignore"))
        item = data.get("data", [{}])[0]
        video = item.get("attributes", {}).get("editorialVideo", {})
        return (video.get("motionDetailTall") or video.get("motionTallVideo3x4")
            or video.get("motionDetailSquare") or video.get("motionSquareVideo1x1") or {}).get("video", "")
    except Exception:
        return ""


def fetch(artist, title, album):
    if not title:
        return ""
    os.makedirs(CACHE_DIR, exist_ok=True)
    key = hashlib.sha256((artist + "\0" + title + "\0" + album).encode("utf-8")).hexdigest()
    output = os.path.join(CACHE_DIR, key + ".mp4")
    if os.path.isfile(output) and os.path.getsize(output) > 10000:
        os.utime(output, None)
        return output
    playlist = motion_playlist(artist, title, album)
    if not playlist or not shutil_which("ffmpeg"):
        return ""
    temp = output + ".tmp.mp4"
    try:
        proc = subprocess.run(["ffmpeg", "-nostdin", "-y", "-loglevel", "error", "-i", playlist,
                               "-t", "30", "-c", "copy", "-movflags", "+faststart", temp],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=40, check=False)
        if proc.returncode == 0 and os.path.isfile(temp) and os.path.getsize(temp) > 10000:
            os.replace(temp, output)
            os.utime(output, None)
            return output
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        try:
            os.remove(temp)
        except OSError:
            pass
    return ""


def shutil_which(command):
    from shutil import which
    return which(command)


if __name__ == "__main__":
    try:
        print(fetch(*(sys.argv[1:4] + [""] * 3)[:3]))
    except Exception:
        print("")