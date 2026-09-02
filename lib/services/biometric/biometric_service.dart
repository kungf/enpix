import 'package:local_auth/local_auth.dart';

/// Authenticates the device owner via platform biometrics (Face ID /
/// fingerprint). Abstracted so [CredentialService]'s auto-unlock gate can
/// be unit-tested without platform channels.
abstract interface class BiometricAuth {
  /// Whether biometrics are enrolled and usable on this device.
  Future<bool> isAvailable();

  /// Run a biometric prompt. Returns false when the user cancels or all
  /// attempts fail — callers must fall back to manual unlocking.
  Future<bool> authenticate({required String reason});
}

/// Production implementation backed by `local_auth`.
class LocalAuthBiometric implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      return canCheck || enrolled.isNotEmpty;
    } on Exception {
      // Platform channel failures (rare device quirks) must not block
      // unlocking — treat as "no biometrics" so the gate is skipped.
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) {
    return _auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        // No device-passcode fallback — Enpix falls back to its own
        // passphrase prompt instead, keeping the gate biometric-only.
        biometricOnly: true,
        // Resume the prompt if the app is backgrounded mid-auth.
        stickyAuth: true,
      ),
    );
  }
}
