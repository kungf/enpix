import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

/// Tests Dio's URL encoding behavior to ensure SigV4 signing matches.
void main() {
  test('RequestOptions.path with %2F keeps it single-encoded', () {
    final opts = RequestOptions(
      path: '/wytest?list-type=2&prefix=yJrr%2Ftest%2F&max-keys=1000',
    );
    final uri = opts.uri;
    print('Full URI: $uri');
    print('Query:    ${uri.query}');
    expect(uri.query, contains('%2F'));
  });

  test('RequestOptions with queryParameters map encodes /', () {
    final opts = RequestOptions(
      path: '/wytest',
      queryParameters: <String, String>{
        'list-type': '2',
        'prefix': 'yJrr/test/',
        'max-keys': '1000',
      },
    );
    final uri = opts.uri;
    print('Full URI: $uri');
    print('Query:    ${uri.query}');
    expect(uri.query, contains('%2F'));
    expect(uri.query, isNot(contains('%252')));
  });

  test('Uri.replace queryParameters order is insertion order', () {
    final base = Uri.parse('https://s3.example.com/wytest');
    final params = <String, String>{
      'list-type': '2',
      'prefix': 'fp123/device/',
      'max-keys': '1000',
    };
    final uri = base.replace(queryParameters: params);
    final query = uri.query;
    print('Query: $query');
    // Uri.replace preserves LinkedHashMap insertion order
    // keys are: list-type, prefix, max-keys
    expect(query, 'list-type=2&prefix=fp123%2Fdevice%2F&max-keys=1000');
  });
}
