import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/download_progress.dart';
import '../models/playlist_entry.dart';
import '../models/subtitle_settings.dart';
import '../models/video_metadata.dart';
import 'download_backend.dart';
import 'external_binary.dart';

/// Thin wrapper around the `yt-dlp` CLI. Pure Dart, no UI deps — safe to
/// unit-test by injecting a [_ProcessRunner] / [_ProcessSpawner].
///
/// On Linux / macOS we shell out to whichever `yt-dlp` / `ffmpeg` is on
/// `PATH` (apt, brew, etc.). On Windows we look for `yt-dlp.exe` /
/// `ffmpeg.exe` next to the running app first — the Inno Setup installer
/// drops them there so users don't have to install anything by hand — and
/// fall back to `PATH` if the bundled copies are missing (e.g. dev builds).
/// Path resolution lives in [ExternalBinary].
///
/// Tests can bypass [ExternalBinary] entirely by passing explicit
/// [executable] and [ffmpegExecutable] strings to the constructor.
///
/// Implements [DownloadBackend] so controllers can be wired against the
/// abstract interface; on Android the stub backend is used instead.
class YtDlpService implements DownloadBackend {
  YtDlpService({
    String? executable,
    String? ffmpegExecutable,
    Future<ProcessResult> Function(String, List<String>)? processRunner,
    Future<Process> Function(String, List<String>)? processSpawner,
  })  : _exeOverride = executable,
        _ffmpegOverride = ffmpegExecutable,
        _runner = processRunner ?? _defaultRunner,
        _spawner = processSpawner ?? _defaultSpawner;

  // Explicit overrides take precedence over auto-resolved paths. Tests pass
  // these so they never hit the disk / never depend on installed binaries.
  final String? _exeOverride;
  final String? _ffmpegOverride;
  // Cached resolved paths. Populated on first use by [_getExe] / [_getFfmpeg].
  String? _exeResolved;
  String? _ffmpegResolved;
  final Future<ProcessResult> Function(String, List<String>) _runner;
  final Future<Process> Function(String, List<String>) _spawner;

  /// Resolve the absolute path / command to launch yt-dlp with. Cached after
  /// the first call so we don't poke the filesystem on every download.
  Future<String> _getExe() async {
    final override = _exeOverride;
    if (override != null) return override;
    return _exeResolved ??= await ExternalBinary.ytDlp();
  }

  /// Resolve the absolute path / command to launch ffmpeg with. Same caching
  /// shape as [_getExe].
  Future<String> _getFfmpeg() async {
    final override = _ffmpegOverride;
    if (override != null) return override;
    return _ffmpegResolved ??= await ExternalBinary.ffmpeg();
  }

  /// Run `yt-dlp --dump-single-json` to fetch metadata for a single URL.
  ///
  /// Throws [YtDlpException] if the process exits non-zero. The thrown
  /// message is yt-dlp's own stderr — that's more useful to surface than a
  /// paraphrase, e.g. "Sign in to confirm you're not a bot" or "Video
  /// unavailable in your country".
  @override
  Future<VideoMetadata> fetchMetadata(String url) async {
    if (url.trim().isEmpty) {
      throw YtDlpException('URL is empty.');
    }
    const args = <String>[
      '--dump-single-json',
      '--no-playlist',
      '--no-warnings',
    ];
    final fullArgs = [...args, url];

    final exe = await _getExe();
    final ProcessResult result;
    try {
      result = await _runner(exe, fullArgs);
    } on ProcessException catch (e) {
      throw YtDlpException(
        'yt-dlp not found at "$exe". Install it with `pip install yt-dlp` '
        'or apt/brew. Original error: ${e.message}',
      );
    }
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?)?.trim() ?? '';
      throw YtDlpException(
        stderr.isEmpty
            ? 'yt-dlp exited with code ${result.exitCode}.'
            : stderr,
      );
    }
    final stdout = result.stdout as String;
    try {
      final json = jsonDecode(stdout) as Map<String, dynamic>;
      return VideoMetadata.fromJson(url, json);
    } on FormatException catch (e) {
      throw YtDlpException(
        "Couldn't parse yt-dlp's JSON output: ${e.message}",
      );
    }
  }

  /// Run `yt-dlp --flat-playlist --dump-json` to list all entries in a
  /// playlist without downloading anything. Each line of stdout is a JSON
  /// object describing one video.
  ///
  /// Throws [YtDlpException] on failure.
  @override
  Future<List<PlaylistEntry>> fetchPlaylist(String url) async {
    if (url.trim().isEmpty) {
      throw YtDlpException('URL is empty.');
    }
    final args = <String>[
      '--flat-playlist',
      '--dump-json',
      '--no-warnings',
      url,
    ];

    final exe = await _getExe();
    final ProcessResult result;
    try {
      result = await _runner(exe, args);
    } on ProcessException catch (e) {
      throw YtDlpException(
        'yt-dlp not found at "$exe". Install it with `pip install yt-dlp` '
        'or apt/brew. Original error: ${e.message}',
      );
    }
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?)?.trim() ?? '';
      throw YtDlpException(
        stderr.isEmpty
            ? 'yt-dlp exited with code ${result.exitCode}.'
            : stderr,
      );
    }

    final stdout = result.stdout as String;
    final entries = <PlaylistEntry>[];
    for (final line in stdout.trim().split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final entry = PlaylistEntry.fromJson(json);
        if (entry.url.isNotEmpty) entries.add(entry);
      } catch (_) {
        continue;
      }
    }
    return entries;
  }

  /// Run `yt-dlp --flat-playlist --print %(playlist_title)s` to get the
  /// playlist's own title. Used to seed the group-folder name in the
  /// Playlist tab so the user doesn't have to type it themselves.
  ///
  /// Returns `null` (rather than throwing) when yt-dlp emits no title — many
  /// non-YouTube playlists, "Mix" / autogenerated playlists, or single-video
  /// URLs simply don't have one. Callers should fall back to a default name.
  @override
  Future<String?> getPlaylistTitle(String url) async {
    if (url.trim().isEmpty) return null;
    final args = <String>[
      '--flat-playlist',
      '--print',
      '%(playlist_title|)s',
      '--no-warnings',
      // Some extractors print one line per entry even with --print; we only
      // need the first non-empty one.
      '--playlist-items',
      '1',
      url,
    ];
    final exe = await _getExe();
    final ProcessResult result;
    try {
      result = await _runner(exe, args);
    } on ProcessException {
      return null;
    }
    if (result.exitCode != 0) return null;
    final stdout = (result.stdout as String?) ?? '';
    for (final line in stdout.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty && t != 'NA') return t;
    }
    return null;
  }

  /// Start an actual download. Returns a [DownloadHandle] you can listen to
  /// for [DownloadProgress] events and call [DownloadHandle.cancel] on.
  ///
  /// [outputExt] is the desired container/codec extension chosen by the user,
  /// e.g. 'mp4', 'mkv', 'mp3', 'm4a'. When [format] is audio-only the
  /// service switches to -x --audio-format mode automatically.
  ///
  /// [trimStart] / [trimEnd] are optional segment boundaries. When either is
  /// provided the service downloads to a hidden temp file first, then runs
  /// ffmpeg to cut the segment into the final file and deletes the temp.
  /// Requires ffmpeg on PATH.
  ///
  /// The returned stream completes (closes) once yt-dlp exits, regardless of
  /// success/failure/cancel. Listen for the terminal phase event and update
  /// UI state accordingly.
  @override
  DownloadHandle download({
    required VideoMetadata metadata,
    required VideoFormat format,
    required String outputDir,
    String outputExt = 'mp4',
    String outputTemplate = '%(title).200B.%(ext)s',
    String? customFilename,
    Duration? trimStart,
    Duration? trimEnd,
    String? rateLimit,
    bool keepPartial = false,
    SubtitleSettings? subtitles,
  }) {
    final controller = StreamController<DownloadProgress>.broadcast();
    final processCompleter = Completer<Process>();
    final state = _DownloadState();

    final bool isTrimming = trimStart != null || trimEnd != null;

    // yt-dlp handles audio-only differently from video:
    //   video: --merge-output-format <ext>  (remux after muxing streams)
    //   audio: -x --audio-format <ext>      (extract + transcode)
    // 'ogg' is a container not a codec — yt-dlp needs 'vorbis' internally.
    final bool isAudio = format.isAudioOnly;
    final String ytdlpAudioFmt = outputExt == 'ogg' ? 'vorbis' : outputExt;

    // When trimming we download to a temp file so ffmpeg can read it cleanly.
    // The temp name uses a fixed prefix so it can be found and deleted on error.
    final String effectiveTemplate;
    if (isTrimming) {
      effectiveTemplate = '_d4m_temp_${DateTime.now().millisecondsSinceEpoch}.%(ext)s';
    } else if (customFilename != null && customFilename.isNotEmpty) {
      effectiveTemplate = '${_sanitizeFilename(customFilename)}.%(ext)s';
    } else {
      effectiveTemplate = outputTemplate;
    }

    // Build subtitle-related flags. We only add them when the user has
    // explicitly enabled subtitles AND the language string is non-empty —
    // otherwise the SubtitleSettings.disabled instance is a no-op and yt-dlp
    // gets no extra flags. Embedding is only honoured for video output and
    // for containers that actually carry subs (MP4 / MKV); for everything
    // else the toggle quietly falls back to writing a sidecar file.
    final List<String> subtitleArgs;
    if (subtitles != null &&
        subtitles.enabled &&
        subtitles.language.trim().isNotEmpty) {
      final lang = subtitles.language.trim();
      final fmt = subtitles.format.trim().isEmpty
          ? 'srt'
          : subtitles.format.trim();
      final canEmbed = !isAudio && kEmbedSubsSupportedExts.contains(outputExt);

      if (subtitles.useAutoCaption) {
        // Auto-caption track — use --write-auto-subs to fetch the track.
        // When embedding, yt-dlp's --embed-subs pipeline only activates when
        // --write-subs is also present; without it, --embed-subs silently does
        // nothing and the auto-caption is never downloaded. So we pass both
        // flags together when the user wants to embed.
        subtitleArgs = <String>[
          '--write-auto-subs',
          if (subtitles.embed && canEmbed) '--write-subs',
          '--sub-langs', lang,
          '--sub-format', '$fmt/best',
          '--convert-subs', fmt,
          if (subtitles.embed && canEmbed) '--embed-subs',
          '--sleep-subtitles', '1',
        ];
      } else {
        // Manual subtitle track selected.
        subtitleArgs = <String>[
          '--write-subs',
          '--sub-langs', lang,
          '--sub-format', '$fmt/best',
          '--convert-subs', fmt,
          if (subtitles.embed && canEmbed) '--embed-subs',
          '--sleep-subtitles', '1',
        ];
      }
    } else {
      subtitleArgs = const <String>[];
    }

    final args = <String>[
      '--newline',
      '--no-playlist',
      '--no-warnings',
      '--no-cache-dir',
      // When the user does NOT want partial files kept, tell yt-dlp to write
      // directly to the final filename instead of a .part sidecar. That way
      // our own _deleteTempFile cleanup reliably removes the file on cancel
      // or error. When keepPartial IS true we omit this flag so yt-dlp's
      // default behaviour (write .part, rename on completion) is preserved.
      if (!keepPartial) '--no-part',
      '-f', format.id,
      if (isAudio) ...['-x', '--audio-format', ytdlpAudioFmt]
      else ...['--merge-output-format', outputExt],
      if (rateLimit != null && rateLimit.isNotEmpty) ...['--rate-limit', rateLimit],
      ...subtitleArgs,
      '-o', p.join(outputDir, effectiveTemplate),
      metadata.url,
    ];

    Future<void> run() async {
      final String exe;
      try {
        exe = await _getExe();
      } on UnsupportedError catch (e) {
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.error,
            errorMessage: e.message?.toString() ?? e.toString(),
          ),
        );
        await controller.close();
        processCompleter.completeError(e);
        return;
      }
      Process process;
      try {
        process = await _spawner(exe, args);
      } on ProcessException catch (e) {
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.error,
            errorMessage: 'yt-dlp not found at "$exe": ${e.message}',
          ),
        );
        await controller.close();
        processCompleter.completeError(e);
        return;
      }
      processCompleter.complete(process);

      controller.add(const DownloadProgress(phase: DownloadPhase.downloading));

      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final progress = parseProgressLine(line);
        if (progress == null) return;
        if (progress.outputPath != null) {
          state.outputPath = progress.outputPath;
          state.writtenPaths.add(progress.outputPath!);
        }
        // Detect when yt-dlp starts merging the separate streams.
        if (progress.message?.startsWith('Merging audio + video') == true) {
          state.mergeStarted = true;
        }
        if (progress.percent != null) {
          state.lastPercent = progress.percent;
        }
        // Carry the paused flag through so the UI stays correct while
        // progress lines trickle in from the buffer during a pause.
        if (state.paused) {
          controller.add(DownloadProgress(
            phase: progress.phase,
            paused: true,
            percent: progress.percent,
            speedBytesPerSecond: null,
            eta: null,
            totalBytes: progress.totalBytes,
            outputPath: progress.outputPath,
            message: 'Paused',
          ));
        } else {
          controller.add(progress);
        }
      });

      // Pause/resume via OS-level process suspension so yt-dlp genuinely
      // stops downloading — not just stops printing progress.
      //
      // The stdout-backpressure trick (pausing the StreamSubscription so the
      // OS pipe buffer fills) does NOT work for yt-dlp: Python buffers its
      // own stdout independently of the OS pipe, and the network download
      // runs in a separate thread that is unaffected by stdout blocking.
      //
      // Instead we use SIGSTOP/SIGCONT on POSIX and NtSuspendProcess on
      // Windows. We also pause/resume the Dart stdout subscription so the
      // progress bar freezes correctly in the UI and buffered lines emitted
      // just before the signal are drained cleanly on resume.
      state.pauseCallback = () async {
        stdoutSub.pause();
        await _suspendProcess(process.pid);
        controller.add(DownloadProgress(
          phase: DownloadPhase.downloading,
          paused: true,
          percent: state.lastPercent,
          message: 'Paused',
        ));
      };
      state.resumeCallback = () async {
        await _resumeProcess(process.pid);
        stdoutSub.resume();
        controller.add(DownloadProgress(
          phase: DownloadPhase.downloading,
          paused: false,
          percent: state.lastPercent,
          message: 'Resuming…',
        ));
      };

      final stderrBuf = StringBuffer();
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen(stderrBuf.write);

      final code = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      if (state.cancelled) {
        // On cancel we must clean up carefully:
        //
        // yt-dlp downloads video and audio as *separate* streams before
        // merging them. If the user cancels during the audio download the
        // video stream is already a complete, valid file on disk — but it has
        // no audio. We must never leave that file visible as a finished MP4.
        //
        // • keepPartial == false  → delete every file that was written,
        //   including the audio-less video stream, any .part sidecars, and
        //   the not-yet-created merge output.
        // • keepPartial == true   → keep the partial data on disk (the user
        //   explicitly asked for this) but do NOT emit a finished event, so
        //   the audio-less file is never shown as a completed download.
        if (!keepPartial) {
          _deleteAllWrittenFiles(state.writtenPaths);
        }
        controller.add(const DownloadProgress(phase: DownloadPhase.cancelled));
        await controller.close();
        return;
      }

      if (code != 0) {
        if (!keepPartial) _deleteAllWrittenFiles(state.writtenPaths);
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.error,
            errorMessage: stderrBuf.toString().trim().isEmpty
                ? 'yt-dlp exited with code $code.'
                : stderrBuf.toString().trim(),
          ),
        );
        await controller.close();
        return;
      }

      // ── Phase 2: ffmpeg trim (only when start/end was requested) ──────────
      if (isTrimming) {
        final tempPath = state.outputPath;
        if (tempPath == null || !File(tempPath).existsSync()) {
          controller.add(
            const DownloadProgress(
              phase: DownloadPhase.error,
              errorMessage:
                  'Trim failed: could not locate the downloaded temp file.',
            ),
          );
          await controller.close();
          return;
        }

        controller.add(
          const DownloadProgress(
            phase: DownloadPhase.trimming,
            message: 'Trimming segment with ffmpeg…',
          ),
        );

        final tempExt = p.extension(tempPath); // includes the dot
        // Use custom filename if provided, otherwise auto-generate from
        // the video title + trim range.
        final String finalName;
        if (customFilename != null && customFilename.isNotEmpty) {
          finalName = _sanitizeFilename(customFilename);
        } else {
          final safeTitle = _sanitizeFilename(metadata.title);
          final startStr = _formatTrimRange(trimStart ?? Duration.zero);
          final endStr = _formatTrimRange(trimEnd ?? metadata.duration ?? Duration.zero);
          finalName = '$safeTitle [$startStr-$endStr]';
        }
        final finalPath = p.join(outputDir, '$finalName$tempExt');

        final ffmpegArgs = _buildFfmpegArgs(
          inputPath: tempPath,
          outputPath: finalPath,
          start: trimStart,
          end: trimEnd,
        );

        final ffmpeg = await _getFfmpeg();
        final ffResult = await _runner(ffmpeg, ffmpegArgs);

        // Rename subtitle sidecar files to match the final trimmed name,
        // then trim their content to the same time window as the video so
        // the captions stay in sync with the shorter clip.
        _renameTempSubtitleFiles(tempPath, outputDir, finalName);
        _trimSubtitleFiles(
          outputDir, finalName, trimStart ?? Duration.zero, trimEnd,
        );

        // Delete the temp video file regardless of ffmpeg outcome.
        _deleteTempFile(tempPath);

        if (state.cancelled) {
          _deleteTempFile(finalPath);
          controller.add(
            const DownloadProgress(phase: DownloadPhase.cancelled),
          );
          await controller.close();
          return;
        }

        if (ffResult.exitCode != 0) {
          final ffErr = (ffResult.stderr as String?)?.trim() ?? '';
          controller.add(
            DownloadProgress(
              phase: DownloadPhase.error,
              errorMessage: ffErr.isEmpty
                  ? 'ffmpeg exited with code ${ffResult.exitCode}. '
                    'Make sure ffmpeg is installed.'
                  : 'ffmpeg error: $ffErr',
            ),
          );
          await controller.close();
          return;
        }

        controller.add(
          DownloadProgress(
            phase: DownloadPhase.finished,
            percent: 100,
            outputPath: finalPath,
            message: 'Saved.',
          ),
        );
        await controller.close();
        return;
      }

      // ── No trim: done ─────────────────────────────────────────────────────
      controller.add(
        DownloadProgress(
          phase: DownloadPhase.finished,
          percent: 100,
          outputPath: state.outputPath,
          message: 'Saved.',
        ),
      );
      await controller.close();
    }

    run();

    return DownloadHandle._(
      stream: controller.stream,
      processFuture: processCompleter.future,
      onCancel: () => state.cancelled = true,
      onPause:  () {
        state.paused = true;
        state.pauseCallback?.call(); // fire-and-forget async
      },
      onResume: () {
        state.paused = false;
        state.resumeCallback?.call(); // fire-and-forget async
      },
    );
  }

  /// Open the downloaded file in the system's default viewer.
  ///
  /// Wraps `url_launcher`'s `launchUrl(Uri.file(...))` so all desktop
  /// callers go through the same code path as the Android backend's
  /// MethodChannel implementation. Catches everything so callers can
  /// branch on the boolean without needing a try/catch at every call site.
  @override
  Future<bool> openFile(String path) async {
    if (path.isEmpty) return false;
    try {
      return await launchUrl(Uri.file(path));
    } catch (_) {
      return false;
    }
  }

  /// Open the parent folder of [path] in the system file manager.
  ///
  /// We deliberately pop one level so reveal-style "show in folder" lands
  /// in the directory containing the file rather than trying to open the
  /// file itself a second time.
  @override
  Future<bool> openFolder(String path) async {
    if (path.isEmpty) return false;
    try {
      final dir = File(path).parent.path;
      return await launchUrl(Uri.file(dir));
    } catch (_) {
      return false;
    }
  }
}

// ── Module-level helpers ─────────────────────────────────────────────────────

/// Build the ffmpeg argument list for a segment cut.
/// Uses stream-copy (-c copy) so no re-encoding — fast and lossless.
/// -y overwrites without prompting; -loglevel error suppresses noise.
List<String> _buildFfmpegArgs({
  required String inputPath,
  required String outputPath,
  Duration? start,
  Duration? end,
}) {
  return [
    '-y',
    '-loglevel', 'error',
    if (start != null) ...[ '-ss', _durToFfmpeg(start) ],
    '-i', inputPath,
    // When -ss is before -i (input seeking), -to is relative to the seeked
    // position, not the original file. Use -t (duration) instead so that
    // start=1:00 end=2:00 produces a 1-minute clip, not a 2-minute one.
    if (end != null && start != null) ...[ '-t', _durToFfmpeg(end - start) ]
    else if (end != null) ...[ '-to', _durToFfmpeg(end) ],
    '-c', 'copy',
    outputPath,
  ];
}

/// Format a [Duration] as `HH:MM:SS.mmm` for ffmpeg -ss / -to arguments.
String _durToFfmpeg(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final ms = (d.inMilliseconds.remainder(1000)).toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// Replace filesystem-unsafe characters with underscores.
String _sanitizeFilename(String name) {
  return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
}

/// Format a Duration as a compact trim-range label, e.g. `01m30s`.
String _formatTrimRange(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '${h}h${m}m${s}s';
  return '${m}m${s}s';
}

/// Best-effort temp file deletion. Swallows errors — if the file is already
/// gone or locked we don't want to mask the real error.
///
/// Also removes the companion `.part` file that yt-dlp writes while a
/// download is in progress, in case `--no-part` wasn't in effect or yt-dlp
/// left a stale sidecar after an interrupted merge.
void _deleteTempFile(String? path) {
  if (path == null) return;
  for (final candidate in [path, '$path.part']) {
    try {
      final f = File(candidate);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// Delete every file that yt-dlp reported writing during a cancelled or failed
/// download.  This covers:
///   • The video-stream partial file (written before the audio stream starts,
///     looks like a valid MP4 but has no audio track).
///   • The audio-stream partial file.
///   • The merged output file (if the cancel arrived after merging began).
///   • Any companion `.part` sidecars for each of the above.
///
/// Swallows errors — if a file is already gone we don't want to mask the real
/// cancellation event.
void _deleteAllWrittenFiles(Set<String> paths) {
  for (final path in paths) {
    _deleteTempFile(path);
  }
}

/// After trimming, yt-dlp's `--write-subs` may have written sidecar files
/// like `_d4m_temp_xxx.en.srt` next to the temp video. Rename them to
/// match the final trimmed filename (e.g. `Title [01m00s-02m00s].en.srt`).
/// Swallows errors so a missing subtitle never blocks the download.
void _renameTempSubtitleFiles(
    String tempVideoPath, String outputDir, String finalBaseName) {
  try {
    final tempBase = p.basenameWithoutExtension(tempVideoPath);
    final dir = Directory(outputDir);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // Subtitle sidecars follow the pattern: <tempBase>.<lang>.<subExt>
      // e.g. _d4m_temp_1234.en.srt, _d4m_temp_1234.ar.vtt
      if (name.startsWith(tempBase) && name != p.basename(tempVideoPath)) {
        final suffix = name.substring(tempBase.length); // e.g. ".en.srt"
        final newPath = p.join(outputDir, '$finalBaseName$suffix');
        try {
          entity.renameSync(newPath);
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// Trim every subtitle sidecar that belongs to [finalBaseName] so only cues
/// within [start]..[end] survive, with timestamps shifted back by [start].
/// Supports SRT and VTT. Swallows all errors.
void _trimSubtitleFiles(
    String outputDir, String finalBaseName, Duration start, Duration? end) {
  try {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(finalBaseName)) continue;
      final ext = p.extension(name).toLowerCase();
      if (ext != '.srt' && ext != '.vtt') continue;
      try {
        final content = entity.readAsStringSync();
        final trimmed = ext == '.srt'
            ? _trimSrt(content, start, end)
            : _trimVtt(content, start, end);
        entity.writeAsStringSync(trimmed);
      } catch (_) {}
    }
  } catch (_) {}
}

/// Parse and trim an SRT subtitle string.
String _trimSrt(String content, Duration start, Duration? end) {
  final blocks = content.split(RegExp(r'\n\s*\n'));
  final buf = StringBuffer();
  int idx = 1;
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.length < 3) continue;
    // SRT timestamp line: 00:01:30,500 --> 00:01:35,000
    final match = RegExp(
      r'(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3})',
    ).firstMatch(lines[1]);
    if (match == null) continue;
    final cueStart = _parseSrtTs(match.group(1)!);
    final cueEnd = _parseSrtTs(match.group(2)!);
    if (cueStart == null || cueEnd == null) continue;
    // Skip cues entirely outside the trim window.
    if (cueEnd <= start) continue;
    if (end != null && cueStart >= end) continue;
    // Clamp and shift.
    final newStart = (cueStart < start ? Duration.zero : cueStart - start);
    final Duration newEnd;
    if (end != null && cueEnd > end) {
      newEnd = end - start;
    } else {
      newEnd = cueEnd - start;
    }
    final text = lines.sublist(2).join('\n');
    buf.writeln(idx);
    buf.writeln('${_toSrtTs(newStart)} --> ${_toSrtTs(newEnd)}');
    buf.writeln(text);
    buf.writeln();
    idx++;
  }
  return buf.toString();
}

/// Parse and trim a WebVTT subtitle string.
String _trimVtt(String content, Duration start, Duration? end) {
  final lines = content.split('\n');
  final buf = StringBuffer();
  buf.writeln('WEBVTT');
  buf.writeln();
  int i = 0;
  // Skip header lines.
  while (i < lines.length && !lines[i].contains('-->')) {
    i++;
  }
  while (i < lines.length) {
    final tsMatch = RegExp(
      r'(\d{2}:\d{2}:\d{2}\.\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}\.\d{3})',
    ).firstMatch(lines[i]);
    if (tsMatch == null) {
      i++;
      continue;
    }
    final cueStart = _parseVttTs(tsMatch.group(1)!);
    final cueEnd = _parseVttTs(tsMatch.group(2)!);
    i++;
    if (cueStart == null || cueEnd == null) continue;
    // Collect cue text.
    final textLines = <String>[];
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      textLines.add(lines[i]);
      i++;
    }
    // Skip blank separator lines.
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    if (cueEnd <= start) continue;
    if (end != null && cueStart >= end) continue;
    final newStart = (cueStart < start ? Duration.zero : cueStart - start);
    final Duration newEnd;
    if (end != null && cueEnd > end) {
      newEnd = end - start;
    } else {
      newEnd = cueEnd - start;
    }
    buf.writeln('${_toVttTs(newStart)} --> ${_toVttTs(newEnd)}');
    for (final l in textLines) {
      buf.writeln(l);
    }
    buf.writeln();
  }
  return buf.toString();
}

Duration? _parseSrtTs(String s) {
  // 00:01:30,500
  final m = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})').firstMatch(s);
  if (m == null) return null;
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: int.parse(m.group(4)!),
  );
}

Duration? _parseVttTs(String s) {
  // 00:01:30.500
  final m = RegExp(r'(\d{2}):(\d{2}):(\d{2})\.(\d{3})').firstMatch(s);
  if (m == null) return null;
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: int.parse(m.group(4)!),
  );
}

String _toSrtTs(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$h:$m:$s,$ms';
}

String _toVttTs(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}


/// Lives outside [YtDlpService.download] only because Dart doesn't let a
/// closure capture local variables by reference for assignment.
class _DownloadState {
  bool cancelled = false;
  bool paused    = false;
  String? outputPath;
  double? lastPercent;

  /// Every file path that yt-dlp has reported writing so far (Destination,
  /// Merger lines). Used to clean up all partial files on cancel/error,
  /// including the audio-less video stream that yt-dlp saves before the
  /// audio stream when downloading a merged format.
  final Set<String> writtenPaths = {};

  /// True once yt-dlp prints a [Merger] line, meaning the separate video
  /// and audio streams have both been downloaded and the merge has started.
  /// Used so that on cancel we know whether intermediate stream files are
  /// still present on disk.
  bool mergeStarted = false;

  /// Set by [YtDlpService.download] once the stdout subscription exists.
  Future<void> Function()? pauseCallback;
  Future<void> Function()? resumeCallback;
}

/// Handle returned from [YtDlpService.download]. Lets the controller listen
/// for progress events and ask the underlying process to terminate or pause.
class DownloadHandle {
  DownloadHandle._({
    required this.stream,
    required this.processFuture,
    required void Function() onCancel,
    required void Function() onPause,
    required void Function() onResume,
  })  : _onCancel = onCancel,
        _onPause  = onPause,
        _onResume = onResume;

  /// Wrap an externally-managed progress [Stream] into a handle the
  /// controllers can listen to. Used by non-process backends (e.g.
  /// [AndroidYtDlpBackend] talking to youtubedl-android through a
  /// platform channel) that emit [DownloadProgress] events through their
  /// own stream rather than by spawning a child process.
  ///
  /// [onCancel] / [onPause] / [onResume] are wired straight through to
  /// the backend so the UI's existing buttons work. The [processFuture]
  /// is a placeholder that always errors — callers should treat this
  /// handle as stream-only.
  factory DownloadHandle.streamed({
    required Stream<DownloadProgress> stream,
    required void Function() onCancel,
    void Function()? onPause,
    void Function()? onResume,
  }) {
    final processCompleter = Completer<Process>();
    // Never let the unfulfilled processFuture log as an unhandled error.
    processCompleter.future.catchError((_) => Process.start('true', const []));
    scheduleMicrotask(() {
      if (!processCompleter.isCompleted) {
        processCompleter.completeError(
          UnsupportedError(
            'This DownloadHandle has no host Process — the underlying '
            'backend exposes progress only through a stream.',
          ),
        );
      }
    });
    return DownloadHandle._(
      stream: stream,
      processFuture: processCompleter.future,
      onCancel: onCancel,
      onPause: onPause ?? () {},
      onResume: onResume ?? () {},
    );
  }

  /// Synthesise a handle that emits a single error event and then closes.
  /// Used by stub backends (e.g. [AndroidBackendStub]) that can't actually
  /// kick off a download but still need to drive the UI's existing
  /// error-card path. The returned handle's [pause] / [resume] / [cancel]
  /// methods are no-ops because there is no underlying process.
  factory DownloadHandle.failed(String errorMessage) {
    final controller = StreamController<DownloadProgress>.broadcast();
    final processCompleter = Completer<Process>();
    // Emit on the next microtask so listeners attached straight after
    // construction don't miss the event.
    scheduleMicrotask(() async {
      controller.add(
        DownloadProgress(
          phase: DownloadPhase.error,
          errorMessage: errorMessage,
        ),
      );
      await controller.close();
      processCompleter.completeError(UnsupportedError(errorMessage));
    });
    return DownloadHandle._(
      stream: controller.stream,
      processFuture: processCompleter.future,
      onCancel: () {},
      onPause: () {},
      onResume: () {},
    );
  }

  final Stream<DownloadProgress> stream;
  final Future<Process> processFuture;

  final void Function() _onCancel;
  final void Function() _onPause;
  final void Function() _onResume;
  bool _cancelled = false;
  bool _paused    = false;

  bool get isCancelled => _cancelled;
  bool get isPaused    => _paused;

  /// Suspend the yt-dlp process at the OS level so it genuinely stops
  /// downloading. Sends SIGSTOP on POSIX, suspends all threads on Windows.
  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _onPause();
  }

  /// Resume the suspended yt-dlp process.
  void resume() {
    if (_cancelled || !_paused) return;
    _paused = false;
    _onResume();
  }

  /// Send SIGTERM to terminate the yt-dlp process.
  /// If the process is suspended (SIGSTOP / NtSuspendProcess), we must
  /// resume it first — a stopped process cannot be killed with SIGTERM on
  /// POSIX (it stays stopped until continued). We resume then kill.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    if (_paused) {
      _paused = false;
      // Resume the process before killing so it can handle the signal.
      // We call the raw _resumeProcess directly (bypassing the stream
      // subscription resume) because we are about to tear it down anyway.
      try {
        final p = await processFuture;
        if (!Platform.isWindows) {
          Process.killPid(p.pid, ProcessSignal.sigcont);
        }
      } catch (_) {}
    }
    _onCancel();
    try {
      final p = await processFuture;
      p.kill(ProcessSignal.sigterm);
    } catch (_) {
      // Process never started; nothing to kill.
    }
  }
}

/// Suspend a process at the OS level so it genuinely stops consuming network.
/// On POSIX sends SIGSTOP; on Windows P/Invokes NtSuspendProcess via PowerShell.
///
/// Failures are logged with [debugPrint] (no-op in release builds) and the
/// function returns `false` so callers can decide whether to surface the
/// failure to the user. The yt-dlp process stays running on failure.
Future<bool> _suspendProcess(int pid) async {
  try {
    if (Platform.isWindows) {
      final script = _windowsSuspendScript(pid, suspend: true);
      final result = await Process.run(
          'powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
      if (result.exitCode != 0) {
        debugPrint(
            'ytdlp_service: NtSuspendProcess($pid) failed: ${result.stderr}');
      }
      return result.exitCode == 0;
    } else {
      final ok = Process.killPid(pid, ProcessSignal.sigstop);
      if (!ok) {
        debugPrint('ytdlp_service: SIGSTOP to pid=$pid returned false');
      }
      return ok;
    }
  } catch (e) {
    debugPrint('ytdlp_service: _suspendProcess($pid) threw: $e');
    return false;
  }
}

/// Resume a process suspended with [_suspendProcess].
Future<bool> _resumeProcess(int pid) async {
  try {
    if (Platform.isWindows) {
      final script = _windowsSuspendScript(pid, suspend: false);
      final result = await Process.run(
          'powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
      if (result.exitCode != 0) {
        debugPrint(
            'ytdlp_service: NtResumeProcess($pid) failed: ${result.stderr}');
      }
      return result.exitCode == 0;
    } else {
      final ok = Process.killPid(pid, ProcessSignal.sigcont);
      if (!ok) {
        debugPrint('ytdlp_service: SIGCONT to pid=$pid returned false');
      }
      return ok;
    }
  } catch (e) {
    debugPrint('ytdlp_service: _resumeProcess($pid) threw: $e');
    return false;
  }
}

/// PowerShell snippet that P/Invokes [NtSuspendProcess] / [NtResumeProcess]
/// from ntdll.dll. [pid] is interpolated directly — it's an int so there is
/// no quoting risk. Errors propagate as a non-zero exit code so the caller
/// can log the stderr.
String _windowsSuspendScript(int pid, {required bool suspend}) {
  final fn = suspend ? 'NtSuspendProcess' : 'NtResumeProcess';
  final type = suspend ? 'NT' : 'NTR';
  return '\$ErrorActionPreference="Stop"\n'
      '\$sig=@"\n'
      '[DllImport("ntdll.dll")] public static extern int $fn(IntPtr h);\n'
      '"@\n'
      '\$t=Add-Type -MemberDefinition \$sig -Name $type -Namespace W -PassThru;\n'
      '\$h=(Get-Process -Id $pid).Handle;\n'
      '\$t::$fn(\$h)';
}

/// Thrown by [YtDlpService.fetchMetadata] for any failure (process missing,
/// non-zero exit, JSON parse failure). Message is safe to show to the user.
class YtDlpException implements Exception {
  YtDlpException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parse a single line of yt-dlp `--newline` stdout. Returns null if the line
/// isn't a recognised progress / status update.
///
/// Lines we handle:
/// - `[download]   1.5% of  100.00MiB at  2.50MiB/s ETA 00:39`
/// - `[download] 100% of   23.86MiB in 00:08 at 2.84MiB/s`
/// - `[download] Destination: /path/to/file.mp4`
/// - `[Merger] Merging formats into "/path/to/file.mp4"`
/// - `[ExtractAudio] Destination: /path/to/file.m4a`
///
/// Public so cross-platform backends (e.g. [AndroidYtDlpBackend]) can share
/// the same parser — yt-dlp's progress lines are identical on every host.
DownloadProgress? parseProgressLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  // "Destination" lines tell us the final filename.
  final dest = RegExp(r'^\[(?:download|ExtractAudio)\]\s+Destination:\s+(.+)$')
      .firstMatch(trimmed);
  if (dest != null) {
    return DownloadProgress(
      phase: DownloadPhase.downloading,
      outputPath: dest.group(1)!.trim(),
      message: 'Saving to ${dest.group(1)!.trim()}',
    );
  }

  final merger = RegExp(r'^\[Merger\]\s+Merging formats into\s+"(.+)"$')
      .firstMatch(trimmed);
  if (merger != null) {
    return DownloadProgress(
      phase: DownloadPhase.downloading,
      percent: 100,
      outputPath: merger.group(1)!,
      message: 'Merging audio + video…',
    );
  }

  // Progress line. Be liberal in what we accept since yt-dlp's spacing varies.
  final progress = RegExp(
    r'^\[download\]\s+'
    r'(\d+(?:\.\d+)?)%'
    r'\s+of\s+~?\s*([\d.]+)\s*([KMGTP]?i?B)'
    r'(?:\s+at\s+([\d.]+|Unknown)\s*([KMGTP]?i?B/s)?)?'
    r'(?:\s+ETA\s+(\S+))?',
  ).firstMatch(trimmed);
  if (progress != null) {
    final percent = double.tryParse(progress.group(1)!);
    final totalAmount = double.tryParse(progress.group(2)!);
    final totalUnit = progress.group(3);
    final speedAmount = double.tryParse(progress.group(4) ?? '');
    final speedUnit = progress.group(5);
    final etaStr = progress.group(6);
    return DownloadProgress(
      phase: DownloadPhase.downloading,
      percent: percent,
      totalBytes: totalAmount != null && totalUnit != null
          ? _bytesFromSize(totalAmount, totalUnit)
          : null,
      speedBytesPerSecond: speedAmount != null && speedUnit != null
          ? _bytesFromSize(speedAmount, speedUnit.replaceAll('/s', ''))
              .toDouble()
          : null,
      eta: etaStr != null ? _parseEta(etaStr) : null,
    );
  }

  return null;
}

int _bytesFromSize(double amount, String unit) {
  // Both binary (KiB / MiB / ...) and decimal (KB / MB / ...) forms appear in
  // yt-dlp output depending on version / postprocessor. Treat them the same
  // way — close enough for a progress UI.
  const multipliers = <String, int>{
    'B': 1,
    'KB': 1024,
    'MB': 1024 * 1024,
    'GB': 1024 * 1024 * 1024,
    'TB': 1024 * 1024 * 1024 * 1024,
    'KiB': 1024,
    'MiB': 1024 * 1024,
    'GiB': 1024 * 1024 * 1024,
    'TiB': 1024 * 1024 * 1024 * 1024,
  };
  return (amount * (multipliers[unit] ?? 1)).round();
}

Duration? _parseEta(String s) {
  final parts = s.split(':');
  try {
    if (parts.length == 2) {
      return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
    } else if (parts.length == 3) {
      return Duration(
        hours: int.parse(parts[0]),
        minutes: int.parse(parts[1]),
        seconds: int.parse(parts[2]),
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}

Future<ProcessResult> _defaultRunner(String exe, List<String> args) =>
    Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8);

Future<Process> _defaultSpawner(String exe, List<String> args) =>
    Process.start(exe, args, runInShell: false);
