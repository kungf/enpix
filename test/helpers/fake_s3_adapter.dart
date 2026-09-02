import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A single scripted HTTP response returned by [FakeS3Adapter].
class ScriptedResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const ScriptedResponse(
    this.statusCode, {
    this.body = '',
    this.headers = const {},
  });
}

/// One HTTP request captured by [FakeS3Adapter].
class CapturedRequest {
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final Uint8List body;

  const CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });
}

/// Fake Dio [HttpClientAdapter] that records every request and answers
/// from a scripted response queue — lets S3Service and UploadService tests
/// exercise the real signing/HTTP layer without a network.
///
/// Responses are consumed in order; a request beyond the script throws.
class FakeS3Adapter implements HttpClientAdapter {
  final List<ScriptedResponse> _responses;
  final requests = <CapturedRequest>[];

  FakeS3Adapter([Iterable<ScriptedResponse> responses = const []])
      : _responses = List.of(responses);

  /// Append a response to the end of the script queue.
  void queueResponse(ScriptedResponse response) => _responses.add(response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final builder = BytesBuilder();
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        builder.add(chunk);
      }
    }
    requests.add(
      CapturedRequest(
        method: options.method,
        uri: options.uri,
        headers: options.headers,
        body: Uint8List.fromList(builder.takeBytes()),
      ),
    );
    if (_responses.isEmpty) {
      throw StateError(
        'No scripted response for ${options.method} ${options.uri}',
      );
    }
    final r = _responses.removeAt(0);
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(r.body))),
      r.statusCode,
      headers: r.headers.map((k, v) => MapEntry(k, [v])),
    );
  }

  @override
  void close({bool force = false}) {}
}
