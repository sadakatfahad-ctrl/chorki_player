/// Lenient reads from a decoded JSON object: a missing or mistyped value
/// gives a default instead of throwing.
class JsonHelper {
  /// Wraps [json]; anything but a map reads as empty.
  JsonHelper({required Object? json})
    : json = json is Map<String, dynamic>
          ? json
          : json is Map
          ? Map<String, dynamic>.from(json)
          : <String, dynamic>{};

  /// The object read from.
  final Map<String, dynamic> json;

  /// The value at [key] as a string; `''` when missing.
  String getJsonString(String key) {
    final value = json[key];
    if (value == null) return '';
    return value.toString();
  }

  /// The value at [key] as an int (from an int, a number or a numeric
  /// string); 0 otherwise.
  int getJsonInt(String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
