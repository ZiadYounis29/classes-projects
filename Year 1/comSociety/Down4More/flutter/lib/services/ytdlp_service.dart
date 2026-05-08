import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/download_progress.dart';
import '../models/video_metadata.dart';

/// Thin wrapper around the `yt-dlp` CLI. Pure Dart, no UI deps — safe to
/// unit-test by injecting a [_ProcessRunner] / [_ProcessSpawner].
///
/// Right now we shell out to whichever `yt-dlp` is on `PATH`. PR 8 will switch
/// this to a bundled binary that ships inside the app, so the user doesn't
/// need yt-dlp pre-installed.
class YtDlpService {
  YtDlpService({
    String executable = 'yt-dlp',
    Future<ProcessResult> Function(String, List<String>)? processRunner,
    Future<Process> Function(String, List<String>)? processSpawner,
  })  : _exe = executable,
        _runner = processRunner ?? _defaultRunner,
        _spawner = processSpawner ?? _defaultSpawner;

  final String _exe;
  final Future<ProcessResult> Function(String, List<String>) _runner;
  final Future<Process> Function(String, List<String>) _spawner;

  /// Run `yt-dlp --dump-single-json` to fetch metadata for a single URL.
  ///
  /// Throws [YtDlpException] if the process exits non-zero. The thrown
  /// message is yt-dlp's own stderr — that's more useful to surface than a
  /// paraphrase, e.g. "Sign in to confirm you're not a bot" or "Video
  /// unavailable in your country".
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

    final ProcessResult result;
    try {
      result = await _runner(_exe, fullArgs);
    } on ProcessException catch (e) {
      throw YtDlpException(
        'yt-dlp not found at "$_exe". Install it with `pip install yt-dlp` '
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

  /// Start an actual download. Returns a [DownloadHandle] you can listen to
  /// for [DownloadProgress] events and call [DownloadHandle.cancel] on.
  ///
  /// The returned stream completes (closes) once yt-dlp exits, regardless of
  /// success/failure/cancel. Listen for the terminal phase event and update
  /// UI state accordingly.
  DownloadHandle download({
    required VideoMetadata metadata,
    required VideoFormat format,
    required String outputDir,
    String outputTemplate = '%(title).200B [%(id)s].%(ext)s',
  }) {
    final controller = StreamController<DownloadProgress>.broadcast();
    final processCompleter = Completer<Process>();
    final state = _DownloadState();

    final args = <String>[
      '--newline',
      '--no-playlist',
      '--no-warnings',
      '-f', format.id,
      // Always remux problematic codecs into mp4 so the output file actually
      // plays in OS-default players (Linux Files / macOS Finder Quick Look).
      // Audio-only stays as m4a.
      if (!format.isAudioOnly) ...['--merge-output-format', 'mp4'],
      '-o', '$outputDir/$outputTemplate',
      metadata.url,
    ];

    Future<void> run() async {
      Process process;
      try {
        process = await _spawner(_exe, args);
      } on ProcessException catch (e) {
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.error,
            errorMessage: 'yt-dlp not found at "$_exe": ${e.message}',
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
        }
        controller.add(progress);
      });

      final stderrBuf = StringBuffer();
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen(stderrBuf.write);

      final code = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      if (code == 0) {
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.finished,
            percent: 100,
            outputPath: state.outputPath,
            message: 'Saved.',
          ),
        );
      } else if (state.cancelled) {
        controller.add(const DownloadProgress(phase: DownloadPhase.cancelled));
      } else {
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.error,
            errorMessage: stderrBuf.toString().trim().isEmpty
                ? 'yt-dlp exited with code $code.'
                : stderrBuf.toString().trim(),
          ),
        );
      }
      await controller.close();
    }

    run();

    return DownloadHandle._(
      stream: controller.stream,
      processFuture: processCompleter.future,
      onCancel: () => state.cancelled = true,
    );
  }
}

/// Mutable state shared between the spawn closure and the cancel callback.
/// Lives outside [YtDlpService.download] only because Dart doesn't let a
/// closure capture local variables by reference for assignment.
class _DownloadState {
  bool cancelled = false;
  String? outputPath;
}

/// Handle returned from [YtDlpService.download]. Lets the controller listen
/// for progress events and ask the underlying process to terminate.
class DownloadHandle {
  DownloadHandle._({
    required this.stream,
    required this.processFuture,
    required void Function() onCancel,
  }) : _onCancel = onCancel;

  /// One [DownloadProgress] per stdout line + one terminal phase event
  /// (finished / error / cancelled). Closes when the subprocess exits.
  final Stream<DownloadProgress> stream;

  /// Completes once the underlying [Process] is actually started. If yt-dlp
  /// is missing on PATH, completes with an error instead.
  final Future<Process> processFuture;

  final void Function() _onCancel;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Send SIGTERM (or kill on Windows) to the running yt-dlp process. The
  /// stream will then emit a [DownloadPhase.cancelled] event and close.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
    try {
      final p = await processFuture;
      p.kill(ProcessSignal.sigterm);
    } catch (_) {
      // Process never started; nothing to kill.
    }
  }
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
@visibleForTesting
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
