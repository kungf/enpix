# Enpix

Cross-platform photo archiving app with end-to-end encryption and S3-compatible backend.

## Features

- **End-to-End Encryption**: Files encrypted on-device with XChaCha20-Poly1305 before upload. Backend never sees plaintext.
- **S3 Backend**: Supports any S3-compatible storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, Wasabi).
- **TTL Auto-Archiving**: Configurable time-based (e.g., photos older than 30 days) and size-based (e.g., when local > 100 GiB, archive oldest) triggers.
- **Recovery Key**: A 256-bit recovery key wraps the master key so the vault can be restored if the device passphrase is lost.
- **Cross-Platform**: iOS, Android, macOS, Windows, Linux - single Flutter codebase.
- **Zero-Knowledge**: Server has no access to files, filenames, or thumbnails. Everything is encrypted client-side.

## Architecture

```
┌───────────────────────────────────────────────────┐
│                Flutter App (4 tabs)                │
│  ┌────────┐ ┌────────┐ ┌──────────┐ ┌──────────┐  │
│  │ Photos │ │ Cloud  │ │ Overview │ │ Settings │  │
│  │(local) │ │Gallery │ │          │ │          │  │
│  └───┬────┘ └───┬────┘ └────┬─────┘ └────┬─────┘  │
│      │          │           │            │         │
│  ┌───┴──────────┴───────────┴────────────┴───────┐ │
│  │             Riverpod Providers                │ │
│  │  remoteUsage · deviceList · uploadTracker     │ │
│  │  uploadSettings · ttlEngine · backupManager    │ │
│  └────────────────────┬──────────────────────────┘ │
│                       │                            │
│  ┌────────────────────┴──────────────────────────┐ │
│  │                Services Layer                  │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │ │
│  │  │  Crypto   │ │    S3    │ │   TTL    │       │ │
│  │  │ Service  │ │ Service  │ │  Engine  │       │ │
│  │  └──────────┘ └──────────┘ └──────────┘       │ │
│  └────────────────────┬──────────────────────────┘ │
│                       │                            │
│  ┌────────────────────┴──────────────────────────┐ │
│  │       Persistence (FlutterSecureStorage)      │ │
│  │   Keychain / Keystore JSON blobs:             │ │
│  │   upload_records · upload_settings            │ │
│  │   ttl_config · credentials                    │ │
│  └───────────────────────────────────────────────┘ │
└──────────────────────────┬──────────────────────────┘
                           │ HTTPS (TLS)
                           ▼
                 ┌─────────────────┐
                 │  S3-Compatible  │
                 │     Storage     │
                 │  files/*/*.enc  │  (encrypted blobs)
                 │  thumbs/*.enc   │  (encrypted thumbs)
                 └─────────────────┘
```

> The **Photos** tab is hidden on desktop/web, leaving Cloud / Overview / Settings.

### Encryption Scheme

```
User Passphrase
     │ Argon2id (probe-tuned per device)
     ▼
   KEK (256-bit) ── wrapped ──► Secure Storage (Keychain/Keystore)
     │
     │ unwrap when needed
     ▼
Per-file: random DEK ──► XChaCha20-Poly1305 ──► encrypted file -> S3
           DEK wrapped by KEK ──► S3 object metadata (x-amz-meta-dek)

Recovery: master key wrapped by a 256-bit recovery key (RK) -> S3,
          restore the vault with the RK if the passphrase is lost.
```

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| State Management | Riverpod 2 (`flutter_riverpod`) |
| Persistence | `flutter_secure_storage` (Keychain / Keystore, JSON blobs) |
| Crypto | `cryptography` (XChaCha20-Poly1305, Argon2id, Blake2b) |
| S3 Client | `dio` + hand-rolled SigV4 (no native SDK) |
| Key Storage | iOS Keychain / Android Keystore |
| Background | `workmanager` + `flutter_background_service` |
| Photo Access | `photo_manager` |
| Video | `video_player` |
| Charts | `fl_chart` |

## Project Structure

```
lib/
├── main.dart                     # Entry point, first-run detection
├── app.dart                      # EnpixApp: theme (light/dark), router, onboarding
├── core/                         # Constants, errors, logging, theme, utils
│   └── theme/                    # AppColorScheme (ThemeExtension), light/dark palettes
├── domain/                       # Entities (pure Dart)
├── presentation/                 # screens, shared widgets
│   ├── screens/                  # local_gallery, cloud_gallery, overview, settings, setup
│   └── shared/widgets/           # photo_viewer, video_player_page, skeletons, ...
└── services/                     # crypto, storage (s3, providers), upload, thumbnail, settings, ttl
```

## Getting Started

### Prerequisites

- Flutter SDK >= 3.5.0
- iOS: Xcode 16+
- Android: Android Studio + SDK 34+
- S3-compatible storage account (or local MinIO for testing)

### Setup

```bash
# Clone the repo
git clone <repo-url> enpix
cd enpix

# Install dependencies
flutter pub get

# Run on iOS simulator
flutter run -d ios
```

> No code generation step is required - Riverpod is used in its classic
> (non-codegen) form and there is no Drift/SQLite layer.

## Roadmap

### v0.1 - Self-Hosted Storage (Current)

For technical users who bring their own S3-compatible storage.

- [x] Project scaffold, encryption, S3 client, secure persistence
- [x] Local photo thumbnail grid + full-screen viewer (photos + video)
- [x] TTL auto-archive engine
- [x] Cloud browse + on-demand download (throttled thumbnail pipeline)
- [x] Onboarding wizard (first run -> S3 configure -> set passphrase)
- [ ] Biometric authentication + security hardening
- [ ] Publish to App Store / Google Play

### v0.2 - Managed Cloud Storage

For everyday users - works out of the box, no S3 setup required.

- [ ] User registration / login (email + Apple/Google Sign-In)
- [ ] Auto-provisioned cloud storage, client-side encrypted upload
- [ ] Dual-mode switch: Enpix Cloud / Custom S3
- [ ] 5 GB free tier + usage dashboard
- [ ] Backend API service (auth + file operations)

### v1.0 - Monetization + Multi-Platform

- [ ] In-app subscriptions (iOS StoreKit / Google Play Billing)
- [ ] Multi-device sync
- [ ] Device management + remote sign-out
- [ ] Encrypted share links
- [ ] Trash bin (30-day retention)
- [ ] Desktop support (macOS / Windows / Linux)

## License

Apache License 2.0 - see [LICENSE](LICENSE) file.
