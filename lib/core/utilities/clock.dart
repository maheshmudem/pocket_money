/// Deterministic UTC clock abstraction.
/// All persisted timestamps in Pocket CFO must be UTC (`README.md`, `DATA-001`).
abstract interface class UtcClock {
  DateTime nowUtc();
  String nowIsoUtc() => nowUtc().toUtc().toIso8601String();
}

final class SystemUtcClock implements UtcClock {
  const SystemUtcClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  String nowIsoUtc() => nowUtc().toIso8601String();
}

final class FixedUtcClock implements UtcClock {
  FixedUtcClock(DateTime initialUtc) : _current = initialUtc.toUtc();

  DateTime _current;

  void advance(Duration duration) {
    _current = _current.add(duration);
  }

  void set(DateTime utc) {
    _current = utc.toUtc();
  }

  @override
  DateTime nowUtc() => _current;

  @override
  String nowIsoUtc() => _current.toIso8601String();
}
