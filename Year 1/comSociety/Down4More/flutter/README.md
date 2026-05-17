# Down4More — Flutter

The Flutter port of the Down4More multi-platform video downloader. One Dart
codebase that targets Linux, macOS, Windows, and Android (no iOS — yt-dlp
can't run inside an iOS app sandbox).

## Status

Feature parity with the Python prototype has been reached on desktop:
single-URL, playlist, and batch downloads with quality + format pickers,
trim, subtitles (embed or sidecar, auto-translate), download history,
real OS pause/resume, and OS-level toast notifications. Windows packaging
now ships with a bundled yt-dlp + ffmpeg; the Android backend is the next
chunk of work.

The Python prototype is archived at
[`../python/legacy/`](../python/legacy/) for reference.

## Run on desktop

```sh
# from this directory:
flutter pub get
flutter run -d linux       # or: -d macos / -d windows
```

On Linux / macOS the app expects `yt-dlp` and `ffmpeg` on `PATH`
(`apt install yt-dlp ffmpeg` / `brew install yt-dlp ffmpeg`). On
Windows the installer bundles both — see the [Windows packaging](#windows-packaging)
section below.

## Test

```sh
flutter analyze            # static analysis
flutter test               # unit + widget tests
```

## Windows packaging

Producing the single-file installer is a three-step flow on a Windows
machine (or any host with Inno Setup + a working Flutter Windows toolchain):

```powershell
# 1. Pull the latest yt-dlp.exe + ffmpeg.exe into windows/runner/bin/.
#    Idempotent — re-run when you want to refresh the bundled binaries.
pwsh -File tools\fetch_windows_binaries.ps1

# 2. Build the Flutter Windows release. The install step in
#    windows/CMakeLists.txt automatically copies the binaries from
#    runner/bin/ next to down4more.exe.
flutter build windows --release

# 3. Compile the installer (replace the version with whatever you're shipping).
iscc /DMyAppVersion=0.1.0 tools\windows_installer.iss
```

The installer ends up under `tools\Output\Down4More-Setup-0.1.0.exe`. It
installs per-user by default (no admin elevation), drops a Start Menu
entry, and registers a clean uninstaller.

`tools/fetch_windows_binaries.sh` is the Bash equivalent for Linux/macOS
hosts that cross-build the Windows installer from CI. Either script
writes to the same `windows/runner/bin/` directory; the binaries are
.gitignored and never committed.

At runtime, [`lib/services/external_binary.dart`](./lib/services/external_binary.dart)
looks for `yt-dlp.exe` / `ffmpeg.exe` next to the running app first, and
falls back to `PATH` so `flutter run -d windows` dev builds keep working
without going through the installer flow.

## Project layout

```
lib/
├── main.dart                    # entry point + top-level MaterialApp
├── theme/
│   ├── theme_preset.dart        # named look-and-feel (color + brightness)
│   ├── theme_presets.dart       # the 6 built-in presets
│   └── theme_controller.dart    # persistence via shared_preferences
├── screens/
│   ├── home_screen.dart         # 5-tab shell (NavigationRail / NavigationBar)
│   ├── single_screen.dart       # PR 3
│   ├── playlist_screen.dart     # PR 4
│   ├── batch_screen.dart        # PR 4
│   ├── files_screen.dart        # PR 5
│   └── settings_screen.dart     # Appearance live, rest as placeholders
└── widgets/
    ├── d4m_logo.dart            # accent-aware "Down4More" wordmark
    ├── theme_picker.dart        # preset chips + custom theme dialog
    └── empty_placeholder.dart   # shared "coming in PR N" empty state
```

## Themes

Six built-in: **Crimson** (default — dark/red), **Sky** (blue/white), **Forest**
(green/black), **Sunset** (orange/dark), **Royal** (purple/dark), **Mono**
(grayscale). Plus a "Custom theme" dialog where you can pick a primary color
and light/dark mode.

Selection persists to disk via `shared_preferences`, so your choice survives
restarts.

## Roadmap

- PR 3: single-URL download flow
- PR 4: playlist + batch + queue
- PR 5: real settings persistence (folder, format, concurrency, retry)
- PR 6: pause / resume / cancel / retry
- PR 7: Android backend (`youtubedl-android` + foreground service)
- PR 8: Desktop backend (bundled `yt-dlp` + `ffmpeg` per OS)
- PR 9: CI builds for Win/Mac/Linux + signed APK
- PR 10: tagged release + install instructions
