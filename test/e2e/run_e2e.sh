#!/bin/bash
# 端到端测试运行脚本
# 用法: bash test/e2e/run_e2e.sh
set -e

export PATH="$HOME/development/flutter/bin:$PATH"
DEVICE="6D0EA366-A494-46D2-89C1-58D8A7D5AEE5"
BUNDLE="com.seephoto.seePhoto"

echo "==> Granting photo permissions..."
xcrun simctl privacy "$DEVICE" grant photos "$BUNDLE" 2>/dev/null || true

echo "==> Adding test photos..."
for i in 1 2 3; do
  xcrun simctl addmedia "$DEVICE" /tmp/photo$i.png 2>/dev/null || true
done

echo "==> Running E2E tests..."
flutter test integration_test/app_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST=true

echo "==> Done"
