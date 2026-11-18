import '../errors/chorki_player_error.dart';

/// A value or a [ChorkiPlayerError]. Replaces `dartz`'s `Either`.
sealed class Result<T> {
  const Result();

  /// Returns [onError] or [onValue] applied to the content.
  R fold<R>(
    R Function(ChorkiPlayerError error) onError,
    R Function(T value) onValue,
  ) => switch (this) {
    Ok<T>(:final value) => onValue(value),
    Err<T>(:final error) => onError(error),
  };
}

/// A successful [Result].
final class Ok<T> extends Result<T> {
  /// Wraps [value].
  const Ok(this.value);

  /// The value.
  final T value;
}

/// A failed [Result].
final class Err<T> extends Result<T> {
  /// Wraps [error].
  const Err(this.error);

  /// The error.
  final ChorkiPlayerError error;
}
