/// Time, as a boundary interface: tests use a fake that never waits.
abstract interface class Clock {
  DateTime now();

  /// Waits for [duration].
  Future<void> sleep(Duration duration);
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}
