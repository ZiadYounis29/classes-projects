# Down4More

Multi-platform video downloader & slicer. Originally built as the project for the
Computer & Society course (Year 1).

Supports YouTube, Instagram, Facebook, X / Twitter, and TikTok via
[yt-dlp](https://github.com/yt-dlp/yt-dlp), with optional time-based slicing via
[ffmpeg](https://ffmpeg.org/).

## Run

```bash
pip install yt-dlp
# install ffmpeg from your package manager (apt / brew / winget)
python server.py
```

The server starts on `http://localhost:8765` and auto-opens it in your browser.

## Features

- YouTube / Instagram / Facebook / X / TikTok video & audio downloads
- Quality picker (best / 1080p / 720p / ...)
- Audio-only export to MP3 / M4A / FLAC / OGG / WAV / OPUS
- Segment trimming via start / end timestamps
- Playlist mode with per-video selective options
- Download queue with pause / resume / cancel / retry
- Auto-retry on network errors with configurable delay
- Persistent settings (download folder, default quality, speed limit, etc.)

## Files

- `server.py` — Python `http.server`-based backend that orchestrates `yt-dlp`
  and `ffmpeg` and serves the UI.
- `index.html` — single-file frontend (HTML + CSS + JS) for the downloader UI.
- `settings.json` — created at runtime; persists user preferences.

## Roadmap

This is the original Python + HTML implementation. A planned future revision
will rebuild this as a self-contained native app for Windows, macOS, Linux,
and Android — yt-dlp bundled per platform, no server, no shared hosting.
