import 'dart:convert';

import '../domain/planner/planner_models.dart';
import 'settings_repository.dart';

/// Persisted planner preferences (defaults apply when nothing is stored).
class PlannerSettings {
  const PlannerSettings({
    this.cooldownDays = 14,
    this.favoriteWeight = 2.0,
    this.discoveryWeight = 1.0,
    this.maxConsecutiveDays = 2,
    this.multiDayChance = 0.25,
    this.multiDayMaxDays = 2,
    this.leftoversOnOfficeDays = false,
    this.categoryTargets = const {},
  });

  final int cooldownDays;
  final double favoriteWeight;
  final double discoveryWeight;
  final int maxConsecutiveDays;
  final double multiDayChance;
  final int multiDayMaxDays;
  final bool leftoversOnOfficeDays;
  final Map<int, int> categoryTargets;

  PlannerSettings copyWith({
    int? cooldownDays,
    double? favoriteWeight,
    double? discoveryWeight,
    int? maxConsecutiveDays,
    double? multiDayChance,
    int? multiDayMaxDays,
    bool? leftoversOnOfficeDays,
    Map<int, int>? categoryTargets,
  }) =>
      PlannerSettings(
        cooldownDays: cooldownDays ?? this.cooldownDays,
        favoriteWeight: favoriteWeight ?? this.favoriteWeight,
        discoveryWeight: discoveryWeight ?? this.discoveryWeight,
        maxConsecutiveDays: maxConsecutiveDays ?? this.maxConsecutiveDays,
        multiDayChance: multiDayChance ?? this.multiDayChance,
        multiDayMaxDays: multiDayMaxDays ?? this.multiDayMaxDays,
        leftoversOnOfficeDays: leftoversOnOfficeDays ?? this.leftoversOnOfficeDays,
        categoryTargets: categoryTargets ?? this.categoryTargets,
      );

  factory PlannerSettings.fromMap(Map<String, String> m) {
    const d = PlannerSettings();
    Map<int, int> targets = {};
    try {
      final raw = m[SettingKeys.categoryTargets];
      if (raw != null) {
        targets = {
          for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
            int.parse(e.key): (e.value as num).toInt()
        };
      }
    } catch (_) {}
    return PlannerSettings(
      cooldownDays: int.tryParse(m[SettingKeys.cooldownDays] ?? '') ?? d.cooldownDays,
      favoriteWeight: double.tryParse(m[SettingKeys.favoriteWeight] ?? '') ?? d.favoriteWeight,
      discoveryWeight: double.tryParse(m[SettingKeys.discoveryWeight] ?? '') ?? d.discoveryWeight,
      maxConsecutiveDays: int.tryParse(m[SettingKeys.maxConsecutive] ?? '') ?? d.maxConsecutiveDays,
      multiDayChance: double.tryParse(m[SettingKeys.multiDayChance] ?? '') ?? d.multiDayChance,
      multiDayMaxDays: int.tryParse(m[SettingKeys.multiDayMaxDays] ?? '') ?? d.multiDayMaxDays,
      leftoversOnOfficeDays: m[SettingKeys.leftoversOnOffice] == 'true',
      categoryTargets: targets,
    );
  }

  Future<void> save(SettingsRepository repo) async {
    await repo.set(SettingKeys.cooldownDays, '$cooldownDays');
    await repo.set(SettingKeys.favoriteWeight, '$favoriteWeight');
    await repo.set(SettingKeys.discoveryWeight, '$discoveryWeight');
    await repo.set(SettingKeys.maxConsecutive, '$maxConsecutiveDays');
    await repo.set(SettingKeys.multiDayChance, '$multiDayChance');
    await repo.set(SettingKeys.multiDayMaxDays, '$multiDayMaxDays');
    await repo.set(SettingKeys.leftoversOnOffice, '$leftoversOnOfficeDays');
    await repo.set(SettingKeys.categoryTargets,
        jsonEncode({for (final e in categoryTargets.entries) '${e.key}': e.value}));
  }

  PlannerConfig toConfig(DateTime start, DateTime end, {int weekStartsOn = DateTime.monday}) =>
      PlannerConfig(
        start: start,
        end: end,
        cooldownDays: cooldownDays,
        favoriteWeight: favoriteWeight,
        discoveryWeight: discoveryWeight,
        maxConsecutiveDays: maxConsecutiveDays,
        multiDayChance: multiDayChance,
        multiDayMaxDays: multiDayMaxDays,
        leftoversOnOfficeDays: leftoversOnOfficeDays,
        categoryTargetsPerWeek: {
          for (final e in categoryTargets.entries)
            if (e.value > 0) e.key: e.value
        },
        weekStartsOn: weekStartsOn,
      );
}
