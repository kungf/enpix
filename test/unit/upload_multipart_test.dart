import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/domain/entities/storage_config.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';
import 'package:enpix/services/upload/upload_service.dart';

import '../helpers/fake_s3_adapter.dart';

void main() {
  const mb = 1024 * 1024;
  // Encrypted size = 24-byte nonce + plaintext + 16-byte Poly1305 tag
  // (CryptoService.encrypt prepends the nonce).
  // 8MB+1 plaintext → 8MB+41 encrypted → 2 parts: [8MB, 41B].
  final bigPlaintext = Uint8List(8 * mb + 1);
  // 8MB-40 plaintext → exactly 8MB encrypted → single PUT (boundary).
  final boundaryPlaintext = Uint8List(8 * mb - 40);

  const xmlInitiate = '<InitiateMultipartUploadResult>'
      '<UploadId>uid-9</UploadId></InitiateMultipartUploadResult>';

  const xmlHeaders = {'content-type': 'application/xml'};

  late FakeS3Adapter adapter;
  late UploadService uploader;

  setUp(() {
    adapter = FakeS3Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://s3.example.com'));
    dio.httpClientAdapter = adapter;
    final s3 = S3Service(dio: dio);
    s3.configure(
      const StorageConfig(
        endpointUrl: 'https://s3.example.com',
        bucketName: 'bucket',
        region: 'us-east-1',
        accessKey: 'AK',
        secretKey: 'SK',
        updatedAt: 0,
      ),
    );
    uploader = UploadService(CryptoService(), s3);
  });

  Future<UploadResult> runUpload(Uint8List plaintext) {
    return uploader.upload(
      plaintext: plaintext,
      fileName: 'big.mov',
      mimeType: 'video/quicktime',
      createdAt: DateTime(2026, 1, 1),
      masterKey: CryptoService().generateMasterKey(),
    );
  }

  group('multipart configuration', () {
    test('part size and threshold are 8MB', () {
      expect(kMultipartPartSize, 8 * 1024 * 1024);
      expect(kMultipartThreshold, kMultipartPartSize);
    });
  });

  group('UploadService multipart', () {
    test('file over threshold uploads via multipart with 8MB parts', () async {
      adapter.queueResponse(const ScriptedResponse(404)); // HEAD → absent
      adapter.queueResponse(
        const ScriptedResponse(200, body: xmlInitiate, headers: xmlHeaders),
      );
      adapter.queueResponse(
        const ScriptedResponse(200, headers: {'etag': '"e1"'}),
      );
      adapter.queueResponse(
        const ScriptedResponse(200, headers: {'etag': '"e2"'}),
      );
      adapter.queueResponse(
        const ScriptedResponse(
          200,
          body: '<CompleteMultipartUploadResult/>',
          headers: xmlHeaders,
        ),
      );

      final result = await runUpload(bigPlaintext);

      expect(result.success, true);
      expect(result.remoteExists, false);
      expect(result.size, 8 * mb + 41); // encrypted length

      // Sequence: HEAD, initiate POST, part PUTs, complete POST.
      expect(adapter.requests.length, 5);
      final [head, init, part1, part2, complete] = adapter.requests;
      expect(head.method, 'HEAD');

      expect(init.method, 'POST');
      expect(init.uri.queryParameters, {'uploads': ''});
      // Object metadata rides on the initiate request.
      expect(init.headers['x-amz-meta-filename'], 'big.mov');
      expect(init.headers['x-amz-meta-hash'], isNotNull);
      expect(init.headers['x-amz-meta-dek'], isNotNull);
      expect(init.headers['x-amz-meta-nonce'], isNotNull);

      expect(part1.method, 'PUT');
      expect(
        part1.uri.queryParameters,
        {'partNumber': '1', 'uploadId': 'uid-9'},
      );
      expect(part1.body.length, 8 * mb);
      expect(
        part2.uri.queryParameters,
        {'partNumber': '2', 'uploadId': 'uid-9'},
      );
      expect(part2.body.length, 41);

      expect(complete.method, 'POST');
      expect(complete.uri.queryParameters, {'uploadId': 'uid-9'});
      expect(
        utf8.decode(complete.body),
        contains('<PartNumber>2</PartNumber>'),
      );
    });

    test('file at exactly the threshold uses single PUT', () async {
      adapter.queueResponse(const ScriptedResponse(404)); // HEAD
      adapter.queueResponse(const ScriptedResponse(200)); // single PUT

      final result = await runUpload(boundaryPlaintext);

      expect(result.success, true);
      expect(adapter.requests.length, 2);
      final put = adapter.requests[1];
      expect(put.method, 'PUT');
      expect(put.uri.queryParameters, isEmpty);
      expect(put.body.length, 8 * mb);
      // Metadata still present on the plain PUT path.
      expect(put.headers['x-amz-meta-filename'], 'big.mov');
    });

    test('retries a failed part instead of the whole file', () async {
      adapter.queueResponse(const ScriptedResponse(404)); // HEAD
      adapter.queueResponse(
        const ScriptedResponse(200, body: xmlInitiate, headers: xmlHeaders),
      );
      adapter.queueResponse(const ScriptedResponse(500)); // part 1, attempt 1
      adapter.queueResponse(
        const ScriptedResponse(200, headers: {'etag': '"e1"'}), // part 1 retry
      );
      adapter.queueResponse(
        const ScriptedResponse(200, headers: {'etag': '"e2"'}), // part 2
      );
      adapter.queueResponse(
        const ScriptedResponse(
          200,
          body: '<CompleteMultipartUploadResult/>',
          headers: xmlHeaders,
        ),
      );

      final result = await runUpload(bigPlaintext);

      expect(result.success, true);
      final partPuts =
          adapter.requests.where((r) => r.method == 'PUT').toList();
      expect(partPuts.length, 3); // part 1 ×2 + part 2 ×1
      expect(partPuts[0].uri.queryParameters['partNumber'], '1');
      expect(partPuts[1].uri.queryParameters['partNumber'], '1');
      expect(partPuts[2].uri.queryParameters['partNumber'], '2');
      // The retried part re-sent its full 8MB chunk.
      expect(partPuts[1].body.length, 8 * mb);
    });

    test('aborts multipart upload when a part fails permanently', () async {
      adapter.queueResponse(const ScriptedResponse(404)); // HEAD
      adapter.queueResponse(
        const ScriptedResponse(200, body: xmlInitiate, headers: xmlHeaders),
      );
      adapter.queueResponse(const ScriptedResponse(400)); // non-retryable
      adapter.queueResponse(const ScriptedResponse(204)); // abort DELETE

      final result = await runUpload(bigPlaintext);

      expect(result.success, false);
      expect(result.error, isNotNull);
      // Only the initiate POST ran — complete was never sent.
      expect(
        adapter.requests.where((r) => r.method == 'POST').length,
        1,
      );
      final abort = adapter.requests.last;
      expect(abort.method, 'DELETE');
      expect(abort.uri.queryParameters, {'uploadId': 'uid-9'});
    });

    test('cancellation mid-multipart aborts and propagates cancellation',
        () async {
      adapter.queueResponse(const ScriptedResponse(404)); // HEAD
      adapter.queueResponse(
        const ScriptedResponse(200, body: xmlInitiate, headers: xmlHeaders),
      );
      adapter.queueResponse(const ScriptedResponse(204)); // abort DELETE

      // Cancel as soon as the initiate POST has been captured.
      await expectLater(
        uploader.upload(
          plaintext: bigPlaintext,
          fileName: 'big.mov',
          mimeType: 'video/quicktime',
          createdAt: DateTime(2026, 1, 1),
          masterKey: CryptoService().generateMasterKey(),
          isCancelled: () => adapter.requests.any((r) => r.method == 'POST'),
        ),
        throwsA(isA<UploadCancelledException>()),
      );

      // Initiate ran, no part PUTs, abort was called.
      expect(adapter.requests.where((r) => r.method == 'PUT'), isEmpty);
      final abort = adapter.requests.last;
      expect(abort.method, 'DELETE');
      expect(abort.uri.queryParameters, {'uploadId': 'uid-9'});
    });
  });
}
