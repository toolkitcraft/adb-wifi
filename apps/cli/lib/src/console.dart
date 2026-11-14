import 'dart:convert';

/// Writes the CLI's output: symbols for people, or JSON for scripts.
///
/// Symbols: ✅ good, ⚠️ warning, ❌ failure, 👉 what to do.
final class Console {
  Console(this.out, this.err, {this.json = false, this.colors = false});

  final StringSink out;
  final StringSink err;

  /// True when the terminal shows ANSI colors.
  final bool colors;

  /// True with `--json`: commands print one JSON document and no text.
  final bool json;

  void line([String text = '']) => out.writeln(text);
  void ok(String text) => out.writeln('✅ $text');
  void warn(String text) => out.writeln('⚠️  $text');
  void fail(String text) => out.writeln('❌ $text');
  void fix(String text) => out.writeln('👉 ${_indent(text)}');
  void info(String text) => out.writeln('   ${_indent(text)}');

  /// A warning that must not be missed (root adb on the network): red
  /// when the terminal has colors.
  void danger(String text) =>
      out.writeln(colors ? '\x1B[1;31m🚨 $text\x1B[0m' : '🚨 $text');

  /// Asks a question on stdout (the answer is read by the caller).
  void ask(String question) => out.write(question);

  /// Prints [value] as indented JSON.
  void printJson(Object? value) =>
      out.writeln(const JsonEncoder.withIndent('  ').convert(value));

  /// Lines after the first line up under the text, not the symbol.
  static String _indent(String text) => text.replaceAll('\n', '\n   ');
}

/// Stops a command with a message, a fix and an exit code. The runner
/// prints it as text or JSON.
final class CliFailure implements Exception {
  const CliFailure(this.message, {this.fix, this.exitCode = 1});

  final String message;
  final String? fix;
  final int exitCode;

  Map<String, Object?> toJson() => {
    'ok': false,
    'error': message,
    if (fix != null) 'fix': fix,
  };

  @override
  String toString() => message;
}
