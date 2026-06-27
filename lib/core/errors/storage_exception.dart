import 'app_exception.dart';

class StorageException extends AppException {
  const StorageException({required super.message, super.cause, super.stackTrace});
}

class StorageNotConfiguredException extends AppException {
  const StorageNotConfiguredException({super.message = 'S3 storage not configured.', super.cause, super.stackTrace});
}

/// Thrown when passphrase verification fails (user input error, not a bug).
class WrongPassphraseException extends AppException {
  const WrongPassphraseException({super.message = 'Incorrect passphrase', super.cause, super.stackTrace});
}
