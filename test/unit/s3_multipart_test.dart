import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/domain/entities/storage_config.dart';
import 'package:enpix/services/storage/s3_service.dart';

import '../helpers/fake_s3_adapter.dart';

void main() {
  const xmlInitiate = '<InitiateMultipartUploadResult>'
      '<Bucket>bucket</Bucket><Key>dev/files/x.enc</Key>'
      '<UploadId>uid-123</UploadId></InitiateMultipartUploadResult>';

  late S3Service s3;
  late FakeS3Adapter adapter;

  setUp(() {
    adapter = FakeS3Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://s3.example.com'));
    dio.httpClientAdapter = adapter;
    s3 = S3Service(dio: dio);
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
  });

  group('initiateMultipartUpload', () {
    test('POSTs ?uploads with metadata headers, returns UploadId', () async {
      adapter.queueResponse(
        const ScriptedResponse(
          200,
          body: xmlInitiate,
          headers: {'content-type': 'application/xml'},
        ),
      );

      final id = await s3.initiateMultipartUpload(
        'dev/files/x.enc',
        metadata: {'dek': 'DEKVALUE'},
        contentType: 'video/quicktime',
      );

      expect(id, 'uid-123');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/bucket/dev/files/x.enc');
      expect(req.uri.queryParameters, {'uploads': ''});
      // Metadata rides on the initiate request (parts cannot carry it).
      expect(req.headers['x-amz-meta-dek'], 'DEKVALUE');
      expect(req.headers['Content-Type'], 'video/quicktime');
      expect(req.headers['Authorization'], startsWith('AWS4-HMAC-SHA256'));
    });

    test('throws StorageException when UploadId missing from response',
        () async {
      adapter.queueResponse(
        const ScriptedResponse(
          200,
          body: '<InitiateMultipartUploadResult/>',
          headers: {'content-type': 'application/xml'},
        ),
      );

      await expectLater(
        s3.initiateMultipartUpload('dev/files/x.enc'),
        throwsA(isA<StorageException>()),
      );
    });

    test('wraps HTTP 500 in StorageException', () async {
      adapter.queueResponse(const ScriptedResponse(500));

      await expectLater(
        s3.initiateMultipartUpload('dev/files/x.enc'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('uploadPart', () {
    test('PUTs partNumber+uploadId query, sends chunk, returns ETag', () async {
      adapter.queueResponse(
        const ScriptedResponse(200, headers: {'etag': '"etag-1"'}),
      );

      final etag = await s3.uploadPart(
        'dev/files/x.enc',
        'uid-1',
        1,
        Uint8List.fromList([1, 2, 3]),
      );

      expect(etag, '"etag-1"');
      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/bucket/dev/files/x.enc');
      expect(req.uri.queryParameters, {'partNumber': '1', 'uploadId': 'uid-1'});
      expect(req.body, [1, 2, 3]);
      // Part integrity is signed (x-amz-content-sha256 of the chunk).
      expect(req.headers['x-amz-content-sha256'], isNotNull);
      expect(req.headers['Authorization'], startsWith('AWS4-HMAC-SHA256'));
    });

    test('wraps HTTP 500 in StorageException', () async {
      adapter.queueResponse(const ScriptedResponse(500));

      await expectLater(
        s3.uploadPart('dev/files/x.enc', 'uid-1', 1, Uint8List.fromList([9])),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('completeMultipartUpload', () {
    test('POSTs part list XML to ?uploadId', () async {
      adapter.queueResponse(
        const ScriptedResponse(
          200,
          body: '<CompleteMultipartUploadResult/>',
          headers: {'content-type': 'application/xml'},
        ),
      );

      await s3.completeMultipartUpload('dev/files/x.enc', 'uid-1', const [
        S3Part(1, '"e1"'),
        S3Part(2, '"e2"'),
      ]);

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.queryParameters, {'uploadId': 'uid-1'});
      final body = utf8.decode(req.body);
      expect(body, contains('<PartNumber>1</PartNumber>'));
      expect(body, contains('<ETag>"e1"</ETag>'));
      expect(body, contains('<PartNumber>2</PartNumber>'));
      expect(body, contains('<ETag>"e2"</ETag>'));
      expect(req.headers['Content-Type'], 'application/xml');
    });

    test('wraps HTTP 500 in StorageException', () async {
      adapter.queueResponse(const ScriptedResponse(500));

      await expectLater(
        s3.completeMultipartUpload('dev/files/x.enc', 'uid-1', const [
          S3Part(1, '"e1"'),
        ]),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('abortMultipartUpload', () {
    test('DELETEs ?uploadId', () async {
      adapter.queueResponse(const ScriptedResponse(204));

      await s3.abortMultipartUpload('dev/files/x.enc', 'uid-1');

      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.queryParameters, {'uploadId': 'uid-1'});
      expect(req.headers['Authorization'], startsWith('AWS4-HMAC-SHA256'));
    });
  });
}
