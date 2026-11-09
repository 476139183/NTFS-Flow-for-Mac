#!/bin/bash
# 一键安装 NTFS 读写驱动（以 root 运行）：
#   1. FUSE-T：没装就从官方 GitHub 下载安装包，校验 Apple 签名后安装
#   2. ntfs-3g / ntfsfix：从 App 内置的预编译版本安装到 /usr/local
# 用法：install-driver.sh <App 内 driver 目录>
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

FUSET_VERSION=1.2.9
FUSET_URL="https://github.com/macos-fuse-t/fuse-t/releases/download/$FUSET_VERSION/fuse-t-macos-installer-$FUSET_VERSION.pkg"
FUSET_DIR="/Library/Application Support/fuse-t"
DRIVER_DIR="${1:?缺少 driver 目录参数}"

step() { echo "==> $*"; }
die() { echo "❌ $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "需要以 root 运行"
[ "$(uname -m)" = arm64 ] || die "内置驱动只支持 Apple Silicon（M 系列芯片）Mac"
[ -f "$DRIVER_DIR/ntfs-3g" ] || die "找不到内置驱动：$DRIVER_DIR"

# ---------- FUSE-T ----------
if [ -x "$FUSET_DIR/bin/go-nfsv4" ]; then
    step "FUSE-T 已安装，跳过"
else
    step "下载 FUSE-T $FUSET_VERSION"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    PKG="$TMP/fuse-t.pkg"
    curl -fL --retry 3 --connect-timeout 15 -o "$PKG" "$FUSET_URL" || die "下载 FUSE-T 失败，请检查网络（需要能访问 github.com）"

    step "校验安装包签名"
    SIG=$(pkgutil --check-signature "$PKG" 2>&1) || die "FUSE-T 安装包签名无效"
    echo "$SIG" | grep -q "Developer ID Installer: .*(6DY7Z4SVDZ)" || die "FUSE-T 安装包签名者不是 FUSE-T 官方，已中止"
    echo "$SIG" | grep -q "trusted by the Apple notary service" || die "FUSE-T 安装包未经 Apple 公证，已中止"
    echo "$SIG" | grep -q "signed by a developer certificate issued by Apple" || die "FUSE-T 安装包签名不受 Apple 信任，已中止"

    step "安装 FUSE-T"
    installer -pkg "$PKG" -target / || die "安装 FUSE-T 失败"
fi

# ntfs-3g 通过 @rpath(/usr/local/lib) 找 libfuse-t.dylib，FUSE-T 安装脚本一般会放好，缺了就补链接
mkdir -p /usr/local/bin /usr/local/lib
if [ ! -e /usr/local/lib/libfuse-t.dylib ]; then
    LIB=$(ls "$FUSET_DIR"/lib/libfuse-t-*.dylib 2>/dev/null | sort -V | tail -1)
    [ -n "$LIB" ] || die "FUSE-T 安装不完整：找不到 libfuse-t"
    ln -sf "$LIB" /usr/local/lib/libfuse-t.dylib
fi

# ---------- ntfs-3g ----------
step "安装 ntfs-3g"
install -o root -g wheel -m 755 "$DRIVER_DIR/libntfs-3g.89.dylib" /usr/local/lib/libntfs-3g.89.dylib
ln -sf libntfs-3g.89.dylib /usr/local/lib/libntfs-3g.dylib
for bin in ntfs-3g ntfsfix; do
    install -o root -g wheel -m 755 "$DRIVER_DIR/$bin" "/usr/local/bin/$bin"
done
xattr -c /usr/local/lib/libntfs-3g.89.dylib /usr/local/bin/ntfs-3g /usr/local/bin/ntfsfix 2>/dev/null || true

step "验证"
/usr/local/bin/ntfs-3g --help 2>&1 | grep -qi "ntfs-3g" || die "ntfs-3g 无法运行"
echo "✅ 驱动安装完成"
