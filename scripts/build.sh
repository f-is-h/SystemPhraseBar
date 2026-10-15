#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
version="$(tr -d '\n' < "$task_root/VERSION")"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 1; }
app="$task_root/build/SystemPhraseBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$task_root/build/module-cache"
icon="$task_root/build/AppIcon.iconset"
if [[ ! -f "$app/Contents/Resources/AppIcon.icns" || "$task_root/scripts/make-icon.swift" -nt "$app/Contents/Resources/AppIcon.icns" ]]; then
  xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/scripts/make-icon.swift" -o "$task_root/build/make-icon"
  "$task_root/build/make-icon" "$icon"
  iconutil -c icns "$icon" -o "$app/Contents/Resources/AppIcon.icns"
fi
xcrun clang -fobjc-arc -fblocks -fmodules \
  -fmodules-cache-path="$task_root/build/module-cache" \
  -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 \
  -framework Cocoa -framework ServiceManagement -lsqlite3 \
  "$task_root/Sources/SystemStore.m" "$task_root/Sources/AppServices.m" "$task_root/Sources/Panel.m" "$task_root/Sources/Language.m" "$task_root/Sources/BackupRetention.m" "$task_root/Sources/Appearance.m" "$task_root/Sources/ReviewTests.m" "$task_root/Sources/main.m" \
  -o "$app/Contents/MacOS/SystemPhraseBar"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SystemPhraseBar</string>
<key>CFBundleIdentifier</key><string>io.github.f-is-h.SystemPhraseBar</string>
<key>CFBundleName</key><string>SystemPhraseBar</string>
<key>CFBundleDisplayName</key><string>SystemPhraseBar</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
for language in en zh-Hans; do
  mkdir -p "$app/Contents/Resources/$language.lproj"
  cp "$task_root/Resources/$language.lproj/Localizable.strings" "$app/Contents/Resources/$language.lproj/Localizable.strings"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf '%s\n' "$app"
