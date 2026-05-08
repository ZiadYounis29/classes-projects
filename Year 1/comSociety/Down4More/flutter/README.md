# Down4More — Flutter

The Flutter port of the Down4More multi-platform video downloader. One Dart
codebase that targets Linux, macOS, Windows, and Android (no iOS — yt-dlp
can't run inside an iOS app sandbox).

## Status

This is **PR 2 of ~10**: the scaffold. The 5-tab shell, navigation, theme
system, and Settings → Appearance section are live. Actual download logic
lands in PR 3+.

The Python prototype lives at [`../python/`](../python/) and continues to
work as a reference until this Flutter version reaches feature parity.

## Run on desktop

```sh
# from this directory:
flutter pub get
flutter run -d linux       # or: -d macos / -d windows
```

## Test

```sh
flutter analyze            # static analysis
flutter test               # unit + widget tests
```

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
