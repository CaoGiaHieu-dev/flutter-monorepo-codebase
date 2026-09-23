// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

/// Input for saving a cache row to the local database.
class CacheEntryParams {
  const CacheEntryParams({required this.key, required this.value});

  final String key;
  final String value;
}
