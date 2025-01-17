import 'package:drift/drift.dart' as sql;
import 'package:nc_photos/di_container.dart';
import 'package:nc_photos/entity/person.dart';
import 'package:nc_photos/entity/person/data_source.dart';
import 'package:nc_photos/entity/sqlite_table.dart' as sql;
import 'package:nc_photos/entity/sqlite_table_converter.dart';
import 'package:nc_photos/entity/sqlite_table_extension.dart' as sql;
import 'package:nc_photos/use_case/sync_person.dart';
import 'package:test/test.dart';
import 'package:tuple/tuple.dart';

import '../mock_type.dart';
import '../test_util.dart' as util;

void main() {
  group("SyncPerson", () {
    test("new", _new);
    test("remove", _remove);
    test("update", _update);
  });
}

/// Sync with remote where there are new persons
///
/// Remote: [test1, test2, test3]
/// Local: [test1]
/// Expect: [test1, test2, test3]
Future<void> _new() async {
  final account = util.buildAccount();
  final c = DiContainer.late();
  c.sqliteDb = util.buildTestDb();
  addTearDown(() => c.sqliteDb.close());
  c.personRepoRemote = MockPersonMemoryRepo({
    account.id: [
      const Person(name: "test1", thumbFaceId: 1, count: 1),
      const Person(name: "test2", thumbFaceId: 2, count: 10),
      const Person(name: "test3", thumbFaceId: 3, count: 100),
    ],
  });
  c.personRepoLocal = PersonRepo(PersonSqliteDbDataSource(c.sqliteDb));
  await c.sqliteDb.transaction(() async {
    await c.sqliteDb.insertAccountOf(account);
    await c.sqliteDb.batch((batch) {
      batch.insert(
        c.sqliteDb.persons,
        sql.PersonsCompanion.insert(
            account: 1, name: "test1", thumbFaceId: 1, count: 1),
      );
    });
  });

  await SyncPerson(c)(account);
  expect(
    await _listSqliteDbPersons(c.sqliteDb),
    {
      account.userId.toCaseInsensitiveString(): {
        const Person(name: "test1", thumbFaceId: 1, count: 1),
        const Person(name: "test2", thumbFaceId: 2, count: 10),
        const Person(name: "test3", thumbFaceId: 3, count: 100),
      },
    },
  );
}

/// Sync with remote where there are removed persons
///
/// Remote: [test1]
/// Local: [test1, test2, test3]
/// Expect: [test1]
Future<void> _remove() async {
  final account = util.buildAccount();
  final c = DiContainer.late();
  c.sqliteDb = util.buildTestDb();
  addTearDown(() => c.sqliteDb.close());
  c.personRepoRemote = MockPersonMemoryRepo({
    account.id: [
      const Person(name: "test1", thumbFaceId: 1, count: 1),
    ],
  });
  c.personRepoLocal = PersonRepo(PersonSqliteDbDataSource(c.sqliteDb));
  await c.sqliteDb.transaction(() async {
    await c.sqliteDb.insertAccountOf(account);
    await c.sqliteDb.batch((batch) {
      batch.insertAll(c.sqliteDb.persons, [
        sql.PersonsCompanion.insert(
            account: 1, name: "test1", thumbFaceId: 1, count: 1),
        sql.PersonsCompanion.insert(
            account: 1, name: "test2", thumbFaceId: 2, count: 10),
        sql.PersonsCompanion.insert(
            account: 1, name: "test3", thumbFaceId: 3, count: 100),
      ]);
    });
  });

  await SyncPerson(c)(account);
  expect(
    await _listSqliteDbPersons(c.sqliteDb),
    {
      account.userId.toCaseInsensitiveString(): {
        const Person(name: "test1", thumbFaceId: 1, count: 1),
      },
    },
  );
}

/// Sync with remote where there are updated persons (i.e, same name, different
/// properties)
///
/// Remote: [test1, test2 (face: 3)]
/// Local: [test1, test2 (face: 2)]
/// Expect: [test1, test2 (face: 3)]
Future<void> _update() async {
  final account = util.buildAccount();
  final c = DiContainer.late();
  c.sqliteDb = util.buildTestDb();
  addTearDown(() => c.sqliteDb.close());
  c.personRepoRemote = MockPersonMemoryRepo({
    account.id: [
      const Person(name: "test1", thumbFaceId: 1, count: 1),
      const Person(name: "test2", thumbFaceId: 3, count: 10),
    ],
  });
  c.personRepoLocal = PersonRepo(PersonSqliteDbDataSource(c.sqliteDb));
  await c.sqliteDb.transaction(() async {
    await c.sqliteDb.insertAccountOf(account);
    await c.sqliteDb.batch((batch) {
      batch.insertAll(c.sqliteDb.persons, [
        sql.PersonsCompanion.insert(
            account: 1, name: "test1", thumbFaceId: 1, count: 1),
        sql.PersonsCompanion.insert(
            account: 1, name: "test2", thumbFaceId: 2, count: 10),
      ]);
    });
  });

  await SyncPerson(c)(account);
  expect(
    await _listSqliteDbPersons(c.sqliteDb),
    {
      account.userId.toCaseInsensitiveString(): {
        const Person(name: "test1", thumbFaceId: 1, count: 1),
        const Person(name: "test2", thumbFaceId: 3, count: 10),
      },
    },
  );
}

Future<Map<String, Set<Person>>> _listSqliteDbPersons(sql.SqliteDb db) async {
  final query = db.select(db.persons).join([
    sql.innerJoin(db.accounts, db.accounts.rowId.equalsExp(db.persons.account)),
  ]);
  final result = await query
      .map((r) => Tuple2(r.readTable(db.accounts), r.readTable(db.persons)))
      .get();
  final product = <String, Set<Person>>{};
  for (final r in result) {
    (product[r.item1.userId] ??= {})
        .add(SqlitePersonConverter.fromSql(r.item2));
  }
  return product;
}
