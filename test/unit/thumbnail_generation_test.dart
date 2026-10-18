import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:enpix/core/constants/app_constants.dart';
import 'package:enpix/services/upload/upload_service.dart';

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  test('preserves aspect ratio for a landscape image', () {
    final thumb = buildThumbnailJpeg(_jpeg(800, 200));
    final decoded = img.decodeImage(thumb!)!;

    expect(decoded.width, AppConstants.thumbnailMaxWidth);
    expect(decoded.height, AppConstants.thumbnailMaxWidth ~/ 4);
  });

  test('preserves aspect ratio for a portrait image', () {
    final thumb = buildThumbnailJpeg(_jpeg(480, 640));
    final decoded = img.decodeImage(thumb!)!;

    expect(decoded.height, AppConstants.thumbnailMaxHeight);
    expect(decoded.width, AppConstants.thumbnailMaxHeight * 480 ~/ 640);
  });

  test('does not stretch a 4:3 image to a square', () {
    final thumb = buildThumbnailJpeg(_jpeg(640, 480));
    final decoded = img.decodeImage(thumb!)!;

    expect(decoded.width, 512);
    expect(decoded.height, 384);
  });

  test('does not upscale images smaller than the box', () {
    final thumb = buildThumbnailJpeg(_jpeg(64, 48));
    final decoded = img.decodeImage(thumb!)!;

    expect(decoded.width, 64);
    expect(decoded.height, 48);
  });

  test('returns null for non-image bytes', () {
    expect(buildThumbnailJpeg(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
