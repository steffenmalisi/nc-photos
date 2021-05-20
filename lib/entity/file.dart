import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:idb_sqflite/idb_sqflite.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/account.dart';
import 'package:nc_photos/api/api.dart';
import 'package:nc_photos/app_db.dart';
import 'package:nc_photos/entity/exif.dart';
import 'package:nc_photos/entity/webdav_response_parser.dart';
import 'package:nc_photos/exception.dart';
import 'package:nc_photos/int_util.dart' as int_util;
import 'package:nc_photos/iterable_extension.dart';
import 'package:nc_photos/or_null.dart';
import 'package:nc_photos/string_extension.dart';
import 'package:path/path.dart' as path;
import 'package:quiver/iterables.dart';
import 'package:xml/xml.dart';

int compareFileDateTimeDescending(File x, File y) {
  final xDate = x.metadata?.exif?.dateTimeOriginal ?? x.lastModified;
  final yDate = y.metadata?.exif?.dateTimeOriginal ?? y.lastModified;
  final tmp = yDate.compareTo(xDate);
  if (tmp != 0) {
    return tmp;
  } else {
    // compare file name if files are modified at the same time
    return x.path.compareTo(y.path);
  }
}

/// Immutable object that hold metadata of a [File]
class Metadata with EquatableMixin {
  Metadata({
    DateTime lastUpdated,
    this.fileEtag,
    this.imageWidth,
    this.imageHeight,
    this.exif,
  }) : this.lastUpdated = (lastUpdated ?? DateTime.now()).toUtc();

  /// Parse Metadata from [json]
  ///
  /// If the version saved in json does not match the active one, the
  /// corresponding upgrader will be called one by one to upgrade the json,
  /// version by version until it reached the active version. If any upgrader
  /// in the chain is null, the upgrade process will fail
  factory Metadata.fromJson(
    Map<String, dynamic> json, {
    MetadataUpgraderV1 upgraderV1,
    MetadataUpgraderV2 upgraderV2,
  }) {
    final jsonVersion = json["version"];
    if (jsonVersion < 2) {
      json = upgraderV1?.call(json);
      if (json == null) {
        _log.info("[fromJson] Version $jsonVersion not compatible");
        return null;
      }
    }
    if (jsonVersion < 3) {
      json = upgraderV2?.call(json);
      if (json == null) {
        _log.info("[fromJson] Version $jsonVersion not compatible");
        return null;
      }
    }
    return Metadata(
      lastUpdated: json["lastUpdated"] == null
          ? null
          : DateTime.parse(json["lastUpdated"]),
      fileEtag: json["fileEtag"],
      imageWidth: json["imageWidth"],
      imageHeight: json["imageHeight"],
      exif: json["exif"] == null
          ? null
          : Exif.fromJson(json["exif"].cast<String, dynamic>()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "version": version,
      "lastUpdated": lastUpdated.toIso8601String(),
      if (fileEtag != null) "fileEtag": fileEtag,
      if (imageWidth != null) "imageWidth": imageWidth,
      if (imageHeight != null) "imageHeight": imageHeight,
      if (exif != null) "exif": exif.toJson(),
    };
  }

  @override
  toString() {
    var product = "$runtimeType {"
        "lastUpdated: $lastUpdated, ";
    if (fileEtag != null) {
      product += "fileEtag: $fileEtag, ";
    }
    if (imageWidth != null) {
      product += "imageWidth: $imageWidth, ";
    }
    if (imageHeight != null) {
      product += "imageHeight: $imageHeight, ";
    }
    if (exif != null) {
      product += "exif: $exif, ";
    }
    return product + "}";
  }

  @override
  get props => [
        lastUpdated,
        fileEtag,
        imageWidth,
        imageHeight,
        exif,
      ];

  final DateTime lastUpdated;

  /// Etag of the parent file when the metadata is saved
  final String fileEtag;
  final int imageWidth;
  final int imageHeight;
  final Exif exif;

  /// versioning of this class, use to upgrade old persisted metadata
  static const version = 3;

  static final _log = Logger("entity.file.Metadata");
}

abstract class MetadataUpgrader {
  Map<String, dynamic> call(Map<String, dynamic> json);
}

/// Upgrade v1 Metadata to v2
class MetadataUpgraderV1 implements MetadataUpgrader {
  MetadataUpgraderV1({
    @required this.fileContentType,
    this.logFilePath,
  });

  Map<String, dynamic> call(Map<String, dynamic> json) {
    if (fileContentType == "image/webp") {
      // Version 1 metadata for webp is bugged, drop it
      _log.fine("[call] Upgrade v1 metadata for file: $logFilePath");
      return null;
    } else {
      return json;
    }
  }

  final String fileContentType;

  /// File path for logging only
  final String logFilePath;

  static final _log = Logger("entity.file.MetadataUpgraderV1");
}

/// Upgrade v2 Metadata to v3
class MetadataUpgraderV2 implements MetadataUpgrader {
  MetadataUpgraderV2({
    @required this.fileContentType,
    this.logFilePath,
  });

  Map<String, dynamic> call(Map<String, dynamic> json) {
    if (fileContentType == "image/jpeg") {
      // Version 2 metadata for jpeg doesn't consider orientation
      if (json["exif"] != null && json["exif"].containsKey("Orientation")) {
        // Check orientation
        final orientation = json["exif"]["Orientation"];
        if (orientation >= 5 && orientation <= 8) {
          _log.fine("[call] Upgrade v2 metadata for file: $logFilePath");
          final temp = json["imageWidth"];
          json["imageWidth"] = json["imageHeight"];
          json["imageHeight"] = temp;
        }
      }
    }
    return json;
  }

  final String fileContentType;

  /// File path for logging only
  final String logFilePath;

  static final _log = Logger("entity.file.MetadataUpgraderV2");
}

class File with EquatableMixin {
  File({
    @required String path,
    this.contentLength,
    this.contentType,
    this.etag,
    this.lastModified,
    this.isCollection,
    this.usedBytes,
    this.hasPreview,
    this.fileId,
    this.metadata,
  }) : this.path = path.trimRightAny("/");

  factory File.fromJson(Map<String, dynamic> json) {
    return File(
      path: json["path"],
      contentLength: json["contentLength"],
      contentType: json["contentType"],
      etag: json["etag"],
      lastModified: json["lastModified"] == null
          ? null
          : DateTime.parse(json["lastModified"]),
      isCollection: json["isCollection"],
      usedBytes: json["usedBytes"],
      hasPreview: json["hasPreview"],
      fileId: json["fileId"],
      metadata: json["metadata"] == null
          ? null
          : Metadata.fromJson(
              json["metadata"].cast<String, dynamic>(),
              upgraderV1: MetadataUpgraderV1(
                fileContentType: json["contentType"],
                logFilePath: json["path"],
              ),
              upgraderV2: MetadataUpgraderV2(
                fileContentType: json["contentType"],
                logFilePath: json["path"],
              ),
            ),
    );
  }

  @override
  toString() {
    var product = "$runtimeType {"
        "path: '$path', ";
    if (contentLength != null) {
      product += "contentLength: $contentLength, ";
    }
    if (contentType != null) {
      product += "contentType: '$contentType', ";
    }
    if (etag != null) {
      product += "etag: '$etag', ";
    }
    if (lastModified != null) {
      product += "lastModified: $lastModified, ";
    }
    if (isCollection != null) {
      product += "isCollection: $isCollection, ";
    }
    if (usedBytes != null) {
      product += "usedBytes: $usedBytes, ";
    }
    if (hasPreview != null) {
      product += "hasPreview: $hasPreview, ";
    }
    if (fileId != null) {
      product += "fileId: '$fileId', ";
    }
    if (metadata != null) {
      product += "metadata: $metadata, ";
    }
    return product + "}";
  }

  Map<String, dynamic> toJson() {
    return {
      "path": path,
      if (contentLength != null) "contentLength": contentLength,
      if (contentType != null) "contentType": contentType,
      if (etag != null) "etag": etag,
      if (lastModified != null) "lastModified": lastModified.toIso8601String(),
      if (isCollection != null) "isCollection": isCollection,
      if (usedBytes != null) "usedBytes": usedBytes,
      if (hasPreview != null) "hasPreview": hasPreview,
      if (fileId != null) "fileId": fileId,
      if (metadata != null) "metadata": metadata.toJson(),
    };
  }

  File copyWith({
    String path,
    int contentLength,
    String contentType,
    String etag,
    DateTime lastModified,
    bool isCollection,
    int usedBytes,
    bool hasPreview,
    int fileId,
    OrNull<Metadata> metadata,
  }) {
    return File(
      path: path ?? this.path,
      contentLength: contentLength ?? this.contentLength,
      contentType: contentType ?? this.contentType,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      isCollection: isCollection ?? this.isCollection,
      usedBytes: usedBytes ?? this.usedBytes,
      hasPreview: hasPreview ?? this.hasPreview,
      fileId: fileId ?? this.fileId,
      metadata: metadata == null ? this.metadata : metadata.obj,
    );
  }

  /// Return the path of this file with the DAV part stripped
  String get strippedPath {
    // WebDAV path: remote.php/dav/files/{username}/{path}
    if (path.contains("remote.php/dav/files")) {
      return path
          .substring(path.indexOf("/", "remote.php/dav/files/".length) + 1);
    } else {
      return path;
    }
  }

  @override
  get props => [
        path,
        contentLength,
        contentType,
        etag,
        lastModified,
        isCollection,
        usedBytes,
        hasPreview,
        fileId,
        metadata,
      ];

  final String path;
  final int contentLength;
  final String contentType;
  final String etag;
  final DateTime lastModified;
  final bool isCollection;
  final int usedBytes;
  final bool hasPreview;
  // maybe null when loaded from old cache
  final int fileId;
  // metadata
  final Metadata metadata;
}

class FileRepo {
  FileRepo(this.dataSrc);

  /// See [FileDataSource.list]
  Future<List<File>> list(Account account, File root) =>
      this.dataSrc.list(account, root);

  /// See [FileDataSource.remove]
  Future<void> remove(Account account, File file) =>
      this.dataSrc.remove(account, file);

  /// See [FileDataSource.getBinary]
  Future<Uint8List> getBinary(Account account, File file) =>
      this.dataSrc.getBinary(account, file);

  /// See [FileDataSource.putBinary]
  Future<void> putBinary(Account account, String path, Uint8List content) =>
      this.dataSrc.putBinary(account, path, content);

  /// See [FileDataSource.updateMetadata]
  Future<void> updateMetadata(Account account, File file, Metadata metadata) =>
      this.dataSrc.updateMetadata(account, file, metadata);

  /// See [FileDataSource.copy]
  Future<void> copy(
    Account account,
    File f,
    String destination, {
    bool shouldOverwrite,
  }) =>
      this.dataSrc.copy(
            account,
            f,
            destination,
            shouldOverwrite: shouldOverwrite,
          );

  final FileDataSource dataSrc;
}

abstract class FileDataSource {
  /// List all files under [f]
  Future<List<File>> list(Account account, File f);

  /// Remove file
  Future<void> remove(Account account, File f);

  /// Read file as binary array
  Future<Uint8List> getBinary(Account account, File f);

  /// Upload content to [path]
  Future<void> putBinary(Account account, String path, Uint8List content);

  /// Update metadata for a file
  ///
  /// This will completely replace the metadata of the file [f]. Partial update
  /// is not supported
  Future<void> updateMetadata(Account account, File f, Metadata metadata);

  /// Copy [f] to [destination]
  ///
  /// [destination] should be a relative WebDAV path like
  /// remote.php/dav/files/admin/new/location
  Future<void> copy(
    Account account,
    File f,
    String destination, {
    bool shouldOverwrite,
  });
}

class FileWebdavDataSource implements FileDataSource {
  @override
  list(
    Account account,
    File f, {
    int depth,
  }) async {
    _log.fine("[list] ${f.path}");
    final response = await Api(account).files().propfind(
      path: f.path,
      depth: depth,
      getlastmodified: 1,
      resourcetype: 1,
      getetag: 1,
      getcontenttype: 1,
      getcontentlength: 1,
      hasPreview: 1,
      fileid: 1,
      customNamespaces: {
        "com.nkming.nc_photos": "app",
      },
      customProperties: [
        "app:metadata",
      ],
    );
    if (!response.isGood) {
      _log.severe("[list] Failed requesting server: $response");
      throw ApiException(
          response: response,
          message: "Failed communicating with server: ${response.statusCode}");
    }

    final xml = XmlDocument.parse(response.body);
    final files = WebdavFileParser()(xml);
    // _log.fine("[list] Parsed files: [$files]");
    return files.map((e) {
      if (e.metadata == null || e.metadata.fileEtag == e.etag) {
        return e;
      } else {
        _log.info("[list] Ignore outdated metadata for ${e.path}");
        return e.copyWith(metadata: OrNull(null));
      }
    }).toList();
  }

  @override
  remove(Account account, File f) async {
    _log.info("[remove] ${f.path}");
    final response = await Api(account).files().delete(path: f.path);
    if (!response.isGood) {
      _log.severe("[remove] Failed requesting server: $response");
      throw ApiException(
          response: response,
          message: "Failed communicating with server: ${response.statusCode}");
    }
  }

  @override
  getBinary(Account account, File f) async {
    _log.info("[getBinary] ${f.path}");
    final response = await Api(account).files().get(path: f.path);
    if (!response.isGood) {
      _log.severe("[getBinary] Failed requesting server: $response");
      throw ApiException(
          response: response,
          message: "Failed communicating with server: ${response.statusCode}");
    }
    return response.body;
  }

  @override
  putBinary(Account account, String path, Uint8List content) async {
    _log.info("[putBinary] $path");
    final response =
        await Api(account).files().put(path: path, content: content);
    if (!response.isGood) {
      _log.severe("[putBinary] Failed requesting server: $response");
      throw ApiException(
          response: response,
          message: "Failed communicating with server: ${response.statusCode}");
    }
  }

  @override
  updateMetadata(Account account, File f, Metadata metadata) async {
    _log.info("[updateMetadata] ${f.path}");
    if (metadata != null && metadata.fileEtag != f.etag) {
      _log.warning(
          "[updateMetadata] etag mismatch (metadata: ${metadata.fileEtag}, file: ${f.etag})");
    }
    final setProps = {
      if (metadata != null) "app:metadata": jsonEncode(metadata.toJson()),
    };
    final removeProps = [
      if (metadata == null) "app:metadata",
    ];
    final response = await Api(account).files().proppatch(
          path: f.path,
          namespaces: {
            "com.nkming.nc_photos": "app",
          },
          set: setProps.isNotEmpty ? setProps : null,
          remove: removeProps.isNotEmpty ? removeProps : null,
        );
    if (!response.isGood) {
      _log.severe("[updateMetadata] Failed requesting server: $response");
      throw ApiException(
          response: response,
          message: "Failed communicating with server: ${response.statusCode}");
    }
  }

  @override
  copy(
    Account account,
    File f,
    String destination, {
    bool shouldOverwrite,
  }) async {
    _log.info("[copy] ${f.path} to $destination");
    final response = await Api(account).files().copy(
          path: f.path,
          destinationUrl: "${account.url}/$destination",
          overwrite: shouldOverwrite,
        );
    if (!response.isGood) {
      _log.severe("[copy] Failed requesting sever: $response");
      throw ApiException(
          response: response,
          message: "Failed communicating with server: ${response.statusCode}");
    }
  }

  static final _log = Logger("entity.file.FileWebdavDataSource");
}

class FileAppDbDataSource implements FileDataSource {
  @override
  list(Account account, File f) {
    _log.info("[list] ${f.path}");
    return AppDb.use((db) async {
      final transaction = db.transaction(AppDb.fileStoreName, idbModeReadOnly);
      final store = transaction.objectStore(AppDb.fileStoreName);
      return await _doList(store, account, f);
    });
  }

  @override
  remove(Account account, File f) {
    _log.info("[remove] ${f.path}");
    return AppDb.use((db) async {
      final transaction = db.transaction(AppDb.fileStoreName, idbModeReadWrite);
      final store = transaction.objectStore(AppDb.fileStoreName);
      final index = store.index(AppDbFileEntry.indexName);
      final path = AppDbFileEntry.toPath(account, f);
      final range = KeyRange.bound([path, 0], [path, int_util.int32Max]);
      final keys = await index
          .openKeyCursor(range: range, autoAdvance: true)
          .map((cursor) => cursor.primaryKey)
          .toList();
      for (final k in keys) {
        _log.fine("[remove] Removing DB entry: $k");
        await store.delete(k);
      }
    });
  }

  @override
  getBinary(Account account, File f) {
    _log.info("[getBinary] ${f.path}");
    throw UnimplementedError();
  }

  @override
  putBinary(Account account, String path, Uint8List content) async {
    _log.info("[putBinary] $path");
    // do nothing, we currently don't store file contents locally
  }

  @override
  updateMetadata(Account account, File f, Metadata metadata) {
    _log.info("[updateMetadata] ${f.path}");
    return AppDb.use((db) async {
      final transaction = db.transaction(AppDb.fileStoreName, idbModeReadWrite);
      final store = transaction.objectStore(AppDb.fileStoreName);
      final parentDir = File(path: path.dirname(f.path));
      final parentList = await _doList(store, account, parentDir);
      final jsonList = parentList.map((e) {
        if (e.path == f.path) {
          return e.copyWith(metadata: OrNull(metadata));
        } else {
          return e;
        }
      });
      await _cacheListResults(store, account, parentDir, jsonList);
    });
  }

  @override
  copy(
    Account account,
    File f,
    String destination, {
    bool shouldOverwrite,
  }) async {
    // do nothing
  }

  Future<List<File>> _doList(ObjectStore store, Account account, File f) async {
    final index = store.index(AppDbFileEntry.indexName);
    final path = AppDbFileEntry.toPath(account, f);
    final range = KeyRange.bound([path, 0], [path, int_util.int32Max]);
    final List results = await index.getAll(range);
    if (results?.isNotEmpty == true) {
      final entries = results
          .map((e) => AppDbFileEntry.fromJson(e.cast<String, dynamic>()));
      return entries.map((e) {
        _log.info("[_doList] ${e.path}[${e.index}]");
        return e.data;
      }).reduce((value, element) => value + element);
    } else {
      throw CacheNotFoundException("No entry: $path");
    }
  }

  static final _log = Logger("entity.file.FileAppDbDataSource");
}

class FileCachedDataSource implements FileDataSource {
  @override
  list(Account account, File f) async {
    final trimmedRootPath = f.path.trimAny("/");
    List<File> cache;
    try {
      cache = await _appDbSrc.list(account, f);
      // compare the cached root
      final cacheEtag = cache
          .firstWhere((element) => element.path.trimAny("/") == trimmedRootPath)
          .etag;
      if (cacheEtag != null) {
        // compare the etag to see if the content has been updated
        var remoteEtag = f.etag;
        if (remoteEtag == null) {
          // no etag supplied, we need to query it form remote
          final remote = await _remoteSrc.list(account, f, depth: 0);
          assert(remote.length == 1);
          remoteEtag = remote.first.etag;
        }
        if (cacheEtag == remoteEtag) {
          // cache is good
          _log.fine(
              "[list] etag matched for ${AppDbFileEntry.toPath(account, f)}");
          return cache;
        }
      }
      _log.info(
          "[list] Remote content updated for ${AppDbFileEntry.toPath(account, f)}");
    } on CacheNotFoundException catch (_) {
      // normal when there's no cache
    } catch (e, stacktrace) {
      _log.shout("[list] Cache failure", e, stacktrace);
    }

    // no cache
    try {
      final remote = await _remoteSrc.list(account, f);
      await _cacheResult(account, f, remote);
      if (cache != null) {
        try {
          await _cleanUpCachedDir(account, remote, cache);
        } catch (e, stacktrace) {
          _log.shout("[list] Failed while _cleanUpCachedList", e, stacktrace);
          // ignore error
        }
      }
      return remote;
    } on ApiException catch (e) {
      if (e.response.statusCode == 404) {
        _log.info("[list] File removed: $f");
        _appDbSrc.remove(account, f);
        return [];
      } else {
        rethrow;
      }
    }
  }

  @override
  remove(Account account, File f) async {
    await _appDbSrc.remove(account, f);
    await _remoteSrc.remove(account, f);
  }

  @override
  getBinary(Account account, File f) {
    return _remoteSrc.getBinary(account, f);
  }

  @override
  putBinary(Account account, String path, Uint8List content) async {
    await _remoteSrc.putBinary(account, path, content);
  }

  @override
  updateMetadata(Account account, File f, Metadata metadata) async {
    await _remoteSrc
        .updateMetadata(account, f, metadata)
        .then((_) => _appDbSrc.updateMetadata(account, f, metadata));
  }

  @override
  copy(
    Account account,
    File f,
    String destination, {
    bool shouldOverwrite,
  }) async {
    await _remoteSrc.copy(account, f, destination,
        shouldOverwrite: shouldOverwrite);
  }

  Future<void> _cacheResult(Account account, File f, List<File> result) {
    return AppDb.use((db) async {
      final transaction = db.transaction(AppDb.fileStoreName, idbModeReadWrite);
      final store = transaction.objectStore(AppDb.fileStoreName);
      await _cacheListResults(store, account, f, result);
    });
  }

  /// Remove dangling dir entries in the file object store
  Future<void> _cleanUpCachedDir(
      Account account, List<File> remoteResults, List<File> cachedResults) {
    final removed = cachedResults
        .where((cache) =>
            !remoteResults.any((remote) => remote.path == cache.path))
        .toList();
    if (removed.isEmpty) {
      return Future.delayed(Duration.zero);
    }
    return AppDb.use((db) async {
      final transaction = db.transaction(AppDb.fileStoreName, idbModeReadWrite);
      final store = transaction.objectStore(AppDb.fileStoreName);
      final index = store.index(AppDbFileEntry.indexName);
      for (final r in removed) {
        final path = AppDbFileEntry.toPath(account, r);
        final keys = [];
        // delete the dir itself
        final dirRange = KeyRange.bound([path, 0], [path, int_util.int32Max]);
        // delete with KeyRange is not supported in idb_shim/idb_sqflite
        // await store.delete(dirRange);
        keys.addAll(await index
            .openKeyCursor(range: dirRange, autoAdvance: true)
            .map((cursor) => cursor.primaryKey)
            .toList());
        // then its children
        final childrenRange =
            KeyRange.bound(["$path/", 0], ["$path/\uffff", int_util.int32Max]);
        keys.addAll(await index
            .openKeyCursor(range: childrenRange, autoAdvance: true)
            .map((cursor) => cursor.primaryKey)
            .toList());

        for (final k in keys) {
          _log.fine("[_cleanUpCachedDir] Removing DB entry: $k");
          await store.delete(k);
        }
      }
    });
  }

  final _remoteSrc = FileWebdavDataSource();
  final _appDbSrc = FileAppDbDataSource();

  static final _log = Logger("entity.file.FileCachedDataSource");
}

Future<void> _cacheListResults(
    ObjectStore store, Account account, File f, Iterable<File> results) async {
  final index = store.index(AppDbFileEntry.indexName);
  final path = AppDbFileEntry.toPath(account, f);
  final range = KeyRange.bound([path, 0], [path, int_util.int32Max]);
  // count number of entries for this dir
  final count = await index.count(range);
  int newCount = 0;
  for (final pair
      in partition(results, AppDbFileEntry.maxDataSize).withIndex()) {
    _log.info(
        "[_cacheListResults] Caching $path[${pair.item1}], length: ${pair.item2.length}");
    await store.put(
      AppDbFileEntry(path, pair.item1, pair.item2).toJson(),
      AppDbFileEntry.toPrimaryKey(account, f, pair.item1),
    );
    ++newCount;
  }
  if (count > newCount) {
    // index is 0-based
    final rmRange = KeyRange.bound([path, newCount], [path, int_util.int32Max]);
    final rmKeys = await index
        .openKeyCursor(range: rmRange, autoAdvance: true)
        .map((cursor) => cursor.primaryKey)
        .toList();
    for (final k in rmKeys) {
      _log.fine("[_cacheListResults] Removing DB entry: $k");
      await store.delete(k);
    }
  }
}

final _log = Logger("entity.file");
