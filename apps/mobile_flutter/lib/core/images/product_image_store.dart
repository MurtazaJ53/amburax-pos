import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists product photos inside the app's documents directory so a path
/// stored in the database keeps resolving across restarts (the OS picker hands
/// back a temp/cache path that can be evicted at any time).
class ProductImageStore {
  ProductImageStore({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const String _folder = 'product_images';

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folder));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Let the user pick from the camera or gallery, downscale/compress it, and
  /// copy it into permanent storage. Returns the stored absolute path, or null
  /// if the user cancelled.
  Future<String?> pickAndStore({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final dir = await _dir();
    final ext = p.extension(picked.path).isNotEmpty
        ? p.extension(picked.path)
        : '.jpg';
    final dest = p.join(
      dir.path,
      'img_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    final bytes = await picked.readAsBytes();
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// Read a stored photo back as a base64 data URI for upload. The server keeps
  /// product photos in the database (the container filesystem isn't persisted),
  /// so images survive a data clear / reinstall. Returns null when there's no
  /// readable file, or when the image is too large to be worth syncing.
  static Future<String?> encodeForUpload(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      // Guard the payload: pickAndStore already caps at 1024px/q80, but skip
      // anything unexpectedly large rather than bloating every sync.
      if (bytes.length > 800 * 1024) return null;
      final ext = p.extension(path).toLowerCase();
      final mime = (ext == '.png')
          ? 'image/png'
          : (ext == '.webp')
          ? 'image/webp'
          : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  /// Write a base64 data URI pulled from the server into local storage and
  /// return the file path, so the existing file-based display code just works.
  Future<String?> storeFromDataUri(String? dataUri) async {
    if (dataUri == null || dataUri.trim().isEmpty) return null;
    try {
      final marker = dataUri.indexOf('base64,');
      final payload = marker >= 0 ? dataUri.substring(marker + 7) : dataUri;
      final bytes = base64Decode(payload.trim());
      if (bytes.isEmpty) return null;
      final ext = dataUri.contains('image/png')
          ? '.png'
          : dataUri.contains('image/webp')
          ? '.webp'
          : '.jpg';
      final dir = await _dir();
      final dest = p.join(
        dir.path,
        'img_${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      await File(dest).writeAsBytes(bytes, flush: true);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// Save raw image bytes fetched from the server.
  ///
  /// Product photos no longer travel inside the inventory list - they were
  /// base64 text on every row, so one sync pulled every picture in the shop
  /// whether it had changed or not. They are fetched from their own address
  /// now, which arrives as bytes rather than a data URI.
  Future<String?> storeFromBytes(
    List<int>? bytes, {
    String? contentType,
  }) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final type = (contentType ?? '').toLowerCase();
      final ext = type.contains('png')
          ? '.png'
          : type.contains('webp')
          ? '.webp'
          : type.contains('gif')
          ? '.gif'
          : '.jpg';
      final dir = await _dir();
      final dest = p.join(
        dir.path,
        'img_${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      await File(dest).writeAsBytes(bytes, flush: true);
      return dest;
    } catch (_) {
      // A photo that will not save is not worth failing a sync over. The
      // product still arrives; it simply shows its initial instead.
      return null;
    }
  }

  /// Best-effort delete of a stored photo. Safe to call with a null/empty path
  /// or a file that is already gone.
  Future<void> deleteIfOwned(String? path) async {
    if (path == null || path.isEmpty) return;
    if (!path.contains(_folder)) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A leftover image file is harmless; never let cleanup break a save.
    }
  }
}
