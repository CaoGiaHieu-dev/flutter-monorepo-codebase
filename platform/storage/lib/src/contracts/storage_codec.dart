import 'dart:convert';

import 'package:core_common/core_common.dart';

/// The one JSON encoding every storage path shares — [StorageValue]'s RAM
/// cache and both backends — so a value always reads back the way it was
/// written.
class StorageCodec {
  StorageCodec._();

  /// Encodes [value] as JSON. Enums store their `name`; any other object
  /// stores whatever its `toJson()` returns — as JSON, not as a string of
  /// JSON (which a reviver would then receive still encoded).
  static String encode(Object value) =>
      jsonEncode(value, toEncodable: _toEncodable);

  static Object? _toEncodable(Object? value) {
    if (value is Enum) return value.name;
    return (value as dynamic).toJson();
  }

  /// Decodes [json] into `T`.
  ///
  /// A [reviver], when given, is called **once** with the decoded root —
  /// not for every node of the tree, as `jsonDecode(reviver:)` would.
  /// Without one, a typed list (`List<String>`, …) is cast element-wise:
  /// the decoder produces `List<dynamic>`, which `as List<String>` rejects.
  static T? decode<T>(
    String json,
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) => revive<T>(jsonDecode(json), key, reviver: reviver);

  /// [decode] for an already-decoded value.
  static T? revive<T>(
    Object? decoded,
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) {
    if (decoded == null) return null;
    if (reviver != null) return reviver(key, decoded);
    if (decoded is List) return _castList<T>(decoded);
    return decoded as T;
  }

  static T _castList<T>(List<dynamic> list) {
    final t = TypeHelper<T>();
    if (t is TypeHelper<List<String>>) return list.cast<String>() as T;
    if (t is TypeHelper<List<int>>) return list.cast<int>() as T;
    if (t is TypeHelper<List<double>>) {
      return list.map((e) => (e as num).toDouble()).toList() as T;
    }
    if (t is TypeHelper<List<num>>) return list.cast<num>() as T;
    if (t is TypeHelper<List<bool>>) return list.cast<bool>() as T;
    if (t is TypeHelper<List<Map<String, dynamic>>>) {
      return list.cast<Map<String, dynamic>>() as T;
    }
    return list as T;
  }
}
