import 'package:core_database/core_database.dart';
import 'package:injectable/injectable.dart';

import '../../database/cache_database.dart';
import '../../models/cache_entry_model.dart';

/// Signatures speak in [CacheEntryModel], never in Drift's generated row
/// class, so Drift stays an implementation detail of `data_cache`.
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<CacheEntryModel?> getEntry(String key);
}

/// SAMPLE — takes [IDatabaseHandle] rather than [CacheDatabase] (only the one
/// DAO it asks for) and converts Drift rows to models here.
@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(IDatabaseHandle<CacheDatabase> handle)
    : _dao = handle.accessor(CacheEntriesDao.new);

  final CacheEntriesDao _dao;

  @override
  Future<void> save(String key, String value) => _dao.upsert(key, value);

  @override
  Future<CacheEntryModel?> getEntry(String key) async {
    final row = await _dao.getEntry(key);
    return row == null ? null : CacheEntryModel.fromRow(row);
  }
}
