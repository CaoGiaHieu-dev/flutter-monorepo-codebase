/// Helper class for type checking.
class TypeHelper<T> {
  const TypeHelper();

  bool operator >=(TypeHelper other) => other is TypeHelper<T>;

  bool operator <=(TypeHelper other) => other >= this;

  bool operator >(TypeHelper other) => this >= other && !(other >= this);

  bool operator <(TypeHelper other) => other >= this && !(this >= other);

  /// Check if the type is supported.
  static bool supportType(TypeHelper tType) {
    return tType is TypeHelper<num> ||
        tType is TypeHelper<String> ||
        tType is TypeHelper<List> ||
        tType is TypeHelper<Enum> ||
        tType is TypeHelper<bool> ||
        tType is TypeHelper<Map<String, dynamic>>;
  }
}
