/// Key-value storage for the analytics visitor id and the unsent request
/// queue.
///
/// The SDK ships only [InMemoryAnalyticsStorage], so it adds no plugin
/// dependency. For a visitor id that survives restarts and an offline queue,
/// back it with `shared_preferences` (or any store) in your app:
///
/// ```dart
/// class PrefsAnalyticsStorage implements ChorkiAnalyticsStorage {
///   PrefsAnalyticsStorage(this.prefs);
///   final SharedPreferences prefs;
///   @override
///   Future<String?> read(String key) async => prefs.getString(key);
///   @override
///   Future<void> write(String key, String? value) async => value == null
///       ? prefs.remove(key)
///       : prefs.setString(key, value);
/// }
/// ```
abstract class ChorkiAnalyticsStorage {
  Future<String?> read(String key);

  /// Null removes [key].
  Future<void> write(String key, String? value);
}

/// Lost when the app exits: a new visitor id per launch and no offline queue
/// across restarts.
class InMemoryAnalyticsStorage implements ChorkiAnalyticsStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
