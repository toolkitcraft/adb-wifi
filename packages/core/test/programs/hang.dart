import 'dart:io';

/// Prints one line, then hangs like `adb connect` sometimes does.
Future<void> main() async {
  stdout.writeln('started');
  await stdout.flush();
  await Future<void>.delayed(const Duration(minutes: 5));
}
