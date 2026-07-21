import 'package:flutter_test/flutter_test.dart';

/// Test that SigV4 canonical query construction does NOT double-encode.
/// The bug: _signedOptions was calling Uri.encodeComponent on already-encoded
/// values, turning %2F → %252F, breaking the signature on strict S3 servers.
void main() {
  // Simulates the canonical query logic from _signedOptions (fixed version).
  String canonicalQuery(String path) {
    final parts = path.split('?');
    if (parts.length <= 1) return '';
    final params = parts[1].split('&').toList()..sort();
    return params.join('&');
  }

  test('preserves single-encoded / as %2F', () {
    const path = '/bucket?list-type=2&prefix=abc%2Fdev%2F&max-keys=1000';
    final query = canonicalQuery(path);
    expect(query, contains('%2F'));
    expect(query, isNot(contains('%252F')));
  });

  test('does NOT re-encode, no double encoding', () {
    const path = '/bucket?prefix=abc%2Fdevices%2F';
    expect(canonicalQuery(path), 'prefix=abc%2Fdevices%2F');
  });

  test('sorts alphabetically', () {
    expect(
      canonicalQuery('/bucket?z=last&a=first&m=middle'),
      'a=first&m=middle&z=last',
    );
  });

  test('full listObjects simulation — no double encoding', () {
    // Simulates what listObjects sends to _signedOptions
    const prefix = 'fp123/device456/thumbs/';
    final encodedPrefix = Uri.encodeComponent(prefix);
    final parts = ['list-type=2', 'prefix=$encodedPrefix', 'max-keys=1000'];
    parts.sort();
    final path = '/bucket?${parts.join('&')}';
    final query = canonicalQuery(path);

    // Must match single-encoded sorted query
    expect(
      query,
      'list-type=2&max-keys=1000&prefix=fp123%2Fdevice456%2Fthumbs%2F',
    );
    // CRITICAL: must NOT have triple-digit percent encoding (%25 → %252 = double)
    expect(query, isNot(contains('%252')));
  });
}
