---
name: testing-down4more
description: End-to-end test recipe for Down4More Flutter on Linux desktop. Use when verifying the Single, Playlist, or Batch tabs, the trim/duration/quality dropdowns, or the per-item cancel/retry flow.
---

# Testing Down4More (Flutter, Linux desktop)

The Flutter project lives at `Year 1/comSociety/Down4More/flutter/`. Run from there.

## Prereqs

Flutter SDK + Linux desktop toolchain, plus yt-dlp and ffmpeg on PATH:

```
flutter config --enable-linux-desktop
flutter pub get
yt-dlp --version    # must succeed
ffmpeg -version     # must succeed (needed for 1080p+ where audio is a separate stream)
```

## Boot, maximize, run

```
flutter run -d linux
# in another shell, once the window is up:
sudo apt-get install -y wmctrl 2>/dev/null
wmctrl -r down4more -b add,maximized_vert,maximized_horz
```

Flutter prints `(com.ziadyounis.down4more.down4more): dbind-WARNING ... AT-SPI: Error retrieving accessibility bus address` on every Linux launch — ignore. It does not affect the app.

## Test URLs that work on this machine

**YouTube hits a bot wall on this VM** without cookies (`Sign in to confirm you're not a bot`). Don't rely on YouTube for any test that needs metadata. Use Vimeo instead:

| Use case | URL | Notes |
|---|---|---|
| Single video, short, has multiple resolutions | `https://vimeo.com/76979871` | "The New Vimeo Player", 19 MB |
| Single video, longer, 50 MB | `https://vimeo.com/19898430` | "skitour slomo" |
| Playlist (showcase) — 5 entries | `https://vimeo.com/showcase/9357160` | Flat-playlist returns titles as `Unknown` until lazy preview enriches them |
| Bad URL for inline-error testing | `https://example.com/notavideo` | yt-dlp returns a 404 |

If the user does provide a YouTube cookie file at `~/.config/down4more/cookies.txt`, it can be plumbed through, but the default flow has no cookies.

## What's where on the UI

- **Single tab** — paste URL, Fetch, Quality dropdown (per-rung sizes), Format dropdown (live size estimate that re-renders when quality changes), optional trim card.
- **Trim card** — soft `primaryContainer` blush when active (NOT vivid red — if it looks like an error, that's a regression on `widgets/trim_input.dart`). Out-of-range warnings render as a filled banner under the time row using `errorContainer` + `Icons.warning_amber_rounded`. Duration fields are digit-shift only — type `551209` to land on `55:12:09`.
- **Playlist tab** — three stages: URL → select → configure. Configure stage's group-folder toggle defaults **ON**, folder name prefilled with `getPlaylistTitle()`. Each row gets its own Quality + Format dropdowns after lazy preview.
- **Batch tab** — paste URLs (one per line), click **Preview** (NOT "Download all" — if it still says "Download all" the relabel got reverted). Group-folder toggle defaults **OFF**, auto-fills to `<first title> batch` when toggled on. Bad URLs render inline in `errorContainer` and don't fail siblings.
- **Per-item action row** — `Cancel` while downloading, `Retry` after error/cancel, `Open` + `Folder` after success, `Remove` otherwise. Lives in `widgets/queue_item_row.dart`.

## Pitfall: per-item cancel is hard to demo with small files

Vimeo's CDN delivers 19 MB and 50 MB files in seconds. By the time a Cancel click registers, the item is already `Saved`. To get a clean `Cancelled` state on screen:

- Use a much larger source (a 4K vimeo.com or a CC-licensed long video), OR
- Throttle the download (system-wide via `tc`/`wondershaper`), OR
- Settle for demonstrating Retry instead — clicking Retry on the bad-URL item transitions through `Downloading…` → `Error` again, which is enough to prove Retry triggers a fresh attempt.

Do not declare T8 "failed" just because the file finished before your click landed — the per-item Cancel button is visibly present during downloading and that's what the spec requires.

## Pitfall: PR-#5-era visible bugs the test plan didn't catch

These are real and may still be in the tree:

- `widgets/queue_item_row.dart` — the per-item Quality + Format dropdowns are inside `SizedBox(width: 220)`, but with `prefixIcon` + dropdown arrow + padding the actual text area is ~160 px. Long labels like `Best available · 301 MB` overflow. Visible as a yellow/black striped pattern on row screenshots; the Flutter framework also prints `RenderFlex overflowed by 23 pixels on the right` from line 232 to stderr. Always check stderr after closing the app.
- `lib/widgets/trim_input.dart` `_DigitShiftField._format` zero-pads intermediate states (e.g. `55` shows as `00:55` instead of `0:55`). The 6-digit endpoint is correct but the intermediate display can confuse.
- `lib/controllers/download_queue_controller.dart` `previewItem()` only replaces the row title when `item.title == item.url || item.title.trim().isEmpty`. Vimeo flat-playlist sets titles to `"Unknown"`, which neither match — so the title never upgrades after preview lands. Per-item Quality / Format / duration / size all enrich correctly.

When reporting test results, scan the `flutter run` stderr stream for `RenderFlex` exceptions, not just the GUI — visible overflow stripes get easy to dismiss as thumbnail artifacts in screenshots.

## Verification commands

From `Year 1/comSociety/Down4More/flutter/`:

```
flutter analyze                # must be clean
flutter test                   # baseline as of PR #5: 57/57 pass
flutter run -d linux           # foreground; redirect stderr to a log if you care about overflow warnings:
# flutter run -d linux 2>&1 | tee /tmp/d4m-run.log
```

No GitHub Actions CI is wired up in this repo as of PR #5 — verification is local only.

## File layout cheat sheet

- `lib/screens/{single,playlist,batch}_screen.dart` — top-level tab UIs.
- `lib/widgets/{trim_input,quality_dropdown,format_dropdown,queue_item_row}.dart` — the user-facing surface most of this skill is about.
- `lib/controllers/{single_download_controller,download_queue_controller,playlist_controller}.dart` — state + yt-dlp orchestration.
- `lib/services/ytdlp_service.dart` — subprocess wrapper. `getPlaylistTitle()` is the helper the playlist configure stage uses to prefill the folder name.
- `lib/models/{video_metadata,output_format,download_progress}.dart` — domain types. `OutputFormat.estimateBytes(sourceVideoBytes, duration)` is what powers the Format dropdown's live size estimate.

## Recording + reporting

When testing UI, record. Annotate per test with `test_start` and `assertion`. Maximize the window before the recording starts. Vimeo is fine in screenshots — the user has seen Vimeo URLs in prior PR comments and won't be confused.

## Devin Secrets Needed

None for the default flow. If a future iteration of the project plumbs YouTube cookies through, set `YOUTUBE_COOKIES` (path or contents of `cookies.txt`) and the controller will read from it.
