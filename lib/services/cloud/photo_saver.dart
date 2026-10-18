import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Thrown when the system photo library refuses a save (no permission,
/// storage full, unsupported format).
class PhotoSaveException implements Exception {
  const PhotoSaveException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'PhotoSaveException: $message';
}

/// Platform boundary for writing decrypted photos into the system library.
///
/// An interface keeps the cloud download flow testable without touching
/// the photo library.
abstract interface class PhotoSaver {
  /// Saves [bytes] as an image. [fileName] is a hint for the library name.
  Future<void> saveImage(Uint8List bytes, {required String fileName});
}

/// [PhotoSaver] backed by the `gal` plugin.
class GalPhotoSaver implements PhotoSaver {
  const GalPhotoSaver();

  @override
  Future<void> saveImage(Uint8List bytes, {required String fileName}) async {
    final granted = await Gal.hasAccess() || await Gal.requestAccess();
    if (!granted) {
      throw const PhotoSaveException('没有相册写入权限');
    }
    try {
      await Gal.putImageBytes(bytes, name: _safeName(fileName));
    } on Exception catch (e) {
      throw PhotoSaveException('保存到相册失败', cause: e);
    }
  }

  /// Strips path separators and extension — gal appends its own.
  static String _safeName(String fileName) {
    final withoutPath = fileName.split('/').last.split(r'\').last;
    final dot = withoutPath.lastIndexOf('.');
    final stem = dot > 0 ? withoutPath.substring(0, dot) : withoutPath;
    return stem.isEmpty ? 'enpix' : stem;
  }
}
