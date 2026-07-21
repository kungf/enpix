import 'app_exception.dart';

class StorageException extends AppException {
  final String? detail;
  const StorageException({
    required super.message,
    this.detail,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => detail != null ? '$message\n$detail' : message;
}

class StorageNotConfiguredException extends AppException {
  const StorageNotConfiguredException({
    super.message = 'S3 storage not configured.',
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when passphrase verification fails (user input error, not a bug).
class WrongPassphraseException extends AppException {
  const WrongPassphraseException({
    super.message = 'Incorrect passphrase',
    super.cause,
    super.stackTrace,
  });
}
