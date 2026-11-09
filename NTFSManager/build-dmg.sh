#!/bin/bash
# 打包成可分发的 DMG：dist/NTFS管理器-<版本>.dmg
set -e
cd "$(dirname "$0")"
bash build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/NTFS管理器.app/Contents/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "build/NTFS管理器.app" "$STAGE/"
ln -s /Applications "$STAGE/应用程序"
cp 使用说明.txt "$STAGE/使用说明.txt"

mkdir -p dist
DMG="dist/NTFS管理器-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "NTFS 管理器" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✅ 已生成 $DMG ($(du -h "$DMG" | cut -f1))"
