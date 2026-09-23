/// Input for saving a cache row to the local database.
class CacheEntryParams {
  const CacheEntryParams({required this.key, required this.value});

  final String key;
  final String value;
}
