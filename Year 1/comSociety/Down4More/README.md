# Down4More

A multi-platform video downloader (YouTube, Instagram, Facebook, X / Twitter,
TikTok) — in active development, originally a Computer & Society course
project that grew into a personal app.

This folder contains **two implementations of the same app**:

| Folder | Implementation | Status |
|---|---|---|
| [`flutter/`](./flutter) | The current Flutter app. One Dart codebase that targets Linux, macOS, Windows, and Android with native UI on each platform. Self-contained per device — bundles `yt-dlp` + `ffmpeg` on Windows so there's no hub or HTTP server. | **Active.** Feature parity with the Python prototype reached; mobile backend is the next chunk. |
| [`python/legacy/`](./python/legacy) | The original Python `http.server` + HTML/CSS/JS prototype, kept for reference. | **Archived.** No longer maintained. |

## Why keep the Python version around?

It's the original Computer & Society project, plus a useful behaviour
reference while reviewing the Flutter port. It can be removed once the
Flutter app has been signed-off through a full release cycle.

## How to run

For the Python version, see [`python/README.md`](./python/README.md).
For the Flutter version, see [`flutter/README.md`](./flutter/README.md).

## Architecture decisions

- **Self-contained per device.** Each install bundles its own `yt-dlp` and
  `ffmpeg` binaries — no hub, no HTTP server, nothing exposed on the LAN.
- **Native look on each OS.** Material 3 on Android, Material on Linux, with
  per-platform window chrome on desktop. No "this looks like a webpage" feel.
- **No iOS.** Apple's sandbox rules forbid spawning subprocesses, which makes
  yt-dlp impossible to ship in a real iOS app. Anyone who claims otherwise
  is wrong about iOS, not Flutter.

See the per-implementation READMEs for runtime details.
