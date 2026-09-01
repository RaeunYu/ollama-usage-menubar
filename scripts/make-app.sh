#!/bin/bash
# Ollama Usage .app 번들 빌드 (ADR-0004: Xcode 프로젝트 없이 SPM)
# 사용법: scripts/make-app.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Ollama Usage"
BUNDLE_ID="com.yulaeun.ollama-usage-menubar"

swift build -c "$CONFIG" --product OllamaUsage

APP_DIR=".build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
mkdir -p "$CONTENTS/MacOS"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OllamaUsage</string>
    <key>CFBundleIdentifier</key><string>com.yulaeun.ollama-usage-menubar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cp ".build/$CONFIG/OllamaUsage" "$CONTENTS/MacOS/OllamaUsage"

# 무서명 개인용 — 애드혹 서명만 (키체인 접근 안정성을 위한 최소 코드사인)
codesign --force --sign - "$APP_DIR"

echo "빌드 완료: $APP_DIR"