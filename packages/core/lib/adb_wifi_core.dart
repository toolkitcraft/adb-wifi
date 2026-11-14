/// Core logic for adbwifi, shared by the CLI and (later) the GUI.
///
/// Rules for this package:
/// - Pure Dart: no Flutter imports, no printing to the terminal.
/// - Every process and network call has a timeout.
/// - Talk to the outside world (adb, sockets, files, clock) only through
///   small interfaces, so tests can use fakes.
library;
