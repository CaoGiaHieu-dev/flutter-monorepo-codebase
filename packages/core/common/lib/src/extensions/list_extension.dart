/// Extension methods for [List] to provide additional functionality.
///
/// This extension adds utility methods for common list operations like
/// null-safe access, grouping, chunking, and statistical operations.
extension ListExtension<T> on List<T> {
  /// Returns the first element or null if the list is empty
  T? get firstOrNull => isEmpty ? null : first;

  /// Returns the last element or null if the list is empty
  T? get lastOrNull => isEmpty ? null : last;

  /// Returns the element at `index` or null if index is out of bounds
  T? elementAtOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }

  /// Adds `item` to the list if it's not already present
  void addIfNotExists(T item) {
    if (!contains(item)) {
      add(item);
    }
  }

  /// Removes all null elements from the list
  List<T> removeNulls() {
    return where((element) => element != null).toList();
  }

  /// Groups the list elements by the result of `keySelector`
  Map<K, List<T>> groupBy<K>(K Function(T) keySelector) {
    final map = <K, List<T>>{};
    for (final element in this) {
      final key = keySelector(element);
      map.putIfAbsent(key, () => <T>[]).add(element);
    }
    return map;
  }

  /// Returns a new list with distinct elements based on `keySelector`
  List<T> distinctBy<K>(K Function(T) keySelector) {
    final seen = <K>{};
    return where((element) => seen.add(keySelector(element))).toList();
  }

  /// Splits the list into chunks of the specified `size`
  List<List<T>> chunk(int size) {
    if (size <= 0) throw ArgumentError('Size must be positive');

    final chunks = <List<T>>[];
    for (int i = 0; i < length; i += size) {
      chunks.add(sublist(i, (i + size).clamp(0, length)));
    }
    return chunks;
  }

  /// Returns a random element from the list
  T? get random {
    if (isEmpty) return null;
    final random = DateTime.now().millisecondsSinceEpoch % length;
    return this[random];
  }

  /// Shuffles the list and returns a new shuffled list
  List<T> shuffled() {
    final shuffled = List<T>.from(this);
    shuffled.shuffle();
    return shuffled;
  }

  /// Returns the second element or null if the list has less than 2 elements
  T? get secondOrNull => length < 2 ? null : this[1];

  /// Returns the second to last element or null if the list has less than 2 elements
  T? get secondLastOrNull => length < 2 ? null : this[length - 2];

  /// Checks if the list has duplicates
  bool get hasDuplicates => length != toSet().length;

  /// Returns the most frequent element in the list
  T? get mostFrequent {
    if (isEmpty) return null;

    final frequency = <T, int>{};
    for (final element in this) {
      frequency[element] = (frequency[element] ?? 0) + 1;
    }

    return frequency.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

/// Extension methods for [List] of [String] to provide string-specific functionality.
///
/// This extension adds utility methods for string list operations like
/// joining with conjunctions and filtering empty strings.
extension StringListExtension on List<String> {
  /// Joins the list with commas and 'and' before the last element
  String joinWithAnd() {
    if (isEmpty) return '';
    if (length == 1) return first;
    if (length == 2) return '$first and $last';

    final allButLast = sublist(0, length - 1).join(', ');
    return '$allButLast, and $last';
  }

  /// Filters the list to contain only non-empty strings
  List<String> get nonEmpty => where((s) => s.isNotEmpty).toList();

  /// Trims all strings in the list
  List<String> get trimmed => map((s) => s.trim()).toList();
}

/// Extension methods for [List] of [int] to provide mathematical operations.
///
/// This extension adds utility methods for integer list calculations like
/// sum, average, and median operations.
extension IntListExtension on List<int> {
  /// Returns the sum of all elements
  int get sum => fold(0, (a, b) => a + b);

  /// Returns the average of all elements
  double get average => isEmpty ? 0 : sum / length;

  /// Returns the median of all elements
  double get median {
    if (isEmpty) return 0;

    final sorted = List<int>.from(this)..sort();
    final middle = sorted.length ~/ 2;

    if (sorted.length % 2 == 0) {
      return (sorted[middle - 1] + sorted[middle]) / 2;
    } else {
      return sorted[middle].toDouble();
    }
  }
}

/// Extension methods for [List] of [double] to provide mathematical operations.
///
/// This extension adds utility methods for double list calculations like
/// sum, average, and median operations with floating-point precision.
extension DoubleListExtension on List<double> {
  /// Returns the sum of all elements
  double get sum => fold(0.0, (a, b) => a + b);

  /// Returns the average of all elements
  double get average => isEmpty ? 0 : sum / length;

  /// Returns the median of all elements
  double get median {
    if (isEmpty) return 0;

    final sorted = List<double>.from(this)..sort();
    final middle = sorted.length ~/ 2;

    if (sorted.length % 2 == 0) {
      return (sorted[middle - 1] + sorted[middle]) / 2;
    } else {
      return sorted[middle];
    }
  }
}
