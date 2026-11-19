import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the app keeps its private data. Everything that must be part of a
/// backup (database + images) lives under [docsDir].
class AppPaths {
  static String? _docs;

  static Future<String> docsDir() async =>
      _docs ??= (await getApplicationDocumentsDirectory()).path;

  /// Synchronous access after [init] ran (used by image thumbnails).
  static String? get docsDirSync => _docs;

  static Future<void> init() async => docsDir();

  static const dbFileName = 'meal_planner.sqlite';
  static const imagesDirName = 'images';

  static Future<String> dbPath() async => p.join(await docsDir(), dbFileName);
}
