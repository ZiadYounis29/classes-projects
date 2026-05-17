# tools/fetch_windows_binaries.ps1
#
# Download the latest yt-dlp.exe and a recent stable ffmpeg.exe and drop them
# into windows/runner/bin/. The Inno Setup installer (and a plain
# `flutter build windows --release` install step) will then copy them next to
# down4more.exe so ExternalBinary can find them at runtime without the user
# having to install anything by hand.
#
# Run this on a Windows dev machine before building a release. Re-run it
# whenever you want to refresh the bundled binaries (yt-dlp ships fixes for
# site-specific extractors every few weeks).
#
# Both binaries are large (~12 MB and ~80 MB) so this script does not commit
# them — they live under windows/runner/bin/*.exe which is .gitignored.
#
# Usage:
#   pwsh -File tools/fetch_windows_binaries.ps1
#
# Optional flags:
#   -Force     overwrite any existing yt-dlp.exe / ffmpeg.exe in runner/bin/.
#   -SkipFfmpeg do NOT download ffmpeg.exe (useful when you only need to
#               refresh yt-dlp during dev).

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipFfmpeg
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# tools/ sits at flutter/tools/ — target is flutter/windows/runner/bin/.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir    = Join-Path (Split-Path -Parent $scriptDir) "windows\runner\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

function Download-File($url, $dest) {
    Write-Host "  -> $url"
    # Force TLS 1.2 — Windows PowerShell 5.1 still defaults to 1.0 / 1.1
    # which most modern GitHub release endpoints reject.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# ── yt-dlp.exe ──────────────────────────────────────────────────────────────
$ytdlpPath = Join-Path $binDir "yt-dlp.exe"
if ((Test-Path $ytdlpPath) -and -not $Force) {
    Write-Host "yt-dlp.exe already present at $ytdlpPath (use -Force to re-fetch)."
} else {
    Write-Host "Fetching latest yt-dlp.exe from GitHub releases..."
    Download-File "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" $ytdlpPath
    Write-Host "  ok: $((Get-Item $ytdlpPath).Length / 1MB) MB"
}

# ── ffmpeg.exe ──────────────────────────────────────────────────────────────
if ($SkipFfmpeg) {
    Write-Host "Skipping ffmpeg.exe (--SkipFfmpeg)."
    exit 0
}

$ffmpegPath = Join-Path $binDir "ffmpeg.exe"
if ((Test-Path $ffmpegPath) -and -not $Force) {
    Write-Host "ffmpeg.exe already present at $ffmpegPath (use -Force to re-fetch)."
    exit 0
}

# Gyan.dev ships a one-file "essentials" build that is the standard
# distribution recommended on ffmpeg.org for Windows. We grab the zip,
# extract just ffmpeg.exe, then delete the rest.
$zipUrl  = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$tmpZip  = Join-Path $env:TEMP "d4m-ffmpeg-release.zip"
$tmpDir  = Join-Path $env:TEMP "d4m-ffmpeg-release"

Write-Host "Fetching ffmpeg-release-essentials.zip from gyan.dev..."
Download-File $zipUrl $tmpZip

Write-Host "Extracting ffmpeg.exe..."
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

$extractedFfmpeg = Get-ChildItem -Path $tmpDir -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
if ($null -eq $extractedFfmpeg) {
    throw "ffmpeg.exe not found inside the downloaded zip — gyan.dev may have changed the layout."
}
Copy-Item $extractedFfmpeg.FullName $ffmpegPath -Force

Remove-Item -Recurse -Force $tmpDir
Remove-Item -Force $tmpZip

Write-Host "  ok: $((Get-Item $ffmpegPath).Length / 1MB) MB"
Write-Host ""
Write-Host "All Windows runtime binaries are in $binDir."
Write-Host "Next: flutter build windows --release && iscc tools\windows_installer.iss"
