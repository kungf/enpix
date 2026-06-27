.PHONY: test test-unit test-integration test-e2e analyze build-ios build-macos clean

DEVICE ?= 6D0EA366-A494-46D2-89C1-58D8A7D5AEE5

# Load test environment variables
ENV = set -a && . ./.env.test && set +a

# CI tests (no device needed)
test-ci:
	flutter analyze
	flutter test test/unit/

# All device-less tests
test-unit:
	flutter test test/unit/

# Integration tests against real MinIO (requires .env.test)
test-integration:
	$(ENV) && dart run test/integration/s3_client_test.dart
	$(ENV) && dart run test/integration/upload_pipeline_test.dart
	$(ENV) && dart run test/integration/cloud_thumbnail_test.dart

# UI integration tests on simulator (requires .env.test)
test-e2e:
	$(ENV) && flutter test integration_test/app_test.dart -d $(DEVICE) --dart-define=INTEGRATION_TEST=true

# Full local test suite
test-all: test-unit test-integration test-e2e

# Static analysis
analyze:
	flutter analyze

# Build checks
build-ios:
	flutter build ios --no-codesign --debug

build-macos:
	flutter build macos --debug

# Clean
clean:
	flutter clean
	flutter pub get
