#!/usr/bin/env bash
# tools/fetch_windows_binaries.sh
#
# Linux/macOS counterpart of tools/fetch_windows_binaries.ps1. Downloads
# yt-dlp.exe + ffmpeg.exe into windows/runner/bin/ so a Windows release
# build can pick them up via the install step in windows/CMakeLists.txt.
#
# Why a non-Windows version? Some devs cross-build the Windows installer
# from CI runners (e.g. GitHub Actions ubuntu-latest -> Wine -> iscc) or
# just want to refresh the bundled binaries before pushing a tag. The
# binaries are platform binaries (PE32) — they don't care which host
# fetched them.
#
# Usage:
#   tools/fetch_windows_binaries.sh           # idempotent, keeps existing
#   tools/fetch_windows_binaries.sh --force   # overwrite existing
#   tools/fetch_windows_binaries.sh --skip-ffmpeg

set -euo pipefail

FORCE=0
SKIP_FFMPEG=0
for arg in "$@"; do
  case "$arg" in
    --force|-f)        FORCE=1 ;;
    --skip-ffmpeg)     SKIP_FFMPEG=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

# tools/ sits at flutter/tools/ — target is flutter/windows/runner/bin/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/windows/runner/bin"
mkdir -p "$BIN_DIR"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 is required (apt install $1 / brew install $1)" >&2
    exit 1
  }
}
need curl
need unzip

download() {
  local url="$1" dest="$2"
  echo "  -> $url"
  # -L follow redirects (GitHub release downloads always redirect).
  # --fail so we get a non-zero exit on 4xx/5xx instead of saving the HTML body.
  curl -L --fail --silent --show-error -o "$dest" "$url"
}

# ── yt-dlp.exe ──────────────────────────────────────────────────────────────
YTDLP="$BIN_DIR/yt-dlp.exe"
if [[ -f "$YTDLP" && "$FORCE" -eq 0 ]]; then
  echo "yt-dlp.exe already present at $YTDLP (use --force to re-fetch)."
else
  echo "Fetching latest yt-dlp.exe from GitHub releases..."
  download "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" "$YTDLP"
  echo "  ok: $(du -h "$YTDLP" | cut -f1)"
fi

# ── ffmpeg.exe ──────────────────────────────────────────────────────────────
if [[ "$SKIP_FFMPEG" -eq 1 ]]; then
  echo "Skipping ffmpeg.exe (--skip-ffmpeg)."
  exit 0
fi

FFMPEG="$BIN_DIR/ffmpeg.exe"
if [[ -f "$FFMPEG" && "$FORCE" -eq 0 ]]; then
  echo "ffmpeg.exe already present at $FFMPEG (use --force to re-fetch)."
  exit 0
fi

# Gyan.dev ships a stable "essentials" build that is the canonical
# Windows ffmpeg distribution recommended on ffmpeg.org.
TMPDIR_FFMPEG="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FFMPEG"' EXIT
ZIP="$TMPDIR_FFMPEG/ffmpeg.zip"

echo "Fetching ffmpeg-release-essentials.zip from gyan.dev..."
download "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" "$ZIP"

echo "Extracting ffmpeg.exe..."
unzip -q "$ZIP" -d "$TMPDIR_FFMPEG"

# Layout inside the zip is ffmpeg-X.Y-essentials_build/bin/ffmpeg.exe — find it.
EXTRACTED="$(find "$TMPDIR_FFMPEG" -type f -name 'ffmpeg.exe' -print -quit)"
if [[ -z "$EXTRACTED" ]]; then
  echo "error: ffmpeg.exe not found inside the gyan.dev zip — layout may have changed." >&2
  exit 1
fi
cp "$EXTRACTED" "$FFMPEG"
echo "  ok: $(du -h "$FFMPEG" | cut -f1)"
echo
echo "All Windows runtime binaries are in $BIN_DIR."
echo "Next (on Windows): flutter build windows --release && iscc tools\\windows_installer.iss"
