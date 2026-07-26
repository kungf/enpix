class CryptoConstants {
  CryptoConstants._();

  // ── Adaptive Argon2id parameters ──────────────────────────────
  // Strategy: start from mobile-safe params, halve memory and double
  // ops until the device can complete within the deadline.  The product
  // memory × ops stays roughly constant so the total work is equivalent.
  static const int argon2MemoryFloor = 32768; // 32 MiB minimum (KiB)
  static const int argon2OpsFloor = 4;
  static const int argon2Parallelism = 4;
  static const int argon2HashLength = 32;
  static const int argon2SaltLength = 16;

  // Starting point: 128 MiB — safe for modern mobile devices. Starting
  // higher (e.g. 1 GiB) causes the main-thread Argon2id allocation to
  // block the UI indefinitely on iOS.
  static const int argon2MemoryStart = 131072; // 128 MiB in KiB
  static const int argon2OpsStart = 4;

  // Legacy fixed params — kept for reading old Keychain entries.
  static const int argon2MemorySize = 65536; // 64 MiB
  static const int argon2Iterations = 3;

  // ── XChaCha20-Poly1305 ────────────────────────────────────────
  static const int xchacha20KeyLength = 32;
  static const int xchacha20NonceLength = 24;

  // ── BLAKE2b ───────────────────────────────────────────────────
  static const int blake2bHashLength = 32;

  // ── Key wrapping ──────────────────────────────────────────────
  static const int keyWrapNonceLength = 24;
}
