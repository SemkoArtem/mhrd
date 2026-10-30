// Дрібні помічники для ручної (без кодогенерації) серіалізації моделей.

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

List<String> stringList(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];

DateTime? dateOrNull(Object? v) => v is String ? DateTime.tryParse(v) : null;

int intOr(Object? v, int fallback) => v is int ? v : (v is num ? v.toInt() : fallback);

bool boolOr(Object? v, bool fallback) => v is bool ? v : fallback;

String strOr(Object? v, String fallback) => v is String ? v : fallback;

Map<String, dynamic> mapOr(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

String? strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
