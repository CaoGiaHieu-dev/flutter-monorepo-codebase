abstract class BaseModel<E> {
  E toEntity() {
    throw UnimplementedError();
  }
}
