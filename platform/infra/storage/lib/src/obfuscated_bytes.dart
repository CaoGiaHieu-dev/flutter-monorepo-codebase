import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Bytes kept XOR-masked in RAM, so a memory dump does not show them as-is.
///
/// The one obfuscation used by this package: the backends' master keys and
/// `StorageValue`'s cached JSON (through [ObfuscatedBytes.fromString]).
class ObfuscatedBytes {
  /// Masks [original]. The caller should zero [original] afterwards.
  ObfuscatedBytes(List<int> original)
    : _mask = _randomMask(original.length),
      _masked = Uint8List(original.length) {
    for (var i = 0; i < original.length; i++) {
      _masked[i] = original[i] ^ _mask[i];
    }
  }

  /// Masks [value]'s UTF-8 bytes — sized by byte length, not
  /// [String.length], so multi-byte characters are not truncated.
  factory ObfuscatedBytes.fromString(String value) {
    final bytes = utf8.encode(value);
    final obfuscated = ObfuscatedBytes(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return obfuscated;
  }

  final Uint8List _masked;
  final Uint8List _mask;

  /// Reconstructs the original bytes. The caller must zero the returned list
  /// (`fillRange(0, length, 0)`) once done with it.
  Uint8List reveal() {
    final original = Uint8List(_masked.length);
    for (var i = 0; i < _masked.length; i++) {
      original[i] = _masked[i] ^ _mask[i];
    }
    return original;
  }

  /// Reconstructs the string masked by [ObfuscatedBytes.fromString]; the
  /// intermediate bytes are zeroed.
  String revealString() {
    final bytes = reveal();
    final value = utf8.decode(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return value;
  }

  /// Zeroes both buffers; the instance is unusable afterwards.
  void dispose() {
    _masked.fillRange(0, _masked.length, 0);
    _mask.fillRange(0, _mask.length, 0);
  }

  static Uint8List _randomMask(int length) {
    final random = math.Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}
