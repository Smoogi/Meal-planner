
import 'db/database.dart';

/// All setting keys in one place. Values are stored as strings.
class SettingKeys {
  static const firstDayOfWeek = 'calendar.firstDayOfWeek'; // 1=Mon..7=Sun
  static const calorieTarget = 'calories.target'; // optional
  static const themeMode = 'appearance.themeMode'; // system|light|dark
  static const cooldownDays = 'planner.cooldownDays';
  static const favoriteWeight = 'planner.favoriteWeight';
  static const discoveryWeight = 'planner.discoveryWeight';
  static const maxConsecutive = 'planner.maxConsecutive';
  static const multiDayChance = 'planner.multiDayChance'; // 0..1
  static const multiDayMaxDays = 'planner.multiDayMaxDays';
  static const leftoversOnOffice = 'planner.leftoversOnOffice';
  static const categoryTargets = 'planner.categoryTargets'; // JSON {categoryId: perWeek}
}

class SettingsRepository {
  SettingsRepository(this.db);
  final AppDatabase db;

  Stream<Map<String, String>> watchAll() => db
      .select(db.appSettings)
      .watch()
      .map((rows) => {for (final r in rows) r.key: r.value});

  Future<String?> get(String key) async =>
      (await (db.select(db.appSettings)..where((s) => s.key.equals(key))).getSingleOrNull())
          ?.value;

  Future<void> set(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.appSettings)..where((s) => s.key.equals(key))).go();
    } else {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
    }
  }
}


