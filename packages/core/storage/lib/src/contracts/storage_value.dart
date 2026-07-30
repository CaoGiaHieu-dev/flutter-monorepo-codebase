import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:core_common/core_common.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';

import 'storage_interface.dart';

/// Container that obfuscates a String in RAM using dynamic XOR masking.
class ObfuscatedString {
  final Uint8List _maskedBytes;
  final Uint8List _mask;

  ObfuscatedString(String value) : this._(utf8.encode(value));

  /// Sizes buffers from UTF-8 byte length, not Dart [String.length],
  /// so multi-byte characters (e.g. Vietnamese) are not truncated.
  ObfuscatedString._(List<int> originalBytes)
    : _mask = _generateRandomMask(originalBytes.length),
      _maskedBytes = Uint8List(originalBytes.length) {
    for (int i = 0; i < originalBytes.length; i++) {
      _maskedBytes[i] = originalBytes[i] ^ _mask[i];
    }
  }

  /// Temporarily reconstructs the original string.
  /// Caller should discard the returned string quickly.
  String reveal() {
    final originalBytes = Uint8List(_maskedBytes.length);
    for (int i = 0; i < _maskedBytes.length; i++) {
      originalBytes[i] = _maskedBytes[i] ^ _mask[i];
    }
    final revealed = utf8.decode(originalBytes);
    originalBytes.fillRange(0, originalBytes.length, 0);
    return revealed;
  }

  /// Disposes of the obfuscated buffers.
  void dispose() {
    _maskedBytes.fillRange(0, _maskedBytes.length, 0);
    _mask.fillRange(0, _mask.length, 0);
  }

  static Uint8List _generateRandomMask(int length) {
    final random = math.Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// A reactive wrapper around a single key-value pair in [StorageInterface].
///
/// Provides:
/// - In-memory cache with [value] getter/setter (obfuscated in RAM)
/// - Automatic persistence via [StorageInterface.write] on every set
/// - [ChangeNotifier] integration for Provider/Riverpod listeners
/// - [Stream] broadcasting via [listen] for reactive pipelines
///
/// Example:
/// ```dart
/// final token = StorageValue<String>(storage, 'auth_token');
/// token.value = 'abc123';        // writes to storage + notifies listeners
/// print(token.value);            // reads from in-memory cache
/// await token.readFromStorage(); // hydrates cache from disk
/// ```
class StorageValue<T> extends ChangeNotifier {
  /// Creates a storage value bound to [key] in the given [storage] backend.
  ///
  /// [reviver] is an optional function for custom JSON deserialization
  /// (e.g. enum decoding, nested object mapping).
  StorageValue(this.storage, this.key, {this.reviver}) {
    var tType = TypeHelper<T>();
    if (!TypeHelper.supportType(tType) && reviver == null) {
      throw ArgumentError(
        '$StorageValue only supports $tType when reviver is provided',
      );
    }
    if (!storage.isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }
  }

  /// The storage backend.
  final StorageInterface storage;

  /// The storage key for this value.
  final String key;

  /// Optional custom JSON deserializer.
  T Function(Object? key, Object? value)? reviver;

  // ---------------------------------------------------------------------------
  // Reactive state
  // ---------------------------------------------------------------------------

  final _streamController = StreamController<T?>.broadcast();

  /// Subscribe to value changes.
  StreamSubscription<T?> Function(
    void Function(T? event)? onData, {
    bool? cancelOnError,
    void Function()? onDone,
    Function? onError,
  })
  get listen => _streamController.stream.listen;

  /// Obfuscated value stored in memory to prevent RAM dumping.
  ObfuscatedString? _obfuscatedValue;

  /// Current in-memory value (decrypted and revived on the fly).
  T? get value {
    if (_obfuscatedValue == null) return null;
    final jsonStr = _obfuscatedValue!.reveal();
    final decoded = json.decode(jsonStr);
    return _revive(decoded);
  }

  /// Update the value — persists to storage and notifies all listeners.
  set value(T? newValue) {
    _updateCache(newValue);
    _streamController.sink.add(newValue);
    storage.write(key, newValue);
    notifyListeners();
  }

  /// Decodes and revives the deserialized value.
  T? _revive(Object? decoded) {
    if (decoded == null) return null;
    var tType = TypeHelper<T>();

    if (tType is TypeHelper<List>) {
      if (decoded is List) {
        if (reviver != null) {
          return reviver!.call(key, decoded);
        }
        return decoded as T;
      }
    }

    if (TypeHelper.supportType(tType)) {
      if (tType is TypeHelper<Enum>) {
        return reviver?.call(key, decoded);
      }
      return decoded as T?;
    }
    return reviver?.call(key, decoded);
  }

  /// Updates the in-memory obfuscated cache.
  void _updateCache(T? newValue) {
    try {
      if (_obfuscatedValue != null) {
        _obfuscatedValue!.dispose();
        _obfuscatedValue = null;
      }

      if (newValue != null) {
        final jsonStr = jsonEncode(
          newValue,
          toEncodable: (nonEncodable) {
            if (nonEncodable is Enum) {
              return nonEncodable.name;
            }
            return jsonEncode(nonEncodable);
          },
        );
        _obfuscatedValue = ObfuscatedString(jsonStr);
      }
    } catch (e, s) {
      DynamicLogger.log(
        'Error updating cache: $e',
        stackTrace: s,
        level: LogLevel.ERROR,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Storage operations
  // ---------------------------------------------------------------------------

  /// Save this value to storage and in-memory cache
  void save(T value) {
    this.value = value;
  }

  /// Delete this value from storage and reset in-memory cache.
  void delete() {
    _updateCache(null);
    _streamController.sink.add(null);
    storage.delete(key);
    notifyListeners();
  }

  /// Hydrate the in-memory cache from persistent storage without redundant write.
  Future<void> readFromStorage() async {
    final newValue = await storage.read(key, reviver: reviver);
    _updateCache(newValue);
    _streamController.sink.add(newValue);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_obfuscatedValue != null) {
      _obfuscatedValue!.dispose();
      _obfuscatedValue = null;
    }
    _streamController.close();
    super.dispose();
  }
}
