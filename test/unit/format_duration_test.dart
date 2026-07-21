import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/presentation/shared/utils/format_duration.dart';

void main() {
  test('formats seconds under a minute as m:ss', () {
    expect(formatDuration(0), '0:00');
    expect(formatDuration(5), '0:05');
    expect(formatDuration(59), '0:59');
  });

  test('formats minutes as m:ss', () {
    expect(formatDuration(60), '1:00');
    expect(formatDuration(125), '2:05');
    expect(formatDuration(599), '9:59');
  });

  test('formats hours as h:mm:ss', () {
    expect(formatDuration(3600), '1:00:00');
    expect(formatDuration(3725), '1:02:05');
  });

  test('clamps negative seconds to 0', () {
    expect(formatDuration(-10), '0:00');
  });
}
