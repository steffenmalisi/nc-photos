import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/mobile/platform.dart'
    if (dart.library.html) 'package:nc_photos/web/platform.dart' as platform;

part 'sqlite_table.g.dart';

class Servers extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get address => text().unique()();
}

class Accounts extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  IntColumn get server =>
      integer().references(Servers, #rowId, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();

  @override
  get uniqueKeys => [
        {server, userId},
      ];
}

/// A file located on a server
class Files extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  IntColumn get server =>
      integer().references(Servers, #rowId, onDelete: KeyAction.cascade)();
  IntColumn get fileId => integer()();
  IntColumn get contentLength => integer().nullable()();
  TextColumn get contentType => text().nullable()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get lastModified =>
      dateTime().map(const _DateTimeConverter()).nullable()();
  BoolColumn get isCollection => boolean().nullable()();
  IntColumn get usedBytes => integer().nullable()();
  BoolColumn get hasPreview => boolean().nullable()();
  TextColumn get ownerId => text().nullable()();
  TextColumn get ownerDisplayName => text().nullable()();

  @override
  get uniqueKeys => [
        {server, fileId},
      ];
}

/// Account specific properties associated with a file
///
/// A file on a Nextcloud server can have more than 1 path when it's shared
class AccountFiles extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  IntColumn get account =>
      integer().references(Accounts, #rowId, onDelete: KeyAction.cascade)();
  IntColumn get file =>
      integer().references(Files, #rowId, onDelete: KeyAction.cascade)();
  TextColumn get relativePath => text()();
  BoolColumn get isFavorite => boolean().nullable()();
  BoolColumn get isArchived => boolean().nullable()();
  DateTimeColumn get overrideDateTime =>
      dateTime().map(const _DateTimeConverter()).nullable()();
  DateTimeColumn get bestDateTime =>
      dateTime().map(const _DateTimeConverter())();

  @override
  get uniqueKeys => [
        {account, file},
      ];
}

/// An image file
class Images extends Table {
  // image data technically is identical between accounts, but the way it's
  // stored in the server is account specific so we follow the server here
  IntColumn get accountFile =>
      integer().references(AccountFiles, #rowId, onDelete: KeyAction.cascade)();
  DateTimeColumn get lastUpdated =>
      dateTime().map(const _DateTimeConverter())();
  TextColumn get fileEtag => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get exifRaw => text().nullable()();

  // exif columns
  DateTimeColumn get dateTimeOriginal =>
      dateTime().map(const _DateTimeConverter()).nullable()();

  @override
  get primaryKey => {accountFile};
}

/// Estimated locations for images
class ImageLocations extends Table {
  IntColumn get accountFile =>
      integer().references(AccountFiles, #rowId, onDelete: KeyAction.cascade)();
  IntColumn get version => integer()();
  TextColumn get name => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get countryCode => text().nullable()();
  TextColumn get admin1 => text().nullable()();
  TextColumn get admin2 => text().nullable()();

  @override
  get primaryKey => {accountFile};
}

/// A file inside trashbin
@DataClassName("Trash")
class Trashes extends Table {
  IntColumn get file =>
      integer().references(Files, #rowId, onDelete: KeyAction.cascade)();
  TextColumn get filename => text()();
  TextColumn get originalLocation => text()();
  DateTimeColumn get deletionTime =>
      dateTime().map(const _DateTimeConverter())();

  @override
  get primaryKey => {file};
}

/// A file located under another dir (dir is also a file)
class DirFiles extends Table {
  IntColumn get dir =>
      integer().references(Files, #rowId, onDelete: KeyAction.cascade)();
  IntColumn get child =>
      integer().references(Files, #rowId, onDelete: KeyAction.cascade)();

  @override
  get primaryKey => {dir, child};
}

class Albums extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  IntColumn get file => integer()
      .references(Files, #rowId, onDelete: KeyAction.cascade)
      .unique()();
  // store the etag of the file when the album is cached in the db
  TextColumn get fileEtag => text().nullable()();
  IntColumn get version => integer()();
  DateTimeColumn get lastUpdated =>
      dateTime().map(const _DateTimeConverter())();
  TextColumn get name => text()();

  // provider
  TextColumn get providerType => text()();
  TextColumn get providerContent => text()();

  // cover provider
  TextColumn get coverProviderType => text()();
  TextColumn get coverProviderContent => text()();

  // sort provider
  TextColumn get sortProviderType => text()();
  TextColumn get sortProviderContent => text()();
}

class AlbumShares extends Table {
  IntColumn get album =>
      integer().references(Albums, #rowId, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get displayName => text().nullable()();
  DateTimeColumn get sharedAt => dateTime().map(const _DateTimeConverter())();

  @override
  get primaryKey => {album, userId};
}

class Tags extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  IntColumn get server =>
      integer().references(Servers, #rowId, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer()();
  TextColumn get displayName => text()();
  BoolColumn get userVisible => boolean().nullable()();
  BoolColumn get userAssignable => boolean().nullable()();

  @override
  get uniqueKeys => [
        {server, tagId},
      ];
}

class Persons extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  IntColumn get account =>
      integer().references(Accounts, #rowId, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get thumbFaceId => integer()();
  IntColumn get count => integer()();

  @override
  get uniqueKeys => [
        {account, name},
      ];
}

// remember to also update the truncate method after adding a new table
@DriftDatabase(
  tables: [
    Servers,
    Accounts,
    Files,
    Images,
    ImageLocations,
    Trashes,
    AccountFiles,
    DirFiles,
    Albums,
    AlbumShares,
    Tags,
    Persons,
  ],
)
class SqliteDb extends _$SqliteDb {
  SqliteDb({
    QueryExecutor? executor,
  }) : super(executor ?? platform.openSqliteConnection());

  SqliteDb.connect(DatabaseConnection connection) : super.connect(connection);

  @override
  get schemaVersion => 4;

  @override
  get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement("PRAGMA journal_mode=WAL;");
          await m.createAll();

          await m.createIndex(Index("files_server_index",
              "CREATE INDEX files_server_index ON files(server);"));
          await m.createIndex(Index("files_file_id_index",
              "CREATE INDEX files_file_id_index ON files(file_id);"));
          await m.createIndex(Index("files_content_type_index",
              "CREATE INDEX files_content_type_index ON files(content_type);"));

          await m.createIndex(Index("account_files_file_index",
              "CREATE INDEX account_files_file_index ON account_files(file);"));
          await m.createIndex(Index("account_files_relative_path_index",
              "CREATE INDEX account_files_relative_path_index ON account_files(relative_path);"));
          await m.createIndex(Index("account_files_best_date_time_index",
              "CREATE INDEX account_files_best_date_time_index ON account_files(best_date_time);"));

          await m.createIndex(Index("dir_files_dir_index",
              "CREATE INDEX dir_files_dir_index ON dir_files(dir);"));
          await m.createIndex(Index("dir_files_child_index",
              "CREATE INDEX dir_files_child_index ON dir_files(child);"));

          await m.createIndex(Index("album_shares_album_index",
              "CREATE INDEX album_shares_album_index ON album_shares(album);"));

          await _createIndexV2(m);
        },
        onUpgrade: (m, from, to) async {
          _log.info("[onUpgrade] $from -> $to");
          try {
            await transaction(() async {
              if (from < 2) {
                await m.createTable(tags);
                await m.createTable(persons);
                await _createIndexV2(m);
              }
              if (from < 3) {
                await m.createTable(imageLocations);
                await _createIndexV3(m);
              }
              if (from < 4) {
                await m.addColumn(albums, albums.fileEtag);
              }
            });
          } catch (e, stackTrace) {
            _log.shout("[onUpgrade] Failed upgrading sqlite db", e, stackTrace);
            rethrow;
          }
        },
        beforeOpen: (details) async {
          await customStatement("PRAGMA foreign_keys = ON;");
          // technically we have a platform side lock to ensure only one
          // transaction is running in any isolates, but for some reason we are
          // still seeing database is locked error in crashlytics, let see if
          // this helps
          await customStatement("PRAGMA busy_timeout = 5000;");
        },
      );

  Future<void> _createIndexV2(Migrator m) async {
    await m.createIndex(Index("tags_server_index",
        "CREATE INDEX tags_server_index ON tags(server);"));
    await m.createIndex(Index("persons_account_index",
        "CREATE INDEX persons_account_index ON persons(account);"));
  }

  Future<void> _createIndexV3(Migrator m) async {
    await m.createIndex(Index("image_locations_name_index",
        "CREATE INDEX image_locations_name_index ON image_locations(name);"));
    await m.createIndex(Index("image_locations_country_code_index",
        "CREATE INDEX image_locations_country_code_index ON image_locations(country_code);"));
    await m.createIndex(Index("image_locations_admin1_index",
        "CREATE INDEX image_locations_admin1_index ON image_locations(admin1);"));
    await m.createIndex(Index("image_locations_admin2_index",
        "CREATE INDEX image_locations_admin2_index ON image_locations(admin2);"));
  }

  static final _log = Logger("entity.sqlite_table.SqliteDb");
}

class _DateTimeConverter extends TypeConverter<DateTime, DateTime> {
  const _DateTimeConverter();

  @override
  DateTime? mapToDart(DateTime? fromDb) => fromDb?.toUtc();

  @override
  DateTime? mapToSql(DateTime? value) => value?.toUtc();
}
