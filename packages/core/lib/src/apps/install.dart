import '../adb/text.dart';
import '../process/process_runner.dart';

/// The result of `adb install -r`.
sealed class InstallResult {
  const InstallResult();
}

final class InstallSuccess extends InstallResult {
  const InstallSuccess();
}

/// Android refused the APK, with its reason code.
final class InstallFailure extends InstallResult {
  const InstallFailure(this.code, {this.detail});

  /// For example `INSTALL_FAILED_VERSION_DOWNGRADE`.
  final String code;

  /// Android's own words after the code, if any.
  final String? detail;
}

final class InstallTimedOut extends InstallResult {
  const InstallTimedOut(this.after);

  final Duration after;
}

/// Output adbwifi does not know. Shown as it is, never guessed at.
final class InstallUnknown extends InstallResult {
  const InstallUnknown(this.lines);

  final List<String> lines;
}

/// Reads what `adb install` printed. adb's exit code is not reliable on
/// old versions, so the text decides: `Success`, or
/// `Failure [INSTALL_FAILED_X: detail]`.
InstallResult parseInstall(ProcessOutcome outcome) {
  switch (outcome) {
    case ProcessTimedOut(:final after):
      return InstallTimedOut(after);
    case ProcessFailedToStart(:final message):
      return InstallUnknown([message]);
    case ProcessCompleted():
      final lines = [
        for (final l in outcome.allLines)
          if (l.trim().isNotEmpty) cleanDeviceText(l, maxLength: 500),
      ];
      for (final line in lines) {
        final m = _failure.firstMatch(line);
        if (m != null) {
          final detail = m.group(2)?.trim();
          return InstallFailure(
            m.group(1) ?? 'UNKNOWN',
            detail: (detail == null || detail.isEmpty) ? null : detail,
          );
        }
      }
      if (lines.any((l) => l.trim() == 'Success')) {
        return const InstallSuccess();
      }
      return InstallUnknown(lines);
  }
}

final _failure = RegExp(r'Failure \[([A-Z0-9_]+)(?::\s*([^\]]*))?\]');

/// How long an install may take: a minute, plus time for the file at a
/// slow 200 KB/s (Wi-Fi was about 1.8 MB/s), at most 30 minutes.
Duration transferTimeout(int bytes, {Duration atLeast = Duration.zero}) {
  final seconds = 60 + bytes ~/ (200 * 1024);
  final limit = Duration(seconds: seconds.clamp(60, 30 * 60));
  return limit > atLeast ? limit : atLeast;
}
