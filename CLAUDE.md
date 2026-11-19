# CLAUDE.md â€” Smoogi Meal Planner

Personal, offline-first meal planning / recipe / calorie tracking app (Flutter, Android-first).
Single user, no accounts, cloud, analytics or ads. All UI text in English. Material 3, light/dark.
Update this file whenever an architectural or release-process decision changes.

## Workflow rules
- Work in phases; get approval before starting a new phase. Avoid unnecessary dependencies.
- Phases: 1 Foundation, 2 Recipes, 3 Calendar, 4 Smart Planner, 5 Calories, 6 Settings/Backup, 7 Polish/Release.
- Current status: **Phases 1-6 complete** (foundation, recipes, calendar, Smart Planner, calories, settings, backup/restore). Remaining: Phase 7 (UI polish on a real device, performance check, first signed release).

## Architecture
- Layers: `lib/data` (Drift DB, DAOs/repos) â†’ `lib/domain` (pure Dart: nutrition, units, planner engine; no Flutter imports) â†’ `lib/features/<tab>` (UI + Riverpod providers). `lib/app` = shell, theme, providers.
- State: `flutter_riverpod` (v3, use `Notifier`, not `StateProvider`). Navigation: `go_router` StatefulShellRoute + M3 `NavigationBar` (Recipes, Planner, Calendar, Calories, Settings).
- DB: Drift/SQLite (`lib/data/db/tables.dart`, `database.dart`; generated `database.g.dart` IS committed). After editing tables run `dart run build_runner build --delete-conflicting-outputs`, bump `schemaVersion`, add an `onUpgrade` step.
- Dates are stored as local `yyyy-MM-dd` text (no timezone/DST bugs).

## Key decisions
- **`meal_entries` is the single source of truth** for Planner, Calendar and Calories. States: planned/prepared/consumed/skipped. Planned never counts as consumed calories.
- **Nutrition snapshots** are stored on the entry (kcal/protein/carbs/fat, title) so recipe edits never rewrite history. Recipe deletion sets `recipe_id` NULL (snapshot stays).
- Leftovers = entries with `batch_id` + `is_leftover`; they do not count as a new preparation or reset cooldown. Remaining portions are derived from `prep_batches.portions_made` minus linked entries.
- Never assume ml == g or a fixed weight per piece: use ingredient `gramsPerMl` / `gramsPerPiece`; if missing, flag recipe nutrition as incomplete.
- Calories UI says "Recorded Calories" (partial tracking: mostly Marenda + Lunch).
- Planner = pure seeded weighted-random engine with relaxation ladder and a report of relaxed preferences.
- Backup = zip of DB + images + manifest (schema version). Image paths stored relative.

## Repository / Git
- Repo: https://github.com/Smoogi/Meal-planner (owner Smoogi), branch `main`. Local: `C:\Meal-planner`.
- Git identity (local config): name `dev`, email `dev@local`. **No Claude co-author lines in commits.**
- Never force-push or overwrite remote history.

## GitHub CLI (Windows)
- `gh` may not be on PATH. In PowerShell: `$env:PATH = "$env:LOCALAPPDATA\Programs\gh\bin;$env:PATH"`
- Check with `gh auth status` (authenticated as Smoogi, credentials in Windows credential manager). If expired, ask the user to run `gh auth login`. Never ask for or store passwords/tokens.

## Build & test
```
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
- Android Studio JBR may be needed: `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr` (release script auto-detects).
- Application ID: `com.smoogi.mealplanner` (final, never change). Flutter project, not a native Android project: do not use native Gradle habits.

## Versioning
- Single source: `version: X.Y.Z+N` in `pubspec.yaml` (X.Y.Z = versionName, N = versionCode). Every release must increment N; the release script does it.

## Android signing
- Release key is private and NEVER committed. `android/key.properties` (gitignored) holds `storePassword`, `keyPassword`, `keyAlias`, `storeFile` (path to a keystore outside the repo).
- `android/app/build.gradle.kts` signs release with it and never falls back to the debug key.
- **Status: no Meal Planner keystore exists yet.** Do not generate or replace one without user approval. (A `C:\Users\Anon\smoogi-signing\smoogi-release.jks` exists, apparently for another project: do not reuse unless the user says so.)
- The same key must be used for all future updates; the user must back up the keystore and passwords in at least two secure places (password manager + offline copy). Losing it means users cannot upgrade in place.

## Releasing
`.\scripts\release.ps1 -Version X.Y.Z` (add `-DryRun` to validate only). It checks clean tree on `main`, remote, gh auth, toolchain, signing, runs analyze + tests, bumps pubspec, builds the signed APK, writes `release-out/meal-planner-X.Y.Z.apk` + `.sha256` + notes, asks for typed confirmation, commits only `pubspec.yaml`, pushes `main`, runs `gh release create vX.Y.Z ... --repo Smoogi/Meal-planner`, then verifies the release on GitHub. It refuses if the tag/release exists. Never report success unless the script printed SUCCESS.

## Windows / PowerShell pitfalls
- Git/Gradle/Flutter write progress to stderr; PowerShell 5.1 may show red NativeCommandError. Judge success by `$LASTEXITCODE` (and e.g. `main -> main` in push output), not stderr.
- Avoid `2>&1` on native exes in PS 5.1 when checking `$?`.
- No `&&` in PowerShell 5.1; use `;` with `if ($?)`.

## Testing requirements
Unit tests for: nutrition calculation & unit conversion, planner constraints (cooldown, suitability, category balancing, relaxation, seeded determinism), schedule overrides, leftovers/batches, historical snapshots, backup/restore. Run `flutter analyze` and `flutter test` before every commit.


## Testing pitfalls
- Drift/real async I/O does not run inside widget-test fake-async: widget tests must stub data providers (see test/widget_test.dart); DB logic is tested with AppDatabase.forTesting(NativeDatabase.memory()) in plain tests.
- A hung test can leave lutter_tester.exe holding uild\native_assets\windows\sqlite3.dll; stop that process (only) and rerun.



## Planner implementation notes
- Engine: `lib/domain/planner/planner_engine.dart` (pure, `generatePlan(input, seed:)`). Persistence glue: `lib/data/planner_service.dart`. Preferences: `lib/data/planner_settings.dart` (stored in `app_settings`).
- Hard: meal-type suitability, locked/non-planned entries. Soft (relaxed stepwise, always reported in `PlanResult.notes`): cooldown, same-day repeat, max consecutive days, category targets.
- A meal counts toward exactly ONE target category (largest deficit) to avoid double counting.
- Regenerate deletes only unlocked + planned entries in range. Leftovers link to a `prep_batches` row; a batch counts as a *preparation* only once one of its entries is prepared/consumed.
- Open batches (cooked, portions left) are scheduled as leftovers first.



## Backup / restore / settings
- `lib/data/backup_service.dart`: zip = `manifest.json` (app id + schemaVersion) + `db.sqlite` (`VACUUM INTO` snapshot) + `images/`. Restore validates the manifest, rejects newer schemas, writes a `pre-restore-*.zip` safety backup in `<docs>/backups/`, closes the DB, swaps files; the UI then `ref.invalidate(databaseProvider)` so Drift reopens and migrates older backups.
- DB file: `<app documents>/meal_planner.sqlite` (`lib/data/app_paths.dart`); images `<docs>/images/` (DB stores relative paths).
- Settings are key/value strings in `app_settings` (keys in `SettingKeys`); theme, first day of week, calorie target, planner prefs, display toggles. Units are fixed metric/kcal (documented in Settings).

## Open items before the first release
- Create the Meal Planner keystore with the user's approval and write `android/key.properties` (see Android signing).
- Try the app on a real device: image picking, share/restore file picker, calendar density on small screens.
- Then `.\scripts\release.ps1 -Version 1.0.0 -DryRun` followed by the real run.
