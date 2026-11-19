import 'dart:math';

import '../schedule.dart';
import '../units.dart';
import 'planner_models.dart';

/// Pure, seeded weighted-random meal planner.
///
/// Hard constraints (never broken): meal-type suitability, fixed/locked meals.
/// Soft preferences (weighted or relaxed step by step, and reported):
/// cooldown, same-day repeats, max consecutive days, category targets.
PlanResult generatePlan(PlannerInput input, {required int seed}) {
  final cfg = input.config;
  final rng = Random(seed);
  final notes = <PlanNote>[];
  final recipes = [...input.recipes]..sort((a, b) => a.id.compareTo(b.id));
  final byId = {for (final r in recipes) r.id: r};

  if (recipes.isEmpty) {
    return PlanResult(const [], [
      const PlanNote(PlanNoteKind.noRecipes, 'There are no recipes to plan with.'),
    ]);
  }

  String key(DateTime d, MealSlot s) => '${dateKey(d)}#${s.index}';
  final start = DateTime(cfg.start.year, cfg.start.month, cfg.start.day);
  final end = DateTime(cfg.end.year, cfg.end.month, cfg.end.day);

  // ---- state -------------------------------------------------------------
  final lastCooked = <int, DateTime>{...input.lastCooked};
  final eatenByDate = <String, List<int>>{}; // dateKey -> recipe ids eaten
  final weekCounts = <String, Map<int, int>>{}; // weekKey -> category -> count
  final occupied = <String>{};
  for (final f in input.fixed) {
    occupied.add(key(f.date, f.slot));
  }

  String weekKeyOf(DateTime d) =>
      dateKey(addDays(d, -((d.weekday - cfg.weekStartsOn + 7) % 7)));

  /// The category target a meal counts toward: the target category with the
  /// largest remaining deficit. A meal never counts toward more than one
  /// category, so Seafood+Rice is not double counted.
  int? primaryCategory(PlannerRecipe r, DateTime date) {
    final counts = weekCounts[weekKeyOf(date)] ?? const {};
    int? best;
    var bestDeficit = -1 << 30;
    for (final c in r.categoryIds.toList()..sort()) {
      final target = cfg.categoryTargetsPerWeek[c];
      if (target == null || target <= 0) continue;
      final deficit = target - (counts[c] ?? 0);
      if (deficit > bestDeficit) {
        bestDeficit = deficit;
        best = c;
      }
    }
    return best;
  }

  void record(PlannerRecipe r, DateTime date, {required bool fresh}) {
    (eatenByDate[dateKey(date)] ??= []).add(r.id);
    final c = primaryCategory(r, date);
    if (c != null) {
      final w = weekCounts[weekKeyOf(date)] ??= {};
      w[c] = (w[c] ?? 0) + 1;
    }
    if (fresh) {
      final prev = lastCooked[r.id];
      if (prev == null || date.isAfter(prev)) lastCooked[r.id] = date;
    }
  }

  // Seed state from fixed meals, chronologically (so deficits are consistent).
  final fixedSorted = [...input.fixed]..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.slot.index.compareTo(b.slot.index);
    });
  for (final f in fixedSorted) {
    final r = f.recipeId == null ? null : byId[f.recipeId];
    if (r != null) record(r, f.date, fresh: !f.isLeftover);
  }

  // ---- slots to fill -----------------------------------------------------
  final slots = <({DateTime date, MealSlot slot})>[];
  for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
    final type = input.dayTypes[dateKey(d)] ?? DayType.free;
    for (final s in slotsFor(type)) {
      if (!occupied.contains(key(d, s))) slots.add((date: d, slot: s));
    }
  }
  final free = {for (final s in slots) key(s.date, s.slot)};

  final meals = <PlannedMeal>[];
  final reserved = <String, PlannedMeal>{}; // slot key -> leftover to place
  var nextCookingKey = 1;

  bool leftoverSlotOk(DateTime d, MealSlot s, PlannerRecipe r) {
    final k = key(d, s);
    if (!free.contains(k) || reserved.containsKey(k)) return false;
    if (!r.slots.contains(s)) return false;
    final type = input.dayTypes[dateKey(d)] ?? DayType.free;
    if (type == DayType.office && !cfg.leftoversOnOfficeDays) return false;
    return true;
  }

  // Leftovers from batches that are already cooked: earliest suitable slots.
  for (final b in input.openBatches) {
    final r = byId[b.recipeId];
    if (r == null) continue;
    var left = b.remaining;
    for (final s in slots) {
      if (left <= 0) break;
      if (daysBetween(b.cookedOn, s.date) > cfg.leftoverMaxAgeDays) break;
      if (daysBetween(b.cookedOn, s.date) < 0) continue;
      if (!leftoverSlotOk(s.date, s.slot, r)) continue;
      reserved[key(s.date, s.slot)] = PlannedMeal(
          date: s.date, slot: s.slot, recipeId: r.id, isLeftover: true, existingBatchId: b.batchId);
      left--;
    }
  }

  // ---- helpers for choosing ---------------------------------------------
  int runLength(int recipeId, DateTime date) {
    var n = 0;
    var d = addDays(date, -1);
    while ((eatenByDate[dateKey(d)] ?? const []).contains(recipeId)) {
      n++;
      d = addDays(d, -1);
    }
    return n;
  }

  double weightOf(PlannerRecipe r, DateTime date) {
    var w = 1.0;
    if (r.isFavorite) w *= max(1.0, cfg.favoriteWeight);
    final last = lastCooked[r.id];
    final horizon = max(30, cfg.cooldownDays * 2).toDouble();
    final recency = last == null ? 1.0 : min(1.0, max(0, daysBetween(last, date)) / horizon);
    w *= 1 + max(0.0, cfg.discoveryWeight) * recency;

    // Category balancing (soft): boost what the week still needs.
    final counts = weekCounts[weekKeyOf(date)] ?? const {};
    var bestDeficitRatio = -2.0;
    var hasTarget = false;
    for (final c in r.categoryIds) {
      final t = cfg.categoryTargetsPerWeek[c];
      if (t == null || t <= 0) continue;
      hasTarget = true;
      bestDeficitRatio = max(bestDeficitRatio, (t - (counts[c] ?? 0)) / t);
    }
    if (hasTarget) {
      w *= bestDeficitRatio > 0 ? 1 + 3 * bestDeficitRatio : 0.35;
    } else if (cfg.categoryTargetsPerWeek.isNotEmpty) {
      // Untargeted recipes stay neutral but must not crowd out needed categories.
      w *= 0.9;
    }
    return w;
  }

  /// Relaxation ladder; returns candidates and the level that produced them.
  ({List<PlannerRecipe> list, int level}) candidatesFor(DateTime date, MealSlot slot) {
    final suitable = recipes.where((r) => r.slots.contains(slot)).toList();
    if (suitable.isEmpty) return (list: const [], level: 0);
    final dk = dateKey(date);
    bool cooled(PlannerRecipe r, int cooldown) {
      final last = lastCooked[r.id];
      return last == null || daysBetween(last, date) >= cooldown;
    }

    bool notToday(PlannerRecipe r) => !(eatenByDate[dk] ?? const []).contains(r.id);
    bool runOk(PlannerRecipe r) => runLength(r.id, date) < max(1, cfg.maxConsecutiveDays);

    final steps = <bool Function(PlannerRecipe)>[
      (r) => cooled(r, cfg.cooldownDays) && notToday(r) && runOk(r),
      (r) => cooled(r, cfg.cooldownDays ~/ 2) && notToday(r) && runOk(r),
      (r) => notToday(r) && runOk(r),
      (r) => runOk(r),
      (r) => true,
    ];
    for (var i = 0; i < steps.length; i++) {
      final list = suitable.where(steps[i]).toList();
      if (list.isNotEmpty) return (list: list, level: i);
    }
    return (list: suitable, level: steps.length - 1);
  }

  PlannerRecipe pick(List<PlannerRecipe> list, DateTime date) {
    final ws = [for (final r in list) weightOf(r, date)];
    final total = ws.fold<double>(0, (a, b) => a + b);
    var x = rng.nextDouble() * total;
    for (var i = 0; i < list.length; i++) {
      x -= ws[i];
      if (x <= 0) return list[i];
    }
    return list.last;
  }

  String slotName(MealSlot s) => s == MealSlot.marenda ? 'Marenda' : 'Lunch';

  // ---- main loop ---------------------------------------------------------
  for (final s in slots) {
    final k = key(s.date, s.slot);

    final left = reserved[k];
    if (left != null) {
      meals.add(left);
      record(byId[left.recipeId]!, s.date, fresh: false);
      continue;
    }

    final cand = candidatesFor(s.date, s.slot);
    if (cand.list.isEmpty) {
      notes.add(PlanNote(
          PlanNoteKind.noSuitableRecipe,
          'No recipe is marked suitable for ${slotName(s.slot)}, so ${dateKey(s.date)} '
          '${slotName(s.slot)} was left empty.',
          date: s.date,
          slot: s.slot));
      continue;
    }
    if (cand.level > 0) {
      final kind = cand.level <= 2 ? PlanNoteKind.cooldownRelaxed : PlanNoteKind.repeatRelaxed;
      final what = switch (cand.level) {
        1 => 'the cooldown was shortened',
        2 => 'the cooldown was ignored',
        3 => 'a recipe was repeated on the same day',
        _ => 'the maximum consecutive days limit was exceeded',
      };
      notes.add(PlanNote(
          kind,
          'Not enough recipes for ${dateKey(s.date)} ${slotName(s.slot)}: $what.',
          date: s.date,
          slot: s.slot));
    }

    final r = pick(cand.list, s.date);

    // Decide on multi-day cooking and reserve the following slots.
    int? cookingKey;
    final maxDays = min(cfg.multiDayMaxDays, r.servings.floor());
    if (cfg.multiDayChance > 0 && maxDays >= 2 && rng.nextDouble() < cfg.multiDayChance) {
      final key0 = nextCookingKey;
      final found = <PlannedMeal>[];
      for (var k2 = 1; k2 <= 3 && found.length < maxDays - 1; k2++) {
        final d = addDays(s.date, k2);
        if (d.isAfter(end)) break;
        if (leftoverSlotOk(d, s.slot, r)) {
          found.add(PlannedMeal(
              date: d, slot: s.slot, recipeId: r.id, isLeftover: true, cookingKey: key0));
        }
      }
      if (found.isNotEmpty) {
        cookingKey = key0;
        nextCookingKey++;
        for (final f in found) {
          reserved[key(f.date, f.slot)] = f;
        }
      }
    }

    meals.add(PlannedMeal(
        date: s.date, slot: s.slot, recipeId: r.id, cookingKey: cookingKey));
    record(r, s.date, fresh: true);
  }

  // ---- report on category targets ---------------------------------------
  if (cfg.categoryTargetsPerWeek.isNotEmpty) {
    final weeks = <String, int>{}; // weekKey -> days of the range inside it
    for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
      weeks[weekKeyOf(d)] = (weeks[weekKeyOf(d)] ?? 0) + 1;
    }
    for (final e in weeks.entries) {
      if (e.value < 4) continue; // too short to judge a weekly target
      final counts = weekCounts[e.key] ?? const {};
      for (final t in cfg.categoryTargetsPerWeek.entries) {
        if (t.value <= 0) continue;
        final got = counts[t.key] ?? 0;
        if (got < t.value) {
          notes.add(PlanNote(
              PlanNoteKind.categoryShortfall,
              'Week of ${e.key}: ${input.categoryNames[t.key] ?? 'Category ${t.key}'} has $got of ${t.value} planned meals '
              '(not enough suitable recipes, or other limits got in the way).'));
        }
      }
    }
  }

  return PlanResult(meals, notes);
}

