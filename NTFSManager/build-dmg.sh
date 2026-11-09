#!/bin/bash
# 打包成可分发的 DMG：dist/NTFS Flow-<版本>.dmg
set -e
cd "$(dirname "$0")"
bash build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/NTFS Flow.app/Contents/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "build/NTFS Flow.app" "$STAGE/"
ln -s /Applications "$STAGE/应用程序"
cp 使用说明.txt "$STAGE/使用说明.txt"

mkdir -p dist
DMG="dist/NTFS Flow-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "NTFS Flow" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✅ 已生成 $DMG ($(du -h "$DMG" | cut -f1))"
