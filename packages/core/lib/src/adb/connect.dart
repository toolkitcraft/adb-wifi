import '../network/ipv4.dart';
import '../process/process_runner.dart';
import 'adb.dart';

/// What `adb connect` said.
sealed class ConnectResult {
  const ConnectResult();
}

/// `connected to …` or `already connected to …`.
final class Connected extends ConnectResult {
  const Connected({this.already = false});

  final bool already;
}

/// The device answered but nothing listens on the port.
final class ConnectRefused extends ConnectResult {
  const ConnectRefused();
}

/// The device refused our adb key (`failed to authenticate`): it waits for
/// someone to tap Allow on its screen.
final class ConnectUnauthorized extends ConnectResult {
  const ConnectUnauthorized();
}

/// adb did not answer within the time limit and was killed.
final class ConnectTimedOut extends ConnectResult {
  const ConnectTimedOut(this.after);

  final Duration after;
}

/// adb said it failed, for another reason (no route, timed out, ...).
final class ConnectFailed extends ConnectResult {
  const ConnectFailed(this.message);

  /// adb's own words, for the user.
  final String message;
}

/// Runs `adb connect ip:port` with the adb time limit.
Future<ConnectResult> adbConnect(Adb adb, NetworkAddress address) async {
  final outcome = await adb.run(['connect', address.serial]);
  return switch (outcome) {
    ProcessCompleted() => parseConnect(outcome.allLines),
    ProcessTimedOut(:final after) => ConnectTimedOut(after),
    ProcessFailedToStart(:final message) => ConnectFailed(message),
  };
}

/// Reads the output of `adb connect`. adb exits with 0 even when it fails,
/// so only the text tells what happened.
ConnectResult parseConnect(Iterable<String> lines) {
  final text = [
    for (final line in lines)
      if (line.trim().isNotEmpty && !line.startsWith('* ')) line.trim(),
  ];
  bool any(String word) =>
      text.any((l) => l.toLowerCase().contains(word.toLowerCase()));

  if (text.any((l) => l.startsWith('already connected to '))) {
    return const Connected(already: true);
  }
  if (text.any((l) => l.startsWith('connected to '))) return const Connected();
  if (any('failed to authenticate')) return const ConnectUnauthorized();
  if (any('connection refused')) return const ConnectRefused();
  return ConnectFailed(
    text.isEmpty ? 'adb connect printed nothing' : text.join(' '),
  );
}
