# See-Photo

Cross-platform photo archiving app with end-to-end encryption and S3-compatible backend.

## Features

- **End-to-End Encryption**: Files encrypted on-device with XChaCha20-Poly1305 before upload. Backend never sees plaintext.
- **S3 Backend**: Supports any S3-compatible storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces, Wasabi).
- **TTL Auto-Archiving**: Configurable time-based (e.g., photos older than 30 days) and size-based (e.g., when local > 100 GiB, archive oldest) triggers.
- **Cross-Platform**: iOS, Android, macOS, Windows, Linux — single Flutter codebase.
- **Zero-Knowledge**: Server has no access to files, filenames, or thumbnails. Everything is encrypted client-side.

## Architecture

```
┌───────────────────────────────────────────────┐
│                  Flutter App                    │
│  ┌─────────┐ ┌──────────┐ ┌────────────────┐  │
│  │ Gallery  │ │  Cloud    │ │ Archive Status │  │
│  │ (Local)  │ │  Gallery  │ │   Dashboard    │  │
│  └────┬─────┘ └────┬─────┘ └───────┬────────┘  │
│       │             │              │            │
│  ┌────┴─────────────┴──────────────┴─────────┐ │
│  │         Domain Layer (Pure Dart)           │ │
│  │   Entities, Use Cases, Repository Ifaces   │ │
│  └────────────────────┬──────────────────────┘ │
│                       │                        │
│  ┌────────────────────┼──────────────────────┐ │
│  │              Services Layer               │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐  │ │
│  │  │  Crypto   │ │   S3     │ │   TTL    │  │ │
│  │  │ (libsodium)│ │ (minio)  │ │  Engine  │  │ │
│  │  └──────────┘ └──────────┘ └──────────┘  │ │
│  └────────────────────┬──────────────────────┘ │
│                       │                        │
│  ┌────────────────────┴──────────────────────┐ │
│  │             Data Layer                     │ │
│  │  ┌──────────────────────────────────────┐ │ │
│  │  │   Drift (encrypted SQLite)            │ │ │
│  │  │   media_files, ttl_config,            │ │ │
│  │  │   storage_config, transfer_queue      │ │ │
│  │  └──────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────┘ │
└───────────────────────┬─────────────────────────┘
                        │ HTTPS (TLS + cert pinning)
                        ▼
              ┌─────────────────┐
              │  S3-Compatible   │
              │     Storage      │
              │                  │
              │  files/*/*.enc   │  (encrypted blobs)
              │  thumbs/*.enc    │  (encrypted thumbs)
              └─────────────────┘
```

### Encryption Scheme

```
User Passphrase
     │ Argon2id (64 MiB, 3 iter, 4 parallel)
     ▼
   KEK (256-bit) ──── wrapped with device HW key ──► Secure Storage
     │
     │ unwrap when needed
     ▼
Per-file: random DEK ──► XChaCha20-Poly1305 ──► encrypted file → S3
           DEK wrapped by KEK ──► S3 metadata (x-amz-meta-dek)
```

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| State Management | Riverpod 3 |
| Database | Drift (type-safe ORM) + encrypted SQLite |
| Crypto | libsodium (flutter_sodium via FFI) |
| S3 Client | minio (Dart) |
| Key Storage | iOS Secure Enclave / Android StrongBox |
| Background | workmanager + flutter_background_service |
| Photo Access | photo_manager |

## Project Structure

```
lib/
├── main.dart                     # Entry point
├── app.dart                      # App widget, theme, router
├── core/                         # Constants, errors, logging, router, theme, utils
├── domain/                       # Entities, repository interfaces, use cases (pure Dart)
├── data/                         # Database (Drift), datasources, repository impls
├── presentation/                 # Providers (Riverpod), screens, shared widgets
└── services/                     # Crypto, storage, background, biometric, thumbnail
```

## Getting Started

### Prerequisites

- Flutter SDK >= 3.5.0
- iOS: Xcode 16+
- Android: Android Studio + SDK 34+
- S3-compatible storage account (or local MinIO for testing)

### Setup

```bash
# Install Flutter (if not already)
# https://docs.flutter.dev/get-started/install

# Clone the repo
git clone <repo-url> see-photo
cd see-photo

# Run flutter create to generate platform files
flutter create .

# Install dependencies
flutter pub get

# Generate Drift/Riverpod code
dart run build_runner build

# Run on iOS simulator
flutter run -d ios
```

### Development Phases

| Phase | Scope | Status |
|---|---|---|
| 1. Foundation | Project scaffold, DB, crypto, S3 client | ✅ In Progress |
| 2. Local Gallery | Thumbnail grid, full-screen viewer | ⏳ Planned |
| 3. Archive Pipeline | TTL engine, transfer queue, auto-archive | ⏳ Planned |
| 4. Cloud Gallery | Cloud browse, on-demand download | ⏳ Planned |
| 5. Advanced TTL | Size-based trigger, cache, stats | ⏳ Planned |
| 6. Security | Biometric, cert pinning, hardening | ⏳ Planned |
| 7. Android | Android-specific adaptations | ⏳ Planned |
| 8. Desktop | macOS/Windows/Linux support | ⏳ Planned |

## License

Apache License 2.0 — see [LICENSE](LICENSE) file.
