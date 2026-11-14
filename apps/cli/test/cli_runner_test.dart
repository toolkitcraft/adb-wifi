import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  Future<int> run(List<String> args) => runCli(args, out: out, err: err);

  test('version prints the tool version', () async {
    expect(await run(['version']), ExitCodes.ok);
    expect(out.toString(), 'adbwifi $toolVersion\n');
    expect(err.toString(), isEmpty);
  });

  test('no arguments prints help that lists the commands', () async {
    expect(await run([]), ExitCodes.ok);
    expect(out.toString(), contains('Usage: adbwifi <command>'));
    expect(out.toString(), contains('version'));
  });

  test('an unknown command is a usage error on stderr', () async {
    expect(await run(['nope']), ExitCodes.usage);
    expect(out.toString(), isEmpty);
    expect(err.toString(), contains('Could not find a command named "nope"'));
  });
}
