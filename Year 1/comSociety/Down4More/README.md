# Down4More

A multi-platform video downloader (YouTube, Instagram, Facebook, X / Twitter,
TikTok) — in active development, originally a Computer & Society course
project that grew into a personal app.

This folder contains **two implementations of the same app**:

| Folder | Implementation | Status |
|---|---|---|
| [`python/`](./python) | The original Python `http.server` + HTML/CSS/JS prototype. Single-file deploy, browser-based UI, runs on Win/Mac/Linux. | **Working today.** Treated as the reference behaviour while the Flutter port catches up. |
| [`flutter/`](./flutter) | The new Flutter port. One Dart codebase that targets Linux, macOS, Windows, and Android with native UI on each platform. Self-contained per device — bundles `yt-dlp` + `ffmpeg` so there's no hub or HTTP server. | **In progress.** PR 2 is the scaffold; download logic lands in PR 3+. |

## Why both?

The Python version is shippable as-is and lets us actually use the app while
the Flutter rewrite is being built. Once the Flutter port reaches feature
parity (around PR 8 in the roadmap), the Python prototype can be archived or
deleted.

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
