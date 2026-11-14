import 'dart:io';

/// Prints Windows line endings, bad UTF-8 and a stderr line, then exits 3.
void main() {
  stdout.add('first\r\nsecond  \r\n'.codeUnits);
  stdout.add([0x62, 0x61, 0x64, 0xFF, 0x0A]); // "bad" + invalid byte
  stderr.writeln('warning');
  exitCode = 3;
}
