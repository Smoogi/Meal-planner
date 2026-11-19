import 'units.dart';

/// Local calendar date key 'yyyy-MM-dd' (no timezone/DST issues).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Adds whole days using calendar arithmetic (safe across DST changes).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

/// Default meal slots for a day type.
List<MealSlot> slotsFor(DayType t) => switch (t) {
      DayType.wfh || DayType.free => const [MealSlot.marenda, MealSlot.lunch],
      DayType.office => const [MealSlot.lunch],
    };

/// Effective day type: a per-date override wins over the weekly default.
/// [weekly] is keyed by weekday 1 (Mon) .. 7 (Sun).
DayType effectiveDayType(
  DateTime date,
  Map<int, DayType> weekly,
  Map<String, DayType> overrides,
) =>
    overrides[dateKey(date)] ?? weekly[date.weekday] ?? DayType.free;
