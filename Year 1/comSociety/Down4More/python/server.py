#!/usr/bin/env python3
"""
Down4More — Multi-Platform Video Downloader & Slicer
Supports: YouTube, Instagram, Facebook, X/Twitter, TikTok (via yt-dlp)
Run: python server.py
Auto-opens http://localhost:8765 in your browser
"""

import json, os, subprocess, shutil, threading, time, re, webbrowser, platform
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse


def kill_proc_tree(proc):
    """Kill a process and all its children cross-platform."""
    try:
        if platform.system() == "Windows":
            # Windows: taskkill kills the whole tree
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                           capture_output=True)
        else:
            import signal as _signal
            try:
                pgid = os.getpgid(proc.pid)
                os.killpg(pgid, _signal.SIGKILL)
            except ProcessLookupError:
                pass
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


PORT = 8765
_DEFAULT_DOWNLOAD_DIR = os.path.join(os.path.expanduser("~"), "Downloads", "Down4More")
DOWNLOAD_DIR = _DEFAULT_DOWNLOAD_DIR
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Settings file lives next to server.py
SETTINGS_FILE = os.path.join(SCRIPT_DIR, "settings.json")

_SETTINGS_DEFAULTS = {
    "download_dir":        _DEFAULT_DOWNLOAD_DIR,
    "default_quality":     "best",
    "default_format":      "mp4",
    "default_concurrency": 2,
    "speed_limit":         "",
    "auto_retry":          0,
    "retry_delay":         5,
    "keep_temp_on_cancel": False,
}

def _load_settings():
    """Load settings from disk, falling back to defaults for missing keys."""
    base = dict(_SETTINGS_DEFAULTS)
    try:
        with open(SETTINGS_FILE, "r") as f:
            saved = json.load(f)
        base.update({k: saved[k] for k in _SETTINGS_DEFAULTS if k in saved})
    except (FileNotFoundError, json.JSONDecodeError):
        pass  # first run or corrupt file — use defaults
    return base

def _save_settings_to_disk(settings):
    """Persist current settings to settings.json."""
    try:
        with open(SETTINGS_FILE, "w") as f:
            json.dump(settings, f, indent=2)
    except Exception as e:
        print(f"[warn] Could not save settings: {e}")

# Runtime settings — loaded from disk at startup, persisted on every change
SETTINGS = _load_settings()
# Sync DOWNLOAD_DIR from persisted settings
if SETTINGS.get("download_dir"):
    DOWNLOAD_DIR = SETTINGS["download_dir"]

# job_id -> {"pct": 0-100, "msg": "...", "done": bool, "error": str|None, "path": str}
progress_store = {}

# job_id -> subprocess.Popen — kept so /cancel can kill the process
proc_store = {}

# playlist_fetch_id -> {"done": bool, "error": str|None, "videos": [...]}
playlist_store = {}


def find_tool(name):
    path = shutil.which(name)
    if path:
        return path
    for p in [f"/usr/bin/{name}", f"/usr/local/bin/{name}", f"/bin/{name}",
              os.path.expanduser(f"~/.local/bin/{name}")]:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def ensure_deps():
    return [t for t in ["yt-dlp", "ffmpeg"] if find_tool(t) is None]


YOUTUBE_DOMAINS = ("youtube.com", "youtu.be")

def is_youtube(url):
    return any(d in url.lower() for d in YOUTUBE_DOMAINS)


def get_video_info(url):
    ytdlp = find_tool("yt-dlp")
    # --no-playlist is YouTube-specific; on other platforms it's a no-op but safe
    cmd = [ytdlp, "--dump-json", "--no-playlist", url]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "yt-dlp failed to fetch info")
    # Some platforms (TikTok, IG) dump multiple JSON lines; take the first video entry
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if line.startswith("{"):
            info = json.loads(line)
            return _parse_video_info(info)
    raise RuntimeError("No video info returned by yt-dlp")


def _parse_video_info(info):
    formats = info.get("formats", [])
    qualities, seen = [], set()
    for f in reversed(formats):
        h = f.get("height")
        if h and f.get("vcodec") not in (None, "none"):
            lbl = f"{h}p"
            if lbl not in seen:
                seen.add(lbl)
                qualities.append({"label": lbl, "height": h})
    qualities.sort(key=lambda x: x["height"], reverse=True)
    # Thumbnail: try multiple fields
    thumbnail = (info.get("thumbnail") or
                 (info.get("thumbnails") or [{}])[-1].get("url", ""))
    return {
        "id": info.get("id", ""),
        "title": info.get("title") or info.get("description", "")[:80] or "Unknown",
        "duration": info.get("duration") or 0,
        "thumbnail": thumbnail,
        "uploader": info.get("uploader") or info.get("channel") or info.get("uploader_id", ""),
        "webpage_url": info.get("webpage_url", ""),
        "qualities": qualities,   # empty list = platform doesn't expose quality levels
    }


def fetch_playlist_job(fetch_id, url):
    """Fetch all video entries in a playlist (flat, no download)."""
    try:
        ytdlp = find_tool("yt-dlp")
        result = subprocess.run(
            [ytdlp, "--flat-playlist", "--dump-json", url],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "yt-dlp failed")

        videos = []
        for line in result.stdout.strip().splitlines():
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
                vid_url = entry.get("url") or entry.get("webpage_url") or ""
                if vid_url and not vid_url.startswith("http"):
                    vid_url = "https://www.youtube.com/watch?v=" + vid_url
                videos.append({
                    "id": entry.get("id", ""),
                    "title": entry.get("title", "Unknown"),
                    "duration": entry.get("duration", 0),
                    "thumbnail": entry.get("thumbnail") or entry.get("thumbnails", [{}])[-1].get("url", ""),
                    "uploader": entry.get("uploader") or entry.get("channel", ""),
                    "url": vid_url,
                })
            except Exception:
                continue

        playlist_store[fetch_id].update({"done": True, "videos": videos})
    except Exception as e:
        playlist_store[fetch_id].update({"done": True, "error": str(e), "videos": []})


def list_download_files():
    """Return list of files in DOWNLOAD_DIR with metadata."""
    if not os.path.isdir(DOWNLOAD_DIR):
        return []
    files = []
    for fname in os.listdir(DOWNLOAD_DIR):
        if fname.startswith('_temp_') or fname.startswith('.'):
            continue
        fpath = os.path.join(DOWNLOAD_DIR, fname)
        if not os.path.isfile(fpath):
            continue
        stat = os.stat(fpath)
        files.append({
            "name": fname,
            "path": fpath,
            "size": stat.st_size,
            "mtime": int(stat.st_mtime),
        })
    return files


def open_folder_native():
    sys = platform.system()
    if sys == "Darwin":
        subprocess.Popen(["open", DOWNLOAD_DIR])
    elif sys == "Windows":
        subprocess.Popen(["explorer", DOWNLOAD_DIR])
    else:
        subprocess.Popen(["xdg-open", DOWNLOAD_DIR])


def reveal_file_native(path):
    sys = platform.system()
    if sys == "Darwin":
        subprocess.Popen(["open", "-R", path])
    elif sys == "Windows":
        subprocess.Popen(["explorer", "/select,", path])
    else:
        subprocess.Popen(["xdg-open", os.path.dirname(path)])



def _parse_speed_bps(s):
    """Parse yt-dlp speed string e.g. '2.34MiB/s' -> bytes/s float."""
    import re as _re
    m = _re.match(r"([\d.]+)\s*([KMG]?)i?B/s", s.strip(), _re.IGNORECASE)
    if not m: return None
    val, u = float(m.group(1)), m.group(2).upper()
    return val * {"K": 1024, "M": 1024**2, "G": 1024**3}.get(u, 1)

def _parse_eta_secs(s):
    """Parse yt-dlp ETA string e.g. '01:23' or '01:23:45' -> seconds int."""
    parts = s.strip().split(":")
    try:
        if len(parts) == 2: return int(parts[0]) * 60 + int(parts[1])
        if len(parts) == 3: return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except ValueError:
        pass
    return None

def run_with_progress(cmd, job_id, phase_label, phase_start, phase_end):
    # Flag-based pause/resume: when progress_store[job_id]["paused"] is True,
    # we stop reading stdout. The unread pipe buffer fills up and yt-dlp naturally
    # stalls waiting for the reader — no OS signals required, works on any platform.
    kwargs = dict(stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                  text=True, bufsize=1)
    if platform.system() != "Windows":
        kwargs["start_new_session"] = True
    proc = subprocess.Popen(cmd, **kwargs)
    proc_store[job_id] = proc

    pct_re   = re.compile(r"\[download\]\s+([\d.]+)%")
    speed_re = re.compile(r"\bat\s+([\d.]+\s*[KMG]?i?B/s)", re.IGNORECASE)
    eta_re   = re.compile(r"\bETA\s+([\d:]+)", re.IGNORECASE)
    dest_re  = re.compile(r"\[download\] Destination: (.+)")
    merge_re = re.compile(r"\[Merger\]|Merging formats|ffmpeg")
    last_path = None

    for line in proc.stdout:
        state = progress_store.get(job_id, {})

        # Cancel check — kill immediately and stop reading
        if state.get("cancelled"):
            kill_proc_tree(proc)
            break

        # Pause check — block here without reading more output.
        # yt-dlp will stall naturally once its pipe buffer fills (~64 KB).
        while state.get("paused") and not state.get("cancelled"):
            time.sleep(0.3)
            state = progress_store.get(job_id, {})
        if state.get("cancelled"):
            kill_proc_tree(proc)
            break

        line = line.strip()
        m = pct_re.search(line)
        if m:
            raw    = float(m.group(1))
            mapped = phase_start + (raw / 100) * (phase_end - phase_start)
            progress_store[job_id]["pct"] = round(mapped, 1)
            progress_store[job_id]["msg"] = phase_label
            sm = speed_re.search(line)
            progress_store[job_id]["speed"] = _parse_speed_bps(sm.group(1)) if sm else None
            em = eta_re.search(line)
            progress_store[job_id]["eta"]   = _parse_eta_secs(em.group(1)) if em else None
        d = dest_re.search(line)
        if d:
            last_path = d.group(1).strip()
        if merge_re.search(line):
            progress_store[job_id].update({
                "pct": phase_end, "msg": "Merging streams...",
                "speed": None, "eta": None
            })

    proc.wait()
    proc_store.pop(job_id, None)
    if progress_store.get(job_id, {}).get("cancelled"):
        raise RuntimeError("Cancelled")
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed (exit {proc.returncode})")
    return last_path


# Audio formats that use yt-dlp -x extraction
AUDIO_FORMATS = {"mp3", "m4a", "flac", "ogg", "wav", "opus"}
# Video formats that use --merge-output-format
VIDEO_FORMATS  = {"mp4", "mkv", "webm"}


def _run_with_auto_retry(cmd, job_id, label, p_start, p_end):
    max_retries = int(SETTINGS.get("auto_retry", 0))
    delay       = float(SETTINGS.get("retry_delay", 5))
    attempt     = 0
    while True:
        try:
            return run_with_progress(cmd, job_id, label, p_start, p_end)
        except RuntimeError as e:
            if "Cancelled" in str(e):
                raise
            if attempt >= max_retries:
                raise
            attempt += 1
            progress_store[job_id].update({
                "pct": p_start,
                "msg": f"Retry {attempt}/{max_retries} in {delay}s…"
            })
            waited = 0.0
            while waited < delay:
                time.sleep(0.5); waited += 0.5
                if progress_store.get(job_id, {}).get("cancelled"):
                    raise RuntimeError("Cancelled")


def download_job(job_id, url, quality, start_time, end_time, out_format, output_name):
    """out_format: one of mp4/mkv/webm (video) or mp3/m4a/flac/ogg (audio)."""
    global DOWNLOAD_DIR
    dl_dir = DOWNLOAD_DIR          # snapshot at job start in case it changes
    try:
        os.makedirs(dl_dir, exist_ok=True)
        safe = "".join(c for c in output_name if c.isalnum() or c in " -_").strip() or "download"
        safe = safe[:60]
        has_seg = bool(start_time or end_time)
        ytdlp  = find_tool("yt-dlp")
        ffmpeg = find_tool("ffmpeg")
        fmt    = out_format.lower() if out_format else "mp4"

        # Store params for /cancel and /retry
        progress_store[job_id]["safe"]   = safe
        progress_store[job_id]["dl_dir"] = dl_dir
        progress_store[job_id]["params"] = {
            "url": url, "quality": quality,
            "start_time": start_time or "", "end_time": end_time or "",
            "out_format": fmt, "output_name": output_name
        }
        progress_store[job_id].update({"pct": 2, "msg": "Starting download..."})

        if fmt in AUDIO_FORMATS:
            # ── Audio extraction ──────────────────────────────────────────
            # "ogg" is a container not a codec — yt-dlp needs "vorbis" for .ogg output
            ytdlp_fmt = "vorbis" if fmt == "ogg" else fmt
            out_tpl = os.path.join(dl_dir,
                f"_temp_{safe}.%(ext)s" if has_seg else f"{safe}.%(ext)s")
            cmd = [ytdlp, "--no-playlist", "--newline",
                   "-x", "--audio-format", ytdlp_fmt, "--audio-quality", "0",
                   "-o", out_tpl, url]
            if SETTINGS.get("speed_limit"):
                cmd += ["--rate-limit", SETTINGS["speed_limit"]]
            _run_with_auto_retry(cmd, job_id, f"Downloading audio ({fmt.upper()})...", 2, 85)

            # yt-dlp outputs .ogg for vorbis — find the actual file extension it used
            actual_ext = "ogg" if fmt == "ogg" else fmt

            if has_seg:
                progress_store[job_id].update({"pct": 87, "msg": "Trimming segment..."})
                temp_files = [f for f in os.listdir(dl_dir) if f.startswith(f"_temp_{safe}")]
                if not temp_files:
                    raise RuntimeError("Temp file not found after download")
                temp_file  = os.path.join(dl_dir, temp_files[0])
                final_path = os.path.join(dl_dir, f"{safe}.{actual_ext}")
                ff = [ffmpeg, "-y", "-i", temp_file]
                if start_time: ff += ["-ss", start_time]
                if end_time:   ff += ["-to", end_time]
                ff += ["-c", "copy", final_path]
                subprocess.run(ff, capture_output=True, check=True)
                os.remove(temp_file)
            else:
                files = [f for f in os.listdir(dl_dir) if safe in f and f.endswith(f".{actual_ext}")]
                final_path = os.path.join(dl_dir, files[0]) if files else dl_dir

        else:
            # ── Video download ────────────────────────────────────────────
            height = quality.replace("p", "") if quality else "best"
            if height.isdigit() and is_youtube(url):
                yt_fmt = f"bestvideo[height<={height}]+bestaudio/best[height<={height}]"
            else:
                yt_fmt = "bestvideo+bestaudio/best"

            out_tpl = os.path.join(dl_dir,
                f"_temp_{safe}.%(ext)s" if has_seg else f"{safe}.%(ext)s")
            cmd = [ytdlp, "--no-playlist", "--newline",
                   "-f", yt_fmt, "--merge-output-format", fmt,
                   "-o", out_tpl, url]
            if SETTINGS.get("speed_limit"):
                cmd += ["--rate-limit", SETTINGS["speed_limit"]]
            _run_with_auto_retry(cmd, job_id, f"Downloading video ({fmt.upper()})...", 2, 90)

            if has_seg:
                progress_store[job_id].update({"pct": 92, "msg": "Trimming segment..."})
                temp_files = [f for f in os.listdir(dl_dir) if f.startswith(f"_temp_{safe}")]
                if not temp_files:
                    raise RuntimeError("Temp file not found after download")
                temp_file  = os.path.join(dl_dir, temp_files[0])
                final_path = os.path.join(dl_dir, f"{safe}.{fmt}")
                ff = [ffmpeg, "-y", "-i", temp_file]
                if start_time: ff += ["-ss", start_time]
                if end_time:   ff += ["-to", end_time]
                ff += ["-c", "copy", final_path]
                subprocess.run(ff, capture_output=True, check=True)
                os.remove(temp_file)
            else:
                files = [f for f in os.listdir(dl_dir) if safe in f and f.endswith(f".{fmt}")]
                final_path = os.path.join(dl_dir, files[0]) if files else dl_dir

        progress_store[job_id].update({"pct": 100, "msg": "Done!", "done": True, "path": final_path})

    except Exception as e:
        progress_store[job_id].update({"done": True, "error": str(e), "msg": "Failed"})


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path in ("/", "/index.html"):
            html_path = os.path.join(SCRIPT_DIR, "index.html")
            if os.path.exists(html_path):
                with open(html_path, "rb") as f:
                    body = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", len(body))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_json({"error": "index.html not found next to server.py"}, 404)
            return

        if parsed.path == "/status":
            missing = ensure_deps()
            tools_info = {t: (find_tool(t) or "NOT FOUND") for t in ["yt-dlp", "ffmpeg"]}
            self.send_json({"ok": len(missing) == 0, "missing": missing,
                            "tools": tools_info, "download_dir": DOWNLOAD_DIR})

        elif parsed.path == "/get_settings":
            self.send_json({"ok": True, "settings": {**SETTINGS, "download_dir": DOWNLOAD_DIR}})

        elif parsed.path == "/info":
            params = parse_qs(parsed.query)
            url = params.get("url", [""])[0]
            if not url:
                self.send_json({"error": "No URL"}, 400); return
            try:
                self.send_json({"ok": True, "info": get_video_info(url)})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)

        elif parsed.path == "/playlist_status":
            params = parse_qs(parsed.query)
            fetch_id = params.get("fetch_id", [""])[0]
            state = playlist_store.get(fetch_id)
            if not state:
                self.send_json({"error": "Unknown fetch"}, 404); return
            self.send_json(state)

        elif parsed.path == "/files":
            self.send_json({
                "ok": True,
                "directory": DOWNLOAD_DIR,
                "files": list_download_files()
            })

        elif parsed.path == "/progress":
            params = parse_qs(parsed.query)
            job_id = params.get("job_id", [""])[0]
            state = progress_store.get(job_id)
            if not state:
                self.send_json({"error": "Unknown job"}, 404); return
            # Include paused flag explicitly so frontend can react to it
            self.send_json({**state, "paused": state.get("paused", False)})

        else:
            self.send_json({"error": "Not found"}, 404)

    def do_POST(self):
        global DOWNLOAD_DIR
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))

        if self.path == "/download":
            url         = body.get("url", "")
            quality     = body.get("quality", "best")
            start_time  = body.get("start_time", "").strip() or None
            end_time    = body.get("end_time", "").strip() or None
            out_format  = body.get("out_format", "mp4")
            output_name = body.get("output_name", "download")

            if not url:
                self.send_json({"ok": False, "error": "No URL"}); return

            job_id = str(int(time.time() * 1000))
            progress_store[job_id] = {"pct": 0, "msg": "Queued...", "done": False,
                                      "error": None, "path": None}
            t = threading.Thread(
                target=download_job,
                args=(job_id, url, quality, start_time, end_time, out_format, output_name),
                daemon=True
            )
            t.start()
            self.send_json({"ok": True, "job_id": job_id})

        elif self.path == "/set_folder":
            folder = body.get("folder", "").strip()
            if not folder:
                self.send_json({"ok": False, "error": "No folder path"}); return
            try:
                os.makedirs(folder, exist_ok=True)
                DOWNLOAD_DIR = folder
                SETTINGS["download_dir"] = folder
                _save_settings_to_disk(SETTINGS)
                self.send_json({"ok": True, "folder": DOWNLOAD_DIR})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)})

        elif self.path == "/save_settings":
            allowed = {"download_dir","default_quality","default_format",
                       "default_concurrency","speed_limit","auto_retry",
                       "retry_delay","keep_temp_on_cancel"}
            for k, v in body.items():
                if k in allowed:
                    SETTINGS[k] = v
            if "download_dir" in body and str(body["download_dir"]).strip():
                folder = str(body["download_dir"]).strip()
                try:
                    os.makedirs(folder, exist_ok=True)
                    DOWNLOAD_DIR = folder
                    SETTINGS["download_dir"] = folder
                except Exception as e:
                    self.send_json({"ok": False, "error": str(e)}); return
            _save_settings_to_disk(SETTINGS)
            self.send_json({"ok": True, "settings": {**SETTINGS, "download_dir": DOWNLOAD_DIR}})

        elif self.path == "/open_folder":
            try:
                open_folder_native()
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)})

        elif self.path == "/reveal_file":
            path = body.get("path", "")
            if not path or not os.path.isfile(path):
                self.send_json({"ok": False, "error": "File not found"}); return
            try:
                reveal_file_native(path)
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)})

        elif self.path == "/delete_file":
            path = body.get("path", "")
            # Safety: only allow deleting files inside DOWNLOAD_DIR
            if not path or not os.path.isfile(path):
                self.send_json({"ok": False, "error": "File not found"}); return
            if not os.path.abspath(path).startswith(os.path.abspath(DOWNLOAD_DIR)):
                self.send_json({"ok": False, "error": "Access denied"}); return
            try:
                os.remove(path)
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)})

        elif self.path == "/cancel":
            job_id = body.get("job_id", "")
            if not job_id or job_id not in progress_store:
                self.send_json({"ok": False, "error": "Unknown job"}); return

            # 1. Mark cancelled so run_with_progress loop exits
            progress_store[job_id]["cancelled"] = True

            # 2. Kill the process tree immediately — don't wait for next line read
            proc = proc_store.get(job_id)
            if proc:
                kill_proc_tree(proc)

            # 3. Delete partial files unless keep_temp_on_cancel is set
            safe = progress_store[job_id].get("safe", "")
            dl_dir = progress_store[job_id].get("dl_dir", DOWNLOAD_DIR)
            if safe and os.path.isdir(dl_dir) and not SETTINGS.get("keep_temp_on_cancel"):
                for fname in os.listdir(dl_dir):
                    if fname.startswith(f"_temp_{safe}") or fname.startswith(safe):
                        try:
                            os.remove(os.path.join(dl_dir, fname))
                        except Exception:
                            pass

            # 4. Mark job as done so any stray poll returns cleanly
            progress_store[job_id].update({"done": True, "error": "Cancelled"})

            self.send_json({"ok": True})

        elif self.path == "/fetch_playlist":
            url = body.get("url", "")
            if not url:
                self.send_json({"ok": False, "error": "No URL"}); return
            fetch_id = "pl_" + str(int(time.time() * 1000))
            playlist_store[fetch_id] = {"done": False, "error": None, "videos": []}
            t = threading.Thread(target=fetch_playlist_job, args=(fetch_id, url), daemon=True)
            t.start()
            self.send_json({"ok": True, "fetch_id": fetch_id})

        elif self.path == "/pause":
            job_id = body.get("job_id", "")
            if not job_id or job_id not in progress_store:
                self.send_json({"ok": False, "error": "Unknown job"}); return
            state = progress_store[job_id]
            if state.get("done") or state.get("paused"):
                self.send_json({"ok": False, "error": "Cannot pause"}); return
            # Flag-based pause: run_with_progress checks this and stalls its read loop.
            # No OS signals needed — works on Android/Termux and every other platform.
            progress_store[job_id]["paused"] = True
            progress_store[job_id]["msg"] = "Paused"
            progress_store[job_id]["speed"] = None
            progress_store[job_id]["eta"] = None
            self.send_json({"ok": True})

        elif self.path == "/resume":
            job_id = body.get("job_id", "")
            if not job_id or job_id not in progress_store:
                self.send_json({"ok": False, "error": "Unknown job"}); return
            if not progress_store[job_id].get("paused"):
                self.send_json({"ok": False, "error": "Not paused"}); return
            progress_store[job_id]["paused"] = False
            progress_store[job_id]["msg"] = "Downloading..."
            self.send_json({"ok": True})

        elif self.path == "/retry":
            job_id = body.get("job_id", "")
            if not job_id or job_id not in progress_store:
                self.send_json({"ok": False, "error": "Unknown job"}); return
            old = progress_store[job_id]
            if not old.get("done"):
                self.send_json({"ok": False, "error": "Job not finished yet"}); return
            params = old.get("params")
            if not params:
                self.send_json({"ok": False, "error": "No retry params stored"}); return
            new_job_id = str(int(time.time() * 1000))
            progress_store[new_job_id] = {"pct": 0, "msg": "Queued...", "done": False,
                                           "error": None, "path": None, "paused": False}
            t = threading.Thread(
                target=download_job,
                args=(new_job_id, params["url"], params["quality"],
                      params["start_time"] or None, params["end_time"] or None,
                      params.get("out_format", params.get("mp3_only") and "mp3" or "mp4"),
                      params["output_name"]),
                daemon=True
            )
            t.start()
            self.send_json({"ok": True, "job_id": new_job_id})

        else:
            self.send_json({"error": "Not found"}, 404)


def main():
    print("=" * 54)
    print("  Down4More — Multi-Platform Video Downloader")
    print("  YouTube · Instagram · Facebook · X · TikTok")
    print("=" * 54)
    missing = ensure_deps()
    if missing:
        print(f"\n⚠️  Missing tools: {', '.join(missing)}")
        print("   Install with: pip install yt-dlp  +  brew/apt install ffmpeg")
    else:
        for t in ["yt-dlp", "ffmpeg"]:
            print(f"  ✓ {t}: {find_tool(t)}")
    print(f"\n✅  http://localhost:{PORT}")
    print(f"📁  {DOWNLOAD_DIR}")
    print("    Press Ctrl+C to stop.\n")

    # Auto-open browser after a brief delay so server is up
    def open_browser():
        time.sleep(1.2)
        webbrowser.open(f"http://localhost:{PORT}")
    threading.Thread(target=open_browser, daemon=True).start()

    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
