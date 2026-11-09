#!/bin/bash
# 编译并打包成 NTFS管理器.app，可选安装到 /Applications
#   bash build-app.sh            # 只打包到 ./build
#   bash build-app.sh install    # 打包并复制到 /Applications
set -e
cd "$(dirname "$0")"
APP="build/NTFS管理器.app"

# 受限构建环境可用 NTFS_DEBUG_INFO_FORMAT=none 跳过 dSYM 生成。
swift build -c release --disable-sandbox -debug-info-format "${NTFS_DEBUG_INFO_FORMAT:-dwarf}"
bash build-icon.sh
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NTFSManager "$APP/Contents/MacOS/NTFSManager"
cp Resources/ntfs-manager-helper "$APP/Contents/Resources/"
cp Resources/install-driver.sh "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/ntfs-manager-helper" "$APP/Contents/Resources/install-driver.sh"

# 内置驱动：本机编译好的 ntfs-3g（arm64，链接 /usr/local/lib 下的 libntfs-3g 和 FUSE-T）
DRV="$APP/Contents/Resources/driver"
mkdir -p "$DRV"
for f in /usr/local/bin/ntfs-3g /usr/local/bin/ntfsfix /usr/local/lib/libntfs-3g.89.dylib; do
    [ -f "$f" ] || { echo "❌ 缺少 $f，请先运行 ../ntfs-setup.sh 编译驱动"; exit 1; }
    cp "$f" "$DRV/"
done
cat > "$DRV/README.txt" <<TXT
ntfs-3g 2022.10.3（macos-fuse-t 分支），GPL-2.0 许可。
源码：https://github.com/macos-fuse-t/ntfs-3g
FUSE-T 不随包分发，安装时从 https://github.com/macos-fuse-t/fuse-t 官方下载，遵循其自身许可（非商业免费）。
TXT

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NTFS管理器</string>
    <key>CFBundleDisplayName</key><string>NTFS 管理器</string>
    <key>CFBundleIdentifier</key><string>local.ntfs-manager</string>
    <key>CFBundleExecutable</key><string>NTFSManager</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>用于弹出管理员授权框以挂载磁盘。</string>
    <key>NSNetworkVolumesUsageDescription</key><string>用于打开本机 NTFS 磁盘。读写驱动通过本机网络卷提供访问，不会将磁盘文件上传至网络。</string>
    <key>NSRemovableVolumesUsageDescription</key><string>用于访问您连接的 NTFS 移动硬盘和 U 盘。</string>
</dict>
</plist>
PLIST

# ad-hoc 签名：「完全磁盘访问」授权按签名识别，每次重新打包后若授权失效需重新勾选
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP"
echo "✅ 已生成 $APP"

if [ "$1" = "install" ]; then
    rm -rf "/Applications/NTFS管理器.app"
    cp -R "$APP" /Applications/
    echo "✅ 已安装到 /Applications/NTFS管理器.app"
fi
