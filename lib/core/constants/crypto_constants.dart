class CryptoConstants {
  CryptoConstants._();
  static const int argon2MemorySize = 65536;
  static const int argon2Iterations = 3;
  static const int argon2Parallelism = 4;
  static const int argon2HashLength = 32;
  static const int argon2SaltLength = 16;
  static const int xchacha20KeyLength = 32;
  static const int xchacha20NonceLength = 24;
  static const int blake2bHashLength = 32;
  static const int keyWrapNonceLength = 24;
}
