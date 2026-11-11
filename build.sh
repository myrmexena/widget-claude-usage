#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="ClaudeUsage.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O ClaudeUsage.swift -o "$APP/Contents/MacOS/ClaudeUsage"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ClaudeUsage</string>
<key>CFBundleIdentifier</key><string>local.claude-usage</string>
<key>CFBundleExecutable</key><string>ClaudeUsage</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP — lance avec: open $APP"
