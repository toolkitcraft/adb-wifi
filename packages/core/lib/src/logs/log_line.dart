/// logcat priorities, lowest first.
enum LogLevel {
  verbose('V'),
  debug('D'),
  info('I'),
  warning('W'),
  error('E'),
  fatal('F');

  const LogLevel(this.letter);

  final String letter;

  /// `V D I W E F`, or `A` (assert, shown as fatal). Null for others.
  static LogLevel? fromLetter(String letter) => switch (letter.toUpperCase()) {
    'V' => verbose,
    'D' => debug,
    'I' => info,
    'W' => warning,
    'E' => error,
    'F' || 'A' => fatal,
    _ => null,
  };
}

/// One line of `logcat -v threadtime`:
/// `11-14 10:22:33.123  1234  1250 I Tag     : message`.
final class LogLine {
  const LogLine({
    required this.raw,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    required this.time,
  });

  /// The whole line as logcat printed it.
  final String raw;
  final int pid;
  final int tid;
  final LogLevel level;
  final String tag;
  final String message;

  /// `MM-DD HH:MM:SS.mmm` as printed (logcat has no year).
  final String time;

  Map<String, Object?> toJson() => {
    'time': time,
    'pid': pid,
    'tid': tid,
    'level': level.letter,
    'tag': tag,
    'message': message,
  };
}

/// Reads one threadtime line. Null for anything else, such as
/// `--------- beginning of main`.
LogLine? parseLogLine(String raw) {
  final m = _threadtime.firstMatch(raw);
  if (m == null) return null;
  final level = LogLevel.fromLetter(m.group(5) ?? '');
  final pid = int.tryParse(m.group(3) ?? '');
  final tid = int.tryParse(m.group(4) ?? '');
  if (level == null || pid == null || tid == null) return null;
  return LogLine(
    raw: raw,
    time: '${m.group(1)} ${m.group(2)}',
    pid: pid,
    tid: tid,
    level: level,
    tag: (m.group(6) ?? '').trim(),
    message: m.group(7) ?? '',
  );
}

final _threadtime = RegExp(
  r'^(\d\d-\d\d)\s+(\d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEFA])\s+'
  r'(.*?)\s*:(?: (.*))?$',
);

/// Hides secrets before a log is saved to a file: `Bearer …`,
/// `token=…`, `key=…`, `password=…` (and JSON `"password": "…"`) become
/// `***`. It hides too much rather than too little.
String redactSecrets(String line) => line
    .replaceAllMapped(_bearer, (m) => '${m.group(1)} ***')
    .replaceAllMapped(_assignment, (m) => '${m.group(1)}${m.group(2)}***')
    .replaceAllMapped(_jsonField, (m) => '${m.group(1)}***"');

final _bearer = RegExp(
  r'\b(Bearer)\s+[A-Za-z0-9\-._~+/]+=*',
  caseSensitive: false,
);

final _assignment = RegExp(
  r'\b(\w*(?:token|key|password|passwd|pwd|secret))(\s*[=:]\s*)'
  r'''(?!\*\*\*)[^\s&"',;]+''',
  caseSensitive: false,
);

final _jsonField = RegExp(
  r'("\w*(?:token|key|password|passwd|secret)"\s*:\s*")[^"]*"',
  caseSensitive: false,
);
