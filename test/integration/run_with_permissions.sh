#!/bin/bash
# 运行 integration_test 前自动授权，避免每次都要手动点权限弹窗
# 用法: bash test/integration/run_with_permissions.sh [test_file]

DEVICE="6D0EA366-A494-46D2-89C1-58D8A7D5AEE5"
BUNDLE="com.seephoto.seePhoto"
TEST="${1:-integration_test/app_test.dart}"

echo "==> Granting permissions..."
xcrun simctl privacy "$DEVICE" grant photos "$BUNDLE"         2>/dev/null
xcrun simctl privacy "$DEVICE" grant photos-add "$BUNDLE"    2>/dev/null

export PATH="$HOME/development/flutter/bin:$PATH"
echo "==> Running integration test: $TEST"
cd "$HOME/../Work/see-photo" 2>/dev/null || cd "$(dirname "$0")/../.."
flutter test "$TEST" -d "$DEVICE"
