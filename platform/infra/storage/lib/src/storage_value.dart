import 'dart:async';
import 'dart:convert';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:platform_kernel/platform_kernel.dart';

import 'contracts/storage_interface.dart';
import 'obfuscated_bytes.dart';
import 'storage_codec.dart';

/// A reactive wrapper around a single key-value pair in [StorageInterface].
///
/// Provides:
/// - In-memory cache with [value] getter/setter (obfuscated in RAM)
/// - Persistence on every change: [save] / [remove] return a future that
///   completes once the value is on disk; the [value] setter starts the same
///   write without waiting for it
/// - [ChangeNotifier] integration for Provider/Riverpod listeners
/// - [Stream] broadcasting via [listen] for reactive pipelines
///
/// Writes are **serialized**: each starts after the previous one finished,
/// so the last value set is the one left on disk. A failed write is logged
/// through `DynamicLogger` and never thrown — the in-memory value is already
/// the new one, and a storage error must not become an uncaught zone error.
///
/// Example:
/// ```dart
/// final token = StorageValue<String>(storage, 'auth_token');
/// await token.save('abc123');    // cache + listeners now, disk when awaited
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
  ObfuscatedBytes? _obfuscatedValue;

  /// The last write started; the next one chains onto it.
  Future<void> _lastWrite = Future.value();

  /// Current in-memory value (decrypted and revived on the fly).
  T? get value {
    if (_obfuscatedValue == null) return null;
    final jsonStr = _obfuscatedValue!.revealString();
    final decoded = json.decode(jsonStr);
    return _revive(decoded);
  }

  /// Updates the value and notifies listeners at once, and starts writing it
  /// to storage (`null` deletes it). Use [save] / [remove] to wait for the
  /// write.
  set value(T? newValue) {
    unawaited(newValue == null ? remove() : save(newValue));
  }

  /// Decodes and revives the deserialized value.
  T? _revive(Object? decoded) =>
      StorageCodec.revive<T>(decoded, key, reviver: reviver);

  /// Updates the in-memory obfuscated cache.
  void _updateCache(T? newValue) {
    try {
      if (_obfuscatedValue != null) {
        _obfuscatedValue!.dispose();
        _obfuscatedValue = null;
      }

      if (newValue != null) {
        final jsonStr = StorageCodec.encode(newValue);
        _obfuscatedValue = ObfuscatedBytes.fromString(jsonStr);
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

  /// Sets [newValue] in memory and notifies listeners at once; the returned
  /// future completes when it is written to storage. A failed write is
  /// logged, not thrown.
  Future<void> save(T newValue) {
    _publish(newValue);
    return _enqueueWrite(() => storage.write(key, newValue));
  }

  /// Clears the value in memory and notifies listeners at once; the returned
  /// future completes when it is deleted from storage. A failed delete is
  /// logged, not thrown.
  Future<void> remove() {
    _publish(null);
    return _enqueueWrite(() => storage.delete(key));
  }

  void _publish(T? newValue) {
    _updateCache(newValue);
    if (!_streamController.isClosed) _streamController.sink.add(newValue);
    notifyListeners();
  }

  /// Runs [write] after every write started before it, logging a failure.
  Future<void> _enqueueWrite(Future<void> Function() write) {
    final next = _lastWrite.then((_) => write()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      DynamicLogger.log(
        'Writing "$key" to storage failed: $error',
        tag: 'StorageValue',
        stackTrace: stackTrace,
        level: LogLevel.ERROR,
      );
    });
    _lastWrite = next;
    return next;
  }

  /// Hydrate the in-memory cache from persistent storage without redundant write.
  Future<void> readFromStorage() async {
    final newValue = await storage.read(key, reviver: reviver);
    _updateCache(newValue);
    if (!_streamController.isClosed) _streamController.sink.add(newValue);
    notifyListeners();
  }

  bool _isDisposed = false;

  /// Whether [dispose] has run. After it, [notifyListeners] is a no-op
  /// instead of throwing — a late `readFromStorage` or `save` completing
  /// after its owner went away must not crash.
  ///
  /// The same guard as `core_common`'s `DisposeGuard` mixin, spelled out
  /// here so `core_storage` (infra) needs only `platform_kernel` from the
  /// foundation group, not the Flutter-bound `core_common` and everything
  /// it pulls in (go_router, package_info_plus, http_security_pinning, …).
  bool get isDisposed => _isDisposed;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_obfuscatedValue != null) {
      _obfuscatedValue!.dispose();
      _obfuscatedValue = null;
    }
    _streamController.close();
    super.dispose();
  }
}
