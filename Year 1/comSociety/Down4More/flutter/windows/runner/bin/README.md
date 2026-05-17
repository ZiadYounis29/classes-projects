# Bundled Windows binaries (yt-dlp, ffmpeg)

This directory holds the Windows binaries that ship inside the Down4More
installer. **The binaries themselves are not committed to git** — they are
fetched at build time by the `tools/fetch_windows_binaries.ps1` /
`tools/fetch_windows_binaries.sh` scripts and copied into the installer
output by `windows/CMakeLists.txt`.

## Expected contents after running the fetch script

```
windows/runner/bin/
├── README.md          (this file, committed)
├── .gitkeep           (committed, keeps the empty dir in git)
├── yt-dlp.exe         (fetched, ~12 MB, ignored by git)
└── ffmpeg.exe         (fetched, ~80 MB, ignored by git)
```

## Why not commit the binaries?

- They're large (~92 MB combined), which would bloat clones and balloon the
  GitHub LFS bill if we ever pushed to LFS.
- They go stale fast — yt-dlp ships fixes for site-specific extractors every
  few weeks, and we want to pick up new releases without re-committing them.
- Their licences (Unlicense for yt-dlp, GPL/LGPL for ffmpeg) allow
  redistribution but the user's choice of installer format may impose
  different reproducible-build constraints.

## How they get into the final installer

1. Developer runs `tools/fetch_windows_binaries.ps1` (or `.sh` on
   Linux/macOS dev machines) once per release — this downloads the latest
   stable yt-dlp.exe and a Gyan.dev ffmpeg.exe into this directory.
2. `flutter build windows --release` produces `down4more.exe` under
   `build/windows/x64/runner/Release/`.
3. The `install` step in `windows/CMakeLists.txt` copies every `*.exe` from
   this directory into the same output folder so it sits next to
   `down4more.exe`.
4. `tools/windows_installer.iss` is fed to the Inno Setup compiler and
   produces a single `Down4More-Setup-<version>.exe`.

## At runtime

At runtime [`lib/services/external_binary.dart`](../../lib/services/external_binary.dart)
looks for `yt-dlp.exe` and `ffmpeg.exe` next to the running app (i.e. the
install dir). If they're missing — e.g. someone is running a `flutter run
-d windows` dev build without first running the fetch script — the
resolver falls back to `PATH`, so the developer flow still works as long
as both tools are installed system-wide.
