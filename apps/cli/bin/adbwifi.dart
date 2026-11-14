import 'dart:io';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments, out: stdout, err: stderr);
}
