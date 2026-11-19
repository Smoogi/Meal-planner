import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/backup_service.dart';
import '../../data/settings_repository.dart';
import '../calendar/weekly_schedule_dialog.dart';
import '../planner/planner_settings_form.dart';
import '../recipes/categories_screen.dart';
import '../recipes/ingredients_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const <String, String>{};
    final repo = ref.watch(settingsRepositoryProvider);
    final firstDow = ref.watch(firstDayOfWeekProvider);
    final theme = settings[SettingKeys.themeMode] ?? 'system';
    final target = settings[SettingKeys.calorieTarget];

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );
    void push(Widget w) =>
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        header('Planner'),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Planner preferences'),
          subtitle: const Text('Cooldown, favorites, discovery, categories, multi-day cooking'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(Scaffold(
            appBar: AppBar(title: const Text('Planner preferences')),
            body: ListView(padding: const EdgeInsets.all(16), children: const [PlannerSettingsForm()]),
          )),
        ),
        header('Calendar'),
        ListTile(
          leading: const Icon(Icons.view_week_outlined),
          title: const Text('Default weekly schedule'),
          subtitle: const Text('WFH / Office / Free day for each weekday'),
          onTap: () => showWeeklyScheduleDialog(context),
        ),
        ListTile(
          leading: const Icon(Icons.calendar_view_week),
          title: const Text('First day of week'),
          trailing: DropdownButton<int>(
            value: firstDow,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Monday')),
              DropdownMenuItem(value: 6, child: Text('Saturday')),
              DropdownMenuItem(value: 7, child: Text('Sunday')),
            ],
            onChanged: (v) => repo.set(SettingKeys.firstDayOfWeek, '${v ?? 1}'),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.local_fire_department_outlined),
          title: const Text('Show recorded kcal in month view'),
          value: settingFlag(settings, SettingKeys.calendarShowKcal),
          onChanged: (v) => repo.set(SettingKeys.calendarShowKcal, '$v'),
        ),
        header('Calories'),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Daily calorie target'),
          subtitle: Text(target == null ? 'Not set (optional)' : '$target kcal'),
          onTap: () => _editTarget(context, repo, target),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.pie_chart_outline),
          title: const Text('Show protein, carbs and fat'),
          value: settingFlag(settings, SettingKeys.showMacros),
          onChanged: (v) => repo.set(SettingKeys.showMacros, '$v'),
        ),
        const ListTile(
          leading: Icon(Icons.straighten),
          title: Text('Units'),
          subtitle: Text('Metric: g, kg, ml, l, pieces. Energy in kcal.'),
        ),
        header('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {theme},
            onSelectionChanged: (s) => repo.set(SettingKeys.themeMode, s.first),
          ),
        ),
        header('Library'),
        ListTile(
          leading: const Icon(Icons.egg_alt_outlined),
          title: const Text('Ingredients'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(const IngredientsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: const Text('Categories'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(const CategoriesScreen()),
        ),
        header('Data management'),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Export complete backup'),
          subtitle: const Text('Database and recipe images in one .zip file'),
          onTap: () => _exportBackup(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Import / restore backup'),
          subtitle: const Text('Replaces all current data (a safety copy is kept)'),
          onTap: () => _restore(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.data_object),
          title: const Text('Export data as JSON'),
          subtitle: const Text('Readable copy of all tables (not for restoring)'),
          onTap: () => _exportJson(context, ref),
        ),
        header('About'),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (_, snap) => ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Meal Planner'),
            subtitle: Text(snap.hasData
                ? 'Version ${snap.data!.version} (${snap.data!.buildNumber}) · works fully offline'
                : 'Works fully offline'),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _editTarget(BuildContext context, SettingsRepository repo, String? current) async {
    final c = TextEditingController(text: current ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily calorie target'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'kcal (leave empty for none)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (r == null) return;
    final v = double.tryParse(r);
    await repo.set(SettingKeys.calorieTarget, v?.round().toString());
  }

  void _toast(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(backupServiceProvider).createBackup();
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)], subject: 'Meal Planner backup', text: 'Meal Planner backup'));
      if (context.mounted) _toast(context, 'Backup created: ${p.basename(file.path)}');
    } catch (e) {
      if (context.mounted) _toast(context, 'Backup failed: $e');
    }
  }

  Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
    try {
      final svc = ref.read(backupServiceProvider);
      final json = await svc.exportJson();
      final f = File(p.join(svc.docsDir, 'meal-planner-export.json'));
      await f.writeAsString(json);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: 'Meal Planner JSON export'));
    } catch (e) {
      if (context.mounted) _toast(context, 'Export failed: $e');
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text('${p.basename(path)}\n\nThis replaces ALL current recipes, meals, settings and images. '
            'A safety copy of the current data is saved first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final svc = ref.read(backupServiceProvider);
      await svc.restore(File(path), closeDb: () => ref.read(databaseProvider).close());
      // Re-open the (restored) database; all providers rebuild from it.
      ref.invalidate(databaseProvider);
      if (context.mounted) _toast(context, 'Backup restored.');
    } on BackupException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, 'Restore failed: $e');
    }
  }
}
