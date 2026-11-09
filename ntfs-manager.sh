#!/bin/bash
# NTFS 硬盘管理器 - 免费开源方案 (FUSE-T + ntfs-3g)
# 功能：自动检测、挂载、卸载、速度测试
# 适用: Apple Silicon / Intel, macOS 13+

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置
NTFS_3G="/usr/local/bin/ntfs-3g"
NTFS_INFO="/usr/local/bin/ntfsinfo"
MOUNT_DIR="$HOME/ntfs"
LOG_FILE="$HOME/.ntfs-manager.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查依赖
check_deps() {
    local missing=()

    if [ ! -x "$NTFS_3G" ]; then
        missing+=("ntfs-3g")
    fi

    if [ ! -x "$NTFS_INFO" ]; then
        missing+=("ntfsinfo")
    fi

    if ! command -v diskutil &> /dev/null; then
        missing+=("diskutil")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ 缺少依赖: ${missing[*]}${NC}"
        echo -e "${YELLOW}请先运行安装脚本: sudo bash install.sh${NC}"
        return 1
    fi

    return 0
}

# 扫描 NTFS 磁盘
scan_ntfs() {
    echo -e "${CYAN}🔍 扫描 NTFS 磁盘...${NC}"
    echo

    local disks=()
    local index=1

    # 获取所有外部磁盘
    while IFS= read -r line; do
        local dev=$(echo "$line" | awk '{print $1}')
        local info=$(diskutil info "$dev" 2>/dev/null)

        # 检查是否是 NTFS
        if echo "$info" | grep -q "File System Personality: NTFS"; then
            local name=$(echo "$info" | grep "Volume Name" | awk -F: '{print $2}' | xargs)
            local mount_point=$(echo "$info" | grep "Mount Point" | awk -F: '{print $2}' | xargs)
            local protocol=$(echo "$info" | grep "Protocol" | awk -F: '{print $2}' | xargs)
            local size=$(echo "$info" | grep "Disk Size" | awk -F: '{print $2}' | xargs)

            # 检查是否已挂载且可写
            local status="📦 未挂载"
            if [ -n "$mount_point" ]; then
                if mount | grep -q "$dev.*rw"; then
                    status="${GREEN}✅ 已挂载 (读写)${NC}"
                else
                    status="${YELLOW}⚠️  已挂载 (只读)${NC}"
                fi
            fi

            echo -e "${BLUE}[$index]${NC} $dev"
            echo -e "    名称: ${GREEN}$name${NC}"
            echo -e "    协议: $protocol"
            echo -e "    大小: $size"
            echo -e "    状态: $status"
            [ -n "$mount_point" ] && echo -e "    挂载点: $mount_point"
            echo

            disks+=("$dev")
            ((index++))
        fi
    done < <(diskutil list external | grep "/dev/disk" | grep -v " EFI")

    if [ ${#disks[@]} -eq 0 ]; then
        echo -e "${YELLOW}📭 未检测到 NTFS 磁盘${NC}"
        echo -e "  提示: 请插入 Windows 格式的外接硬盘"
        return 1
    fi

    echo -e "${CYAN}共检测到 ${#disks[@]} 个 NTFS 磁盘${NC}"
    return 0
}

# 挂载 NTFS 磁盘
mount_ntfs() {
    local dev="$1"

    if [ -z "$dev" ]; then
        echo -e "${RED}❌ 请指定设备，如: $0 mount /dev/disk4s1${NC}"
        return 1
    fi

    # 确认是 NTFS (使用 diskutil，不需要 root)
    local fs_info=$(diskutil info "$dev" 2>/dev/null | grep "File System Personality")
    if ! echo "$fs_info" | grep -q "NTFS"; then
        echo -e "${RED}❌ $dev 不是 NTFS 卷${NC}"
        return 1
    fi

    local name=$(diskutil info "$dev" 2>/dev/null | grep "Volume Name" | awk -F: '{print $2}' | xargs)
    [ -z "$name" ] && name="NTFS_Disk"

    # 创建挂载点
    mkdir -p "$MOUNT_DIR/$name"

    echo -e "${CYAN}📦 挂载 $name ($dev)...${NC}"

    # 先卸载系统只读挂载
    diskutil unmount "$dev" 2>/dev/null || true

    # 使用 ntfs-3g 挂载
    if $NTFS_3G "$dev" "$MOUNT_DIR/$name" -o local,auto_xattr,allow_other; then
        echo -e "${GREEN}✅ 挂载成功: $MOUNT_DIR/$name${NC}"
        log "Mounted $dev at $MOUNT_DIR/$name"

        # 在 Finder 中打开
        open "$MOUNT_DIR/$name"
        return 0
    else
        echo -e "${RED}❌ 挂载失败${NC}"
        log "Failed to mount $dev"
        return 1
    fi
}

# 卸载 NTFS 磁盘
unmount_ntfs() {
    local dev="$1"

    if [ -z "$dev" ]; then
        echo -e "${RED}❌ 请指定设备，如: $0 unmount /dev/disk4s1${NC}"
        return 1
    fi

    echo -e "${CYAN}📤 卸载 $dev...${NC}"

    # 查找挂载点
    local mount_point=$(mount | grep "$dev" | awk '{print $3}')

    if [ -n "$mount_point" ]; then
        # 尝试正常卸载
        if umount "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}✅ 已卸载: $mount_point${NC}"
            log "Unmounted $dev from $mount_point"
        else
            # 强制卸载
            echo -e "${YELLOW}⚠️  正在强制卸载...${NC}"
            umount -f "$mount_point" 2>/dev/null || diskutil unmount force "$dev" 2>/dev/null
            echo -e "${GREEN}✅ 已强制卸载${NC}"
            log "Force unmounted $dev"
        fi
    else
        echo -e "${YELLOW}ℹ️  磁盘未挂载${NC}"
    fi
}

# 弹出磁盘
eject_ntfs() {
    local dev="$1"

    if [ -z "$dev" ]; then
        echo -e "${RED}❌ 请指定设备，如: $0 eject /dev/disk4s1${NC}"
        return 1
    fi

    echo -e "${CYAN}⏏️  弹出 $dev...${NC}"

    # 先卸载
    unmount_ntfs "$dev"

    # 安全弹出
    if diskutil eject "$dev" 2>/dev/null; then
        echo -e "${GREEN}✅ 已安全弹出${NC}"
        log "Ejected $dev"
    else
        echo -e "${RED}❌ 弹出失败，请手动拔出${NC}"
        return 1
    fi
}

# 速度测试
speed_test() {
    local dev="$1"
    local test_dir="/tmp/ntfs-speed-test"
    local test_file="$test_dir/speedtest.bin"
    local test_size=100  # MB

    echo -e "${CYAN}🏎️  速度测试 ($test_size MB)...${NC}"

    # 创建测试目录
    mkdir -p "$test_dir"

    # 生成测试文件
    echo -e "  生成测试数据..."
    dd if=/dev/urandom of="$test_file" bs=1m count=$test_size 2>/dev/null

    # 创建临时挂载点
    local tmp_mount="$test_dir/mount"
    mkdir -p "$tmp_mount"

    # 挂载
    echo -e "  挂载磁盘..."
    diskutil unmount "$dev" 2>/dev/null || true
    if ! $NTFS_3G "$dev" "$tmp_mount" -o local,auto_xattr; then
        echo -e "${RED}❌ 无法挂载进行测试${NC}"
        rm -rf "$test_dir"
        return 1
    fi

    # 写入速度测试
    echo -e "  测试写入速度..."
    local start=$(date +%s.%N)
    cp "$test_file" "$tmp_mount/"
    sync
    local end=$(date +%s.%N)
    local write_time=$(echo "$end - $start" | bc)
    local write_speed=$(echo "scale=1; $test_size / $write_time" | bc)
    echo -e "  ${GREEN}写入: ${write_speed} MB/s${NC}"

    # 读取速度测试
    echo -e "  测试读取速度..."
    purge 2>/dev/null || true
    start=$(date +%s.%N)
    cp "$tmp_mount/speedtest.bin" /dev/null
    end=$(date +%s.%N)
    local read_time=$(echo "$end - $start" | bc)
    local read_speed=$(echo "scale=1; $test_size / $read_time" | bc)
    echo -e "  ${GREEN}读取: ${read_speed} MB/s${NC}"

    # 清理
    rm -f "$tmp_mount/speedtest.bin"
    umount "$tmp_mount" 2>/dev/null || true
    rm -rf "$test_dir"

    log "Speed test: write=${write_speed}MB/s read=${read_speed}MB/s"
}

# 显示帮助
show_help() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           NTFS 硬盘管理器 (免费开源版)                 ║${NC}"
    echo -e "${CYAN}║           FUSE-T + ntfs-3g，无内核扩展                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}用法:${NC}"
    echo -e "  $0 ${GREEN}scan${NC}                    扫描 NTFS 磁盘"
    echo -e "  $0 ${GREEN}list${NC}                    列出所有 NTFS 磁盘"
    echo -e "  $0 ${GREEN}mount${NC} <设备>             挂载磁盘 (读写模式)"
    echo -e "  $0 ${GREEN}unmount${NC} <设备>           卸载磁盘"
    echo -e "  $0 ${GREEN}eject${NC} <设备>             安全弹出磁盘"
    echo -e "  $0 ${GREEN}test${NC} <设备>              速度测试"
    echo -e "  $0 ${GREEN}open${NC} <设备>              在 Finder 中打开"
    echo -e "  $0 ${GREEN}status${NC}                   显示挂载状态"
    echo -e "  $0 ${GREEN}install${NC}                  安装依赖"
    echo
    echo -e "${YELLOW}示例:${NC}"
    echo -e "  $0 scan"
    echo -e "  $0 mount /dev/disk4s1"
    echo -e "  $0 eject /dev/disk4s1"
    echo
    echo -e "${YELLOW}挂载点:${NC} $MOUNT_DIR/<磁盘名称>"
    echo -e "${YELLOW}日志:${NC}   $LOG_FILE"
}

# 显示状态
show_status() {
    echo -e "${CYAN}📊 NTFS 挂载状态${NC}"
    echo

    local count=0
    while IFS= read -r line; do
        local dev=$(echo "$line" | awk '{print $1}')
        local info=$(diskutil info "$dev" 2>/dev/null)

        if echo "$info" | grep -q "File System Personality: NTFS"; then
            local name=$(echo "$info" | grep "Volume Name" | awk -F: '{print $2}' | xargs)
            local mount_point=$(echo "$info" | grep "Mount Point" | awk -F: '{print $2}' | xargs)

            if [ -n "$mount_point" ]; then
                if mount | grep -q "$dev.*rw"; then
                    echo -e "${GREEN}✅ $name${NC} ($dev)"
                    echo -e "   挂载点: $mount_point"
                    echo -e "   模式: 读写"
                else
                    echo -e "${YELLOW}⚠️  $name${NC} ($dev)"
                    echo -e "   挂载点: $mount_point"
                    echo -e "   模式: 只读"
                fi
                ((count++))
            fi
        fi
    done < <(diskutil list external | grep "/dev/disk" | grep -v " EFI")

    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}📭 没有已挂载的 NTFS 磁盘${NC}"
    else
        echo
        echo -e "共 $count 个已挂载"
    fi
}

# 安装依赖
install_deps() {
    echo -e "${CYAN}📦 安装 NTFS 支持依赖...${NC}"

    # 检查 Homebrew
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}⚠️  未检测到 Homebrew，正在安装...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # 安装 FUSE-T
    echo -e "  安装 FUSE-T..."
    brew tap macos-fuse-t/homebrew-cask 2>/dev/null || true
    brew install --cask fuse-t

    # 安装编译工具
    echo -e "  安装编译工具..."
    brew install autoconf automake libtool pkg-config gettext libgcrypt gnutls

    # 克隆并编译 ntfs-3g
    echo -e "  编译 ntfs-3g..."
    local work_dir="$HOME/.ntfs-build"
    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    git clone --depth 1 https://github.com/macos-fuse-t/ntfs-3g "$work_dir/ntfs-3g"
    cd "$work_dir/ntfs-3g"

    export PATH="/opt/homebrew/opt/gettext/bin:/opt/homebrew/bin:$PATH"
    export ACLOCAL_PATH="/opt/homebrew/share/aclocal:/opt/homebrew/opt/libgcrypt/share/aclocal:/opt/homebrew/opt/gettext/share/aclocal"
    export CPPFLAGS="-I/usr/local/include/fuse"
    export LDFLAGS="-L/usr/local/lib -lfuse-t -Wl,-rpath,/usr/local/lib"

    ./autogen.sh
    ./configure --prefix=/usr/local --exec-prefix=/usr/local \
      --with-fuse=external --sbindir=/usr/local/bin --bindir=/usr/local/bin
    make -j"$(sysctl -n hw.ncpu)"

    sudo make install

    echo
    echo -e "${GREEN}✅ 安装完成！${NC}"
    echo -e "${YELLOW}⚠️  首次使用请到 系统设置 > 隐私与安全性 > 完全磁盘访问 里放行 fuse-t${NC}"

    cd -
    rm -rf "$work_dir"
}

# 主函数
main() {
    # 检查依赖（install 命令除外）
    if [ "$1" != "install" ] && [ "$1" != "--help" ] && [ "$1" != "-h" ]; then
        check_deps || exit 1
    fi

    case "${1:-help}" in
        scan|s)
            scan_ntfs
            ;;
        list|ls)
            scan_ntfs
            ;;
        mount|mnt)
            mount_ntfs "$2"
            ;;
        unmount|umount)
            unmount_ntfs "$2"
            ;;
        eject|e)
            eject_ntfs "$2"
            ;;
        test|t)
            speed_test "$2"
            ;;
        open|o)
            if [ -n "$2" ]; then
                local name=$($NTFS_INFO -m "$2" 2>/dev/null | grep 'Volume Name' | awk -F: '{print $2}' | xargs)
                [ -n "$name" ] && open "$MOUNT_DIR/$name" || echo -e "${RED}❌ 无法获取磁盘名称${NC}"
            else
                open "$MOUNT_DIR" 2>/dev/null || echo -e "${YELLOW}ℹ️  挂载目录不存在${NC}"
            fi
            ;;
        status)
            show_status
            ;;
        install)
            install_deps
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}❌ 未知命令: $1${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
}

main "$@"
