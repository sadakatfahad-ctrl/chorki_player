/// Returns the current time. Inject one wherever time is read so tests can
/// control it.
typedef ChorkiClock = DateTime Function();

/// The wall clock. The only place in the package that reads it.
DateTime systemClock() => DateTime.now();
