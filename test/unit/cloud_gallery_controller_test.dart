import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/presentation/screens/cloud_gallery/cloud_gallery_controller.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/cloud/cloud_media_repository.dart';
import 'package:enpix/services/cloud/photo_saver.dart';
import 'package:enpix/services/storage/s3_config_service.dart';

CloudMedia _media(String fileId, {int day = 7}) {
  final dateSegment = '202603${day.toString().padLeft(2, '0')}';
  return CloudMedia(
    fileId: fileId,
    thumbnailKey: 'enpix/dev/thumbs/$dateSegment/${fileId}_thumb.enc',
    originalKey: 'enpix/dev/files/$dateSegment/$fileId.enc',
    deviceId: 'dev',
    createdAt: DateTime(2026, 3, day),
    thumbnailSize: 100,
  );
}

class _FakeGateway implements CloudMediaGateway {
  _FakeGateway(this.items);

  final List<CloudMedia> items;
  final Set<String> failingDeletes = <String>{};
  final Map<String, CloudMediaContent> contents = <String, CloudMediaContent>{};
  int listCalls = 0;

  @override
  Future<List<CloudMedia>> listThumbnails() async {
    listCalls++;
    return items;
  }

  @override
  Future<Uint8List> loadThumbnail(CloudMedia media) async => Uint8List(0);

  @override
  Future<CloudMediaContent> fetchOriginal(CloudMedia media) async {
    final content = contents[media.fileId];
    if (content == null) {
      throw const CloudMediaException('no content');
    }
    return content;
  }

  @override
  Future<CloudDeleteReport> deleteAll(Iterable<CloudMedia> media) async {
    var deleted = 0;
    final failures = <CloudDeleteFailure>[];
    for (final item in media) {
      if (failingDeletes.contains(item.fileId)) {
        failures.add(
          CloudDeleteFailure(media: item, error: Exception('delete failed')),
        );
      } else {
        deleted++;
      }
    }
    return CloudDeleteReport(deleted: deleted, failures: failures);
  }
}

class _ThrowingGateway extends _FakeGateway {
  _ThrowingGateway() : super(const []);

  @override
  Future<List<CloudMedia>> listThumbnails() async {
    throw const CloudMediaException('boom');
  }
}

class _FakePhotoSaver implements PhotoSaver {
  final List<String> savedNames = <String>[];
  Object? error;

  @override
  Future<void> saveImage(Uint8List bytes, {required String fileName}) async {
    final failure = error;
    if (failure != null) throw failure;
    savedNames.add(fileName);
  }
}

CloudGalleryController _controller(
  _FakeGateway gateway, {
  _FakePhotoSaver? saver,
  S3ConfigResult config = S3ConfigResult.configured,
}) {
  return CloudGalleryController(
    repository: gateway,
    photoSaver: saver ?? _FakePhotoSaver(),
    ensureConfigured: () async => config,
    now: () => DateTime(2026, 3, 10),
  );
}

void main() {
  group('load', () {
    test('groups items by day, newest first', () async {
      final controller = _controller(
        _FakeGateway([_media('a', day: 7), _media('b', day: 8)]),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, CloudGalleryStatus.ready);
      expect(controller.state.days.length, 2);
      expect(controller.state.days.first.dateKey, '2026-03-08');
      expect(controller.state.days.first.label, '2026年3月8日');
    });

    test('reports a missing endpoint without listing', () async {
      final gateway = _FakeGateway([_media('a')]);
      final controller = _controller(
        gateway,
        config: S3ConfigResult.missingEndpoint,
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.hasError, isTrue);
      expect(controller.state.errorMessage, contains('Endpoint'));
      expect(gateway.listCalls, 0);
    });

    test('reports a listing failure', () async {
      final controller = _controller(_ThrowingGateway());
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.hasError, isTrue);
      expect(controller.state.errorMessage, contains('boom'));
    });
  });

  group('selection', () {
    test('toggles by thumbnail key and exits when empty', () async {
      final media = _media('a');
      final controller = _controller(_FakeGateway([media]));
      addTearDown(controller.dispose);

      controller.toggleSelection(media.thumbnailKey);
      expect(controller.state.isSelectionMode, isTrue);
      expect(controller.state.selectedCount, 1);

      controller.toggleSelection(media.thumbnailKey);
      expect(controller.state.isSelectionMode, isFalse);
    });

    test('select-all only covers visible days', () async {
      final a = _media('a');
      final b = _media('b');
      final controller = _controller(_FakeGateway([a, b]));
      addTearDown(controller.dispose);
      await controller.load();

      controller.selectAllVisible();

      expect(controller.state.selectedCount, 2);
    });
  });

  group('deleteSelected', () {
    test('removes succeeded items and keeps failed ones', () async {
      final a = _media('a');
      final b = _media('b');
      final gateway = _FakeGateway([a, b])..failingDeletes.add('b');
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.load();
      controller
        ..toggleSelection(a.thumbnailKey)
        ..toggleSelection(b.thumbnailKey);

      final report = await controller.deleteSelected();

      expect(report!.deleted, 1);
      expect(report.failures.single.media.fileId, 'b');
      final remaining = controller.state.allDays
          .expand((day) => day.items)
          .map((item) => item.fileId)
          .toList();
      expect(remaining, ['b']);
      expect(controller.state.isWorking, isFalse);
      expect(controller.state.selectedCount, 0);
    });
  });

  group('downloadSelected', () {
    test('saves decrypted bytes with the original file name', () async {
      final media = _media('a');
      final gateway = _FakeGateway([media])
        ..contents['a'] = CloudMediaContent(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'IMG_0001.jpg',
          hashVerified: true,
        );
      final saver = _FakePhotoSaver();
      final controller = _controller(gateway, saver: saver);
      addTearDown(controller.dispose);
      await controller.load();
      controller.toggleSelection(media.thumbnailKey);

      final report = await controller.downloadSelected();

      expect(report!.saved, 1);
      expect(report.hasFailures, isFalse);
      expect(saver.savedNames, ['IMG_0001.jpg']);
    });

    test('counts per-item failures and continues', () async {
      final a = _media('a');
      final b = _media('b');
      final gateway = _FakeGateway([a, b])
        ..contents['a'] = CloudMediaContent(
          bytes: Uint8List(2),
          fileName: 'a.jpg',
          hashVerified: true,
        );
      final saver = _FakePhotoSaver();
      final controller = _controller(gateway, saver: saver);
      addTearDown(controller.dispose);
      await controller.load();
      controller
        ..toggleSelection(a.thumbnailKey)
        ..toggleSelection(b.thumbnailKey);

      final report = await controller.downloadSelected();

      expect(report!.saved, 1);
      expect(report.failures.length, 1);
      expect(controller.state.isWorking, isFalse);
    });

    test('reports a save failure from the photo library', () async {
      final media = _media('a');
      final gateway = _FakeGateway([media])
        ..contents['a'] = CloudMediaContent(
          bytes: Uint8List(2),
          fileName: 'a.jpg',
          hashVerified: true,
        );
      final saver = _FakePhotoSaver()..error = Exception('denied');
      final controller = _controller(gateway, saver: saver);
      addTearDown(controller.dispose);
      await controller.load();
      controller.toggleSelection(media.thumbnailKey);

      final report = await controller.downloadSelected();

      expect(report!.saved, 0);
      expect(report.failures.length, 1);
    });
  });

  test('onSessionUnlocked re-lists', () async {
    final gateway = _FakeGateway([_media('a')]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    expect(gateway.listCalls, 1);

    await controller.onSessionUnlocked();

    expect(gateway.listCalls, 2);
  });
}
