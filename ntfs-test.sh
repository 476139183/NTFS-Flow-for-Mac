#!/bin/bash
# FUSE-T + ntfs-3g 挂载层与速度实测
IMG="${1:-}"
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
  echo "用法: sudo bash ntfs-test.sh /绝对路径/测试镜像.img"
  echo "请使用可丢弃的 NTFS 测试镜像；此脚本会挂载镜像并写入测试文件。"
  exit 1
fi
IMG="$(cd "$(dirname "$IMG")" && pwd)/$(basename "$IMG")"
MP="$HOME/ntfs-test"
[ "$EUID" -ne 0 ] && { echo "请用 sudo bash ntfs-test.sh /绝对路径/测试镜像.img"; exit 1; }

# --- 正确解析 hdiutil info：设备行在 image-path 之后 ---
DEV=$(hdiutil info | awk -v img="$IMG" '
  /^image-path/ { inblk = ($0 ~ img) ? 1 : 0 }
  inblk && /^\/dev\/disk/ { print $1; exit }')
if [ -z "$DEV" ]; then
  echo "==> 镜像未挂载，重新 attach"
  DEV=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$IMG" | head -1 | awk '{print $1}')
fi
echo "块设备: $DEV"

# --- 关键：挂载前先确认它真的是 NTFS，防止指错盘 ---
if ! /usr/local/bin/ntfsinfo -m "$DEV" >/dev/null 2>&1; then
  echo "❌ $DEV 不是 NTFS，中止（避免误操作其他磁盘）"; exit 1
fi
echo "✅ 确认是 NTFS 卷: $(/usr/local/bin/ntfsinfo -m "$DEV" 2>/dev/null | grep 'Volume Name' | xargs)"

mkdir -p "$MP"
echo; echo "==> 挂载"
/usr/local/bin/ntfs-3g "$DEV" "$MP" -o local,auto_xattr,allow_other || { echo "❌ 挂载失败"; exit 1; }
sleep 2
mount | grep -q "$MP" && echo "✅ 挂载成功" || { echo "❌ 未出现在 mount 列表"; exit 1; }
mount | grep "$MP"

echo; echo "==> 卷内已有文件"; ls -la "$MP"

echo; echo "==> 写入速度 (200MB)"
dd if=/dev/urandom of=/tmp/_spd.bin bs=1m count=200 2>/dev/null
S=$(date +%s.%N); cp /tmp/_spd.bin "$MP/speed.bin"; sync; E=$(date +%s.%N)
W=$(echo "$E - $S" | bc); echo "耗时 ${W}s  →  $(echo "scale=1; 200/$W" | bc) MB/s"

echo; echo "==> 读取速度"
purge 2>/dev/null
S=$(date +%s.%N); cp "$MP/speed.bin" /tmp/_spd_back.bin; E=$(date +%s.%N)
R=$(echo "$E - $S" | bc); echo "耗时 ${R}s  →  $(echo "scale=1; 200/$R" | bc) MB/s"

echo; echo "==> 完整性校验"
A=$(shasum -a 256 /tmp/_spd.bin | awk '{print $1}')
B=$(shasum -a 256 /tmp/_spd_back.bin | awk '{print $1}')
[ "$A" = "$B" ] && echo "✅ sha256 一致，数据无损坏" || echo "❌ 数据不一致！"

echo; echo "==> 常见文件操作"
mkdir -p "$MP/测试目录" && echo "建目录(中文名): ✅"
echo hello > "$MP/测试目录/a.txt" && echo "写文件: ✅"
mv "$MP/测试目录/a.txt" "$MP/测试目录/b.txt" && echo "重命名: ✅"
cat "$MP/测试目录/b.txt" >/dev/null && echo "读取: ✅"
rm "$MP/测试目录/b.txt" && rmdir "$MP/测试目录" && echo "删除: ✅"

echo; echo "==> 清理"
rm -f "$MP/speed.bin" /tmp/_spd.bin /tmp/_spd_back.bin
umount "$MP" && echo "已卸载"
hdiutil detach "$DEV" >/dev/null 2>&1 && echo "已弹出镜像"
