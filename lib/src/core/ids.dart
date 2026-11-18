import 'dart:math';

/// Creates an id. Inject one wherever ids are made so tests are
/// deterministic.
typedef ChorkiIdGenerator = String Function();

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

final Random _random = Random();
final Random _secure = Random.secure();

/// A random alphanumeric id of [length] characters (not cryptographic).
String randomId([int length = 12]) => String.fromCharCodes(
  List.generate(
    length,
    (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ),
);

/// [bytes] random bytes from a cryptographically secure source, as
/// lowercase hex (e.g. a Matomo visitor id is 8 bytes / 16 hex characters).
String secureHex(int bytes) => [
  for (var i = 0; i < bytes; i++)
    _secure.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

/// A random non-negative integer below [max] (cache busters and the like).
int randomInt(int max) => _random.nextInt(max);
