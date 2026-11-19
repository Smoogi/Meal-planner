# Meal Planner

A personal, fully offline meal planning, recipe management and calorie tracking app built with Flutter (Android first). No accounts, no cloud, no tracking.

## Features (planned)

- **Recipes** – personal cookbook with categories, ingredients, nutrition and images
- **Planner** – smart, seeded weighted-random meal generation with cooldowns, favorites, variety and leftovers
- **Calendar** – WFH / Office / Free day types, weekly schedule with per-date overrides, meal history
- **Calories** – "Recorded Calories" tracking with recipe, manual or ingredient logging, and statistics
- **Settings** – planner/calendar/calories preferences, themes, full backup and restore

## Status

Phase 1 (foundation) is done: app shell with five tabs, Material 3 light/dark themes, database schema, signing and release tooling. Feature tabs are placeholders until their phases land.

## Install

Download the latest `meal-planner-X.Y.Z.apk` from the [Releases](https://github.com/Smoogi/Meal-planner/releases) page and check it against the `.sha256` file.

## Development

Requirements: Flutter (stable), Android Studio (SDK + bundled JDK).

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

Release (Windows PowerShell): `.\scripts\release.ps1 -Version X.Y.Z`. See [CLAUDE.md](CLAUDE.md) for architecture, signing and release details.
