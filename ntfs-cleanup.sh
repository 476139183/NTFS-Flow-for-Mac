#!/bin/bash
# 卸载失效的付费 NTFS 工具 (Tuxera + 赤友/iBoysoft)，保留免费的 FUSE-T + ntfs-3g
echo "================ 卸载付费 NTFS 工具 ================"
[ "$EUID" -ne 0 ] && { echo "请用 sudo 运行: sudo bash ~/Desktop/ntfs-cleanup.sh"; exit 1; }
REAL_UID=$(stat -f "%u" /dev/console)

echo; echo "==> 1/4 卸载 赤友NTFS助手 (官方卸载器)"
IB="/Applications/赤友NTFS助手.app/Contents/Resources/uninstall.sh"
if [ -f "$IB" ]; then bash "$IB" 2>&1 | grep -v "^$"; echo "赤友: 已执行"; else echo "赤友: 未找到，跳过"; fi

echo; echo "==> 2/4 卸载 Tuxera NTFS (官方卸载器)"
TX="/Library/Filesystems/tuxera_ntfs.fs/Contents/Resources/Support/uninstall-package.sh"
if [ -f "$TX" ]; then bash "$TX" --uid "$REAL_UID" 2>&1 | tail -20; else echo "Tuxera: 未找到，跳过"; fi

echo; echo "==> 3/4 清理残留"
for p in "/Library/Filesystems/tuxera_ntfs.fs" \
         "/Library/PreferencePanes/Tuxera NTFS.prefPane" \
         "/Library/Application Support/Tuxera NTFS" \
         "/Library/LaunchAgents/com.tuxera.ntfs.agent.plist" \
         "/Applications/Tuxera Disk Manager.app" \
         "/Library/Filesystems/iboysoft_NTFS.fs" \
         "/Applications/赤友NTFS助手.app"; do
  [ -e "$p" ] && { rm -rf "$p" && echo "已删除: $p"; }
done
pkill -9 -f "Tuxera" 2>/dev/null; pkill -9 -f "ntfsassistantd|ntfshelperd" 2>/dev/null
pkgutil --forget com.tuxera.pkg.Tuxera_NTFS 2>/dev/null
pkgutil --forget com.iboysoft.ntfsassistant-zh-website 2>/dev/null

echo; echo "==> 4/4 验证"
echo "--- /Library/Filesystems (应只剩 NetFSPlugins) ---"; ls /Library/Filesystems/
echo "--- 残留进程 ---"; pgrep -fl -i "tuxera|iboysoft|ntfsassist|ntfshelper" || echo "✅ 无残留进程"
echo "--- 免费方案是否完好 ---"
[ -x /usr/local/bin/ntfs-3g ] && echo "✅ ntfs-3g 正常: $(/usr/local/bin/ntfs-3g --version 2>&1 | head -1)" || echo "❌ ntfs-3g 丢失"
[ -d "/Library/Application Support/fuse-t" ] && echo "✅ fuse-t 正常" || echo "❌ fuse-t 丢失"
echo; echo "================ 完成，建议重启一次 ================"
