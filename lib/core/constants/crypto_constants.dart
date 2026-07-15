class CryptoConstants {
  CryptoConstants._();

  // ── Adaptive Argon2id parameters ──────────────────────────────
  // Strategy: start from the strongest params, halve memory and double
  // ops until the device can complete within the deadline.  The product
  // memory × ops stays roughly constant so the total work is equivalent.
  static const int argon2MemoryFloor = 65536; // 64 MiB minimum (KiB)
  static const int argon2OpsFloor = 3;
  static const int argon2Parallelism = 4;
  static const int argon2HashLength = 32;
  static const int argon2SaltLength = 16;

  // Starting point for adaptive probing (1 GiB / 4 ops).
  static const int argon2MemoryStart = 1048576; // 1 GiB in KiB
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
