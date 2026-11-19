# Meal Planner

A personal, fully offline meal planning, recipe management and calorie tracking app built with Flutter (Android first). No accounts, no cloud, no tracking.

## Features

- **Recipes** – personal cookbook: multiple categories, Marenda/Lunch suitability, ingredients with units (g, kg, ml, l, pieces), automatic nutrition from ingredients, manual overrides, favorites, local images, duplicate/delete, search and filters.
- **Planner** – seeded weighted-random meal generator: cooldowns, favorite and discovery weighting, weekly category targets (soft, no double counting), multi-day cooking with leftovers, locked meals/days, manual replacement, and a report explaining any preference it had to relax.
- **Calendar** – monthly view with WFH / Office / Free day types, a default weekly schedule with per-date overrides, planned/prepared/consumed/skipped meals and recorded calories.
- **Calories** – "Recorded Calories" for the day (not assumed to be your full intake), optional target, macros, logging by recipe, quick entry (e.g. an office lunch) or ingredients, daily/weekly/monthly statistics.
- **Settings** – planner and calendar preferences, calorie target, light/dark/system theme, full backup (database + images), restore, and JSON export.

Meals you log keep the nutrition values they had at the time, so editing or deleting a recipe never rewrites your history.

## Install

Download the latest `meal-planner-X.Y.Z.apk` from the [Releases](https://github.com/Smoogi/Meal-planner/releases) page and verify it against the `.sha256` file.

## Development

Requirements: Flutter (stable), Android Studio (Android SDK + bundled JDK), Windows PowerShell for the release script.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after changing database tables
flutter analyze
flutter test
flutter run
```

The Drift-generated `lib/data/db/database.g.dart` is committed.

### Releasing

```
.\scripts\release.ps1 -Version 1.0.0 -DryRun   # validate everything first
.\scripts\release.ps1 -Version 1.0.0
```

This needs a release keystore configured in `android/key.properties` (never committed). See [CLAUDE.md](CLAUDE.md) for the architecture, signing setup, key backup advice and Windows/PowerShell notes.

## Data and privacy

Everything is stored on the device (SQLite + image files). The only way data leaves the phone is when you export a backup yourself.
