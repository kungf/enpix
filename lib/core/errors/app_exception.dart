abstract class AppException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
  const AppException({required this.message, this.cause, this.stackTrace});
  @override
  String toString() => '${runtimeType}: $message';
}
