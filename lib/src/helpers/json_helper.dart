class JsonHelper {
  JsonHelper({required dynamic json})
    : json = json is Map<String, dynamic>
          ? json
          : json is Map
          ? Map<String, dynamic>.from(json)
          : <String, dynamic>{};

  final Map<String, dynamic> json;

  String getJsonString(String key) {
    final value = json[key];
    if (value == null) return '';
    return value.toString();
  }

  bool getJsonBool(String key) =>
      bool.tryParse(json[key]?.toString() ?? '') ?? false;

  int getJsonInt(String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double getJsonDouble(String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  List<Map<String, dynamic>> getJsonList(String key) {
    final value = json[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> fromStringList(String key) {
    final value = json[key];
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  Map<String, dynamic> getJsonMap(String key) {
    final value = json[key];
    if (value is! Map) return const {};
    return Map<String, dynamic>.from(value);
  }
}
