/// A data-layer model that converts to its domain entity [E].
abstract class BaseModel<E> {
  /// The domain entity this model represents.
  E toEntity();
}
