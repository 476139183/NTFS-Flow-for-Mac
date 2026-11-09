#!/bin/bash
# 从 1024px PNG 生成 macOS 标准多分辨率应用图标。
set -euo pipefail
cd "$(dirname "$0")"
SOURCE="Resources/AppIcon.png"
ICONSET=$(mktemp -d "${TMPDIR:-/tmp}/ntfs-icon.XXXXXX")
trap 'rm -rf "$ICONSET"' EXIT
mkdir -p "$ICONSET/AppIcon.iconset"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# 将 PNG 封装为 ICNS；不依赖图形会话中的 IconServices。
python3 - "$ICONSET/AppIcon.iconset" Resources/AppIcon.icns <<'PY'
from pathlib import Path
import struct
import sys

source = Path(sys.argv[1])
entries = [
    (b'icp4', 'icon_16x16.png'),
    (b'ic11', 'icon_16x16@2x.png'),
    (b'icp5', 'icon_32x32.png'),
    (b'ic12', 'icon_32x32@2x.png'),
    (b'ic07', 'icon_128x128.png'),
    (b'ic13', 'icon_128x128@2x.png'),
    (b'ic08', 'icon_256x256.png'),
    (b'ic14', 'icon_256x256@2x.png'),
    (b'ic09', 'icon_512x512.png'),
    (b'ic10', 'icon_512x512@2x.png'),
]
chunks = []
for kind, name in entries:
    data = (source / name).read_bytes()
    chunks.append(kind + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
PY
echo "已生成 Resources/AppIcon.icns"
