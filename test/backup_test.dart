import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/data/backup_service.dart';
import 'package:meal_planner/data/db/database.dart';
import 'package:meal_planner/data/recipe_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String dbPath;
  late AppDatabase db;

  AppDatabase open() => AppDatabase.forTesting(NativeDatabase(File(dbPath)));
  BackupService service() =>
      BackupService(db: db, docsDir: root.path, dbFile: dbPath);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mp_backup_test');
    dbPath = p.join(root.path, 'meal_planner.sqlite');
    db = open();
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    await root.delete(recursive: true);
  });

  test('backup then restore brings back data and images', () async {
    final repo = RecipeRepository(db);
    await repo.save(RecipeDraft(name: 'Bolognese', servings: 4, kcalOverride: 700, imagePath: 'images/a.jpg'));
    await Directory(p.join(root.path, 'images')).create();
    await File(p.join(root.path, 'images', 'a.jpg')).writeAsBytes([1, 2, 3, 4]);

    final zip = await service().createBackup();
    expect(await zip.exists(), isTrue);

    // Change everything after the backup.
    await (db.delete(db.recipes)).go();
    await repo.save(RecipeDraft(name: 'Something new'));
    await File(p.join(root.path, 'images', 'a.jpg')).delete();
    await File(p.join(root.path, 'images', 'b.jpg')).writeAsBytes([9]);

    await service().restore(zip, closeDb: () => db.close());
    db = open();

    final recipes = await RecipeRepository(db).loadAll();
    expect(recipes.map((r) => r.recipe.name), ['Bolognese']);
    expect(recipes.single.perServing!.kcal, 700);
    expect(await File(p.join(root.path, 'images', 'a.jpg')).readAsBytes(), [1, 2, 3, 4]);
    expect(await File(p.join(root.path, 'images', 'b.jpg')).exists(), isFalse);
    // A safety backup of the pre-restore state exists.
    final safety = Directory(p.join(root.path, 'backups')).listSync().map((e) => p.basename(e.path));
    expect(safety.any((n) => n.startsWith('pre-restore-')), isTrue);
    // No temp leftovers.
    expect(await Directory(p.join(root.path, 'restore_tmp')).exists(), isFalse);
  });

  test('seeded data (categories, schedule) survives a round trip', () async {
    final zip = await service().createBackup();
    await service().restore(zip, closeDb: () => db.close());
    db = open();
    expect((await db.select(db.categories).get()).length, AppDatabase.defaultCategories.length);
    expect((await db.select(db.weeklySchedule).get()).length, 7);
  });

  test('rejects a backup from a newer schema without touching data', () async {
    final repo = RecipeRepository(db);
    await repo.save(RecipeDraft(name: 'Keep me'));
    final bad = File(p.join(root.path, 'newer.zip'));
    final enc = ZipFileEncoder()..create(bad.path);
    enc.addArchiveFile(ArchiveFile.string(
        'manifest.json', jsonEncode({'app': 'meal_planner', 'schemaVersion': db.schemaVersion + 1})));
    enc.addArchiveFile(ArchiveFile.string('db.sqlite', 'x'));
    await enc.close();

    await expectLater(service().restore(bad, closeDb: () => db.close()),
        throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('newer'))));
    expect((await RecipeRepository(db).loadAll()).single.recipe.name, 'Keep me');
  });

  test('rejects files that are not Meal Planner backups', () async {
    final wrong = File(p.join(root.path, 'other.zip'));
    final enc = ZipFileEncoder()..create(wrong.path);
    enc.addArchiveFile(ArchiveFile.string('manifest.json', jsonEncode({'app': 'something_else', 'schemaVersion': 1})));
    enc.addArchiveFile(ArchiveFile.string('db.sqlite', 'x'));
    await enc.close();
    await expectLater(service().restore(wrong, closeDb: () => db.close()), throwsA(isA<BackupException>()));

    final garbage = File(p.join(root.path, 'garbage.zip'))..writeAsStringSync('not a zip');
    await expectLater(service().restore(garbage, closeDb: () => db.close()), throwsA(isA<BackupException>()));
  });

  test('JSON export contains every table', () async {
    await RecipeRepository(db).save(RecipeDraft(name: 'Soup'));
    final json = jsonDecode(await service().exportJson()) as Map<String, dynamic>;
    final tables = json['tables'] as Map<String, dynamic>;
    expect(tables.keys, containsAll(['recipes', 'ingredients', 'categories', 'meal_entries', 'app_settings']));
    expect((tables['recipes'] as List).single['name'], 'Soup');
  });
}
