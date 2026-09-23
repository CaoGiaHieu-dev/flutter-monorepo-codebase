// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

import 'package:core_database/core_database.dart';
import 'package:injectable/injectable.dart';

import '../../database/cache_database.dart';
import '../../models/cache_entry_model.dart';

/// Contract for reading/writing cache rows.
///
/// Signatures speak in [CacheEntryModel], never in Drift's generated row
/// class — that keeps Drift an implementation detail of `data_core` instead
/// of leaking it to every consumer of this package.
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<String?> get(String key);

  Future<CacheEntryModel?> getEntry(String key);

  Future<void> delete(String key);

  Future<List<CacheEntryModel>> getAll();
}

/// Example local data source — demonstrates the two boundaries the Data layer
/// is expected to hold.
///
/// * It takes [IDatabaseHandle], not [CacheDatabase], so it can only reach
///   the one accessor it asks for instead of every DAO on the database.
/// * It converts Drift rows into [CacheEntryModel] here, so drift's generated
///   types never appear in this package's public API.
@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(IDatabaseHandle<CacheDatabase> handle)
    : _dao = handle.accessor(CacheEntriesDao.new);

  final CacheEntriesDao _dao;

  @override
  Future<void> save(String key, String value) {
    return _dao.upsert(key, value);
  }

  @override
  Future<String?> get(String key) {
    return _dao.getValue(key);
  }

  @override
  Future<CacheEntryModel?> getEntry(String key) async {
    final row = await _dao.getEntry(key);
    return row == null ? null : CacheEntryModel.fromRow(row);
  }

  @override
  Future<void> delete(String key) {
    return _dao.deleteByKey(key);
  }

  @override
  Future<List<CacheEntryModel>> getAll() async {
    final rows = await _dao.getAll();
    return rows.map(CacheEntryModel.fromRow).toList();
  }
}
