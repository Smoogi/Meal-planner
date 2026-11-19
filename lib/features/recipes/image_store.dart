import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Recipe images live in `<app documents>/images/`; the database stores the
/// path relative to the documents directory so backups/restores stay valid.
class ImageStore {
  static String? _docs;

  static Future<String> docsDir() async =>
      _docs ??= (await getApplicationDocumentsDirectory()).path;

  /// Must be called once at startup (see main.dart) so thumbnails resolve synchronously.
  static Future<void> init() async => docsDir();

  static String? resolveSync(String relative) =>
      _docs == null ? null : p.join(_docs!, relative);

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
