import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show DataClass;
import 'package:path/path.dart' as p;

import 'db/database.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Full local backup: one zip with `manifest.json`, `db.sqlite` (a consistent
/// snapshot) and `images/`. Restore replaces the database and images.
class BackupService {
  BackupService({required this.db, required this.docsDir, required this.dbFile});
  final AppDatabase db;

  /// Directory holding `images/` and the `backups/` folder.
  final String docsDir;

  /// Path of the live SQLite file.
  final String dbFile;

  static const appId = 'meal_planner';

  String get imagesDir => p.join(docsDir, 'images');
  String get backupsDir => p.join(docsDir, 'backups');

  Future<File> createBackup({String? fileName, String? outDir}) async {
    final dir = Directory(outDir ?? backupsDir);
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final out = File(p.join(dir.path, fileName ?? 'meal-planner-backup-$stamp.zip'));

    // Consistent snapshot of the live database (safe while the app is using it).
    final snapshot = File(p.join(docsDir, 'snapshot_${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await db.customStatement("VACUUM INTO '${snapshot.path.replaceAll("'", "''")}'");

      final enc = ZipFileEncoder()..create(out.path);
      enc.addArchiveFile(ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'app': appId,
            'schemaVersion': db.schemaVersion,
            'createdAt': DateTime.now().toIso8601String(),
          })));
      await enc.addFile(snapshot, 'db.sqlite');
      final images = Directory(imagesDir);
      if (await images.exists()) {
        await for (final f in images.list(recursive: true, followLinks: false)) {
          if (f is File) {
            await enc.addFile(f, p.join('images', p.relative(f.path, from: imagesDir)).replaceAll('\\', '/'));
          }
        }
      }
      await enc.close();
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
    return out;
  }

  /// Validates and restores [zip]. [closeDb] must close every connection to the
  /// live database; the caller reopens it afterwards (migrations then bring an
  /// older backup up to date). A safety backup of the current data is written first.
  Future<void> restore(File zip, {required Future<void> Function() closeDb}) async {
    if (!await zip.exists()) throw BackupException('Backup file not found.');
    final tmp = Directory(p.join(docsDir, 'restore_tmp'));
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);

    try {
      try {
        final input = InputFileStream(zip.path);
        final archive = ZipDecoder().decodeStream(input);
        await extractArchiveToDisk(archive, tmp.path);
        await input.close();
      } catch (e) {
        throw BackupException('This file is not a valid backup archive.');
      }

      final manifestFile = File(p.join(tmp.path, 'manifest.json'));
      final snapshot = File(p.join(tmp.path, 'db.sqlite'));
      if (!await manifestFile.exists() || !await snapshot.exists()) {
        throw BackupException('This is not a Meal Planner backup (manifest or database missing).');
      }
      final Map<String, dynamic> manifest;
      try {
        manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        throw BackupException('The backup manifest is unreadable.');
      }
      if (manifest['app'] != appId) throw BackupException('This is not a Meal Planner backup.');
      final v = manifest['schemaVersion'];
      if (v is! int) throw BackupException('The backup has no schema version.');
      if (v > db.schemaVersion) {
        throw BackupException(
            'This backup was made by a newer version of the app (schema $v). Update the app first.');
      }

      // Keep a way back.
      await createBackup(fileName: 'pre-restore-${DateTime.now().millisecondsSinceEpoch}.zip');

      await closeDb();

      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('$dbFile$suffix');
        if (await f.exists()) await f.delete();
      }
      await snapshot.copy(dbFile);

      final images = Directory(imagesDir);
      if (await images.exists()) await images.delete(recursive: true);
      final restored = Directory(p.join(tmp.path, 'images'));
      if (await restored.exists()) {
        await _copyDir(restored, images);
      }
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(recursive: true, followLinks: false)) {
      final rel = p.relative(e.path, from: from.path);
      if (e is Directory) {
        await Directory(p.join(to.path, rel)).create(recursive: true);
      } else if (e is File) {
        await Directory(p.dirname(p.join(to.path, rel))).create(recursive: true);
        await e.copy(p.join(to.path, rel));
      }
    }
  }

  /// Human-readable export of every table (not restorable; use the zip for that).
  Future<String> exportJson() async {
    final tables = <String, dynamic>{};
    for (final t in db.allTables) {
      final rows = await db.select(t).get();
      tables[t.actualTableName] = [for (final r in rows) (r as DataClass).toJson()];
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'meal_planner_json',
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }
}
