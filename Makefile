.PHONY: test test-unit test-integration test-e2e analyze build-ios build-macos clean

DEVICE ?= 6D0EA366-A494-46D2-89C1-58D8A7D5AEE5

# CI tests (no device needed)
test-ci:
	flutter analyze
	flutter test test/unit/

# All device-less tests
test-unit:
	flutter test test/unit/

# Integration tests against real MinIO
test-integration:
	dart run test/integration/s3_client_test.dart
	dart run test/integration/upload_pipeline_test.dart

# UI integration tests on simulator
test-e2e:
	flutter test integration_test/app_test.dart -d $(DEVICE) --dart-define=INTEGRATION_TEST=true

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
