import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../data/app_paths.dart';

/// Recipe images live in `<app documents>/images/`; the database stores the
/// path relative to the documents directory so backups/restores stay valid.
class ImageStore {
  static Future<String> docsDir() => AppPaths.docsDir();

  /// Must be called once at startup (see main.dart) so thumbnails resolve synchronously.
  static Future<void> init() async => docsDir();

  static String? resolveSync(String relative) =>
      AppPaths.docsDirSync == null ? null : p.join(AppPaths.docsDirSync!, relative);

  /// Lets the user pick an image, copies it into the app folder, returns the relative path.
  static Future<String?> pickAndStore({ImageSource source = ImageSource.gallery}) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return null;
    final docs = await docsDir();
    final dir = Directory(p.join(docs, 'images'));
    await dir.create(recursive: true);
    final name = '${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}';
    await File(picked.path).copy(p.join(dir.path, name));
    return p.join('images', name);
  }

  static Future<void> delete(String relative) async {
    final docs = await docsDir();
    final f = File(p.join(docs, relative));
    if (await f.exists()) await f.delete();
  }
}

