#!/bin/bash
# NTFS 读写支持安装脚本 (FUSE-T + ntfs-3g，无内核扩展、不改 SIP)
# 适用: Apple Silicon / Intel, macOS 13+
set -e
WORK="$HOME/.ntfs-build"

echo "==> 1/4 安装 FUSE-T 和编译依赖（会要管理员密码）"
brew tap macos-fuse-t/homebrew-cask 2>/dev/null || true
brew install --cask fuse-t
brew install autoconf automake libtool pkg-config gettext libgcrypt gnutls

echo "==> 2/4 获取 ntfs-3g 源码"
rm -rf "$WORK"; mkdir -p "$WORK"
git clone --depth 1 https://github.com/macos-fuse-t/ntfs-3g "$WORK/ntfs-3g"
cd "$WORK/ntfs-3g"

echo "==> 3/4 编译"
export PATH="/opt/homebrew/opt/gettext/bin:/opt/homebrew/bin:$PATH"
export ACLOCAL_PATH="/opt/homebrew/share/aclocal:/opt/homebrew/opt/libgcrypt/share/aclocal:/opt/homebrew/opt/gettext/share/aclocal"
export CPPFLAGS="-I/usr/local/include/fuse"
export LDFLAGS="-L/usr/local/lib -lfuse-t -Wl,-rpath,/usr/local/lib"
./autogen.sh
./configure --prefix=/usr/local --exec-prefix=/usr/local \
  --with-fuse=external --sbindir=/usr/local/bin --bindir=/usr/local/bin
make -j"$(sysctl -n hw.ncpu)"

echo "==> 4/4 安装（会要管理员密码）"
sudo make install

echo
echo "✅ 完成。挂载方法："
echo "   diskutil list                     # 找到 NTFS 分区，如 /dev/disk4s1"
echo "   diskutil unmount /dev/disk4s1     # 先卸掉系统的只读挂载"
echo "   mkdir -p ~/ntfs"
echo "   sudo /usr/local/bin/ntfs-3g /dev/disk4s1 ~/ntfs -o local,allow_other,auto_xattr"
echo
echo "⚠️ 首次使用请到 系统设置 > 隐私与安全性 > 完全磁盘访问/网络卷 里放行 fuse-t"
