/// Constants owned exclusively by `core_database`.
///
/// `core_database` provides the persistence MECHANISM only — these values
/// describe the database file itself, never any feature's or domain's data.
/// Feature/domain-specific keys belong in that package's own `utils/` folder.
class DatabaseConstants {
  DatabaseConstants._();

  /// Default number of concurrent read connections for the background
  /// isolate pool. `1` keeps a single reader (no concurrent reads).
  static const int DEFAULT_READ_POOL = 1;

  /// How long SQLite waits for a held lock before returning
  /// `SQLITE_BUSY` ("database is locked"), in milliseconds.
  ///
  /// Applied via `PRAGMA busy_timeout` in [MigrationStrategy.beforeOpen].
  /// Without it the default is `0` — a contended write fails instantly
  /// instead of waiting for the other connection to finish.
  static const int BUSY_TIMEOUT_MS = 5000;

  /// Suffix appended to a database file that failed to open because its
  /// contents are corrupt.
  ///
  /// The corrupt file is renamed rather than deleted so the bytes survive
  /// for support/forensics; see `DriftDatabaseOpener.open`.
  static const String CORRUPT_FILE_SUFFIX = '.corrupt';

  /// Substrings that identify a genuinely corrupt database file.
  ///
  /// Kept deliberately narrow: matching one of these is the ONLY condition
  /// under which the app is allowed to move a user's database aside. Every
  /// other failure (permissions, full disk, transient I/O) must surface to
  /// the caller untouched — see [ENVIRONMENT_ERROR_MARKERS].
  static const List<String> CORRUPTION_ERROR_MARKERS = <String>[
    'database disk image is malformed', // SQLITE_CORRUPT
    'file is not a database', // SQLITE_NOTADB
    'file is encrypted or is not a database', // SQLITE_NOTADB
    'malformed database schema',
  ];

  /// Substrings that identify an environment failure, never corruption.
  ///
  /// If any of these appear the database is left completely untouched, even
  /// when a corruption marker also matched — losing user data is worse than
  /// surfacing a startup error.
  static const List<String> ENVIRONMENT_ERROR_MARKERS = <String>[
    'unable to open database file', // SQLITE_CANTOPEN
    'disk i/o error', // SQLITE_IOERR
    'database or disk is full', // SQLITE_FULL
    'attempt to write a readonly database', // SQLITE_READONLY
    'access denied',
    'permission denied',
    'operation not permitted',
  ];
}
