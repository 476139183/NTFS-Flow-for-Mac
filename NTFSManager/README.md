# NTFS 管理器（macOS 原生应用）

Swift + SwiftUI 写的 NTFS 读写管理工具，底层用 FUSE-T + ntfs-3g（先用上级目录的 `ntfs-setup.sh` 装好）。
设计参考了 ntfs-mounter-macos、Nigate、ntfs-automount-rw。

## 功能
- 自动发现 NTFS 盘（插拔实时刷新），显示 只读 / 读写 / 未挂载 状态和容量
- 一键读写挂载到 `/Volumes/<卷名>`，Finder 侧边栏可见；挂载后关闭 Spotlight 索引，避免文件被占用
- 卸载、切回系统只读、安全弹出、全部挂载 / 全部弹出
- Windows 休眠 / 快速启动导致拒绝挂载时，提示原因并可选「强制挂载」（remove_hiberfile）
- 修复脏卷标记（ntfsfix -d）
- 免密码挂载（可选开关）
- 菜单栏常驻，关掉主窗口不退出；可选「插入后自动读写挂载」「登录时启动」

## 构建
```bash
bash build-app.sh            # 生成 build/NTFS管理器.app
bash build-app.sh install    # 并安装到 /Applications
```
## 打包分发
```bash
bash build-dmg.sh            # 生成 dist/NTFS管理器-<版本>.dmg，可直接发给别人
```
DMG 内含 App、「应用程序」快捷方式和 `使用说明.txt`。App 内置本机编译的 ntfs-3g（仅 Apple Silicon），
对方首次打开后点「一键安装驱动」：从官方下载 FUSE-T（校验 Apple 公证 + 官方 Team ID）并安装内置 ntfs-3g，无需 Homebrew、无需编译。
没有 Developer ID 签名，对方第一次打开需在 系统设置 › 隐私与安全性 点「仍要打开」。
版本号改 `build-app.sh` 里的 `CFBundleShortVersionString`。

应用图标源文件为 `Resources/AppIcon.png`，打包时自动生成多分辨率 `AppIcon.icns`。
运行时也会设置 Dock 图标，避免继续显示缓存的默认图标。

默认使用临时签名。正式分发时可设置 `CODE_SIGN_IDENTITY` 为自己的签名身份，
例如 `CODE_SIGN_IDENTITY='Developer ID Application: …' bash build-app.sh`。
重新临时签名后，macOS 可能要求重新授权文件访问；固定 Bundle ID 本身不能保证授权延续。

命令行排查：`build/NTFS管理器.app/Contents/MacOS/NTFSManager --list`

## 代码结构与回归测试

- `NTFSDisk`：磁盘数据模型。
- `DiskStore`：主线程 UI 状态和操作编排。
- `DiskOperationCoordinator`：整盘互斥，防止兄弟分区操作冲突。
- `DiskWatcher`：磁盘事件监听。
- `DiskService`：系统元数据扫描、挂载和卸载。
- `DiskMountResolver`：结合 FUSE-T 挂载源和进程参数匹配实际挂载点，避免把系统只读副本误认为唯一挂载。
- `DiskErrors`：权限、I/O、脏卷和明确休眠错误分类。
- `Shell` / `Privilege`：进程执行和特权助手调用。

运行 `swift test --disable-sandbox` 验证错误分类、整盘互斥、磁盘列表解析、命令输出、超时和图标解码。
测试不会挂载、修复或写入外置硬盘。

后台容量查询使用内核缓存的挂载表，不主动打开网络卷；缓存容量可能稍有延迟。
扫描失败会保留最后一次成功结果并显示错误，不会伪装成“没有检测到磁盘”。

## 网络宗卷授权

FUSE-T 的读写驱动通过本机 NFS 提供挂载，macOS 因而可能显示“访问网络宗卷”提示。
首次打开磁盘时允许即可；若之前拒绝，可到 系统设置 › 隐私与安全性 › 文件与文件夹，
开启「NTFS 管理器」的网络宗卷访问。该权限与管理员授权、完全磁盘访问权限是不同的权限。

## 免密码挂载
勾选窗口底部「免密码挂载」，输一次密码后，挂载/卸载/修复都不再弹密码框。它做了两件事：
- 把 `Resources/ntfs-manager-helper` 装到 `/Library/PrivilegedHelperTools/`（root 所有，普通进程改不了）
- 写 `/etc/sudoers.d/ntfs-manager`，只放行这一个助手（visudo 校验通过才生效）

助手只接受 `mount <diskXsY> [force]`、`unmount </Volumes/名称>`、`fix <diskXsY>`，
挂载点和选项由助手自己决定，不能被利用来挂到系统目录提权。没有直接给 ntfs-3g 开免密，就是为了这个。
取消勾选会删除这两个文件。App 更新后若助手有变化，开关旁会出现「更新助手」。

手动撤销：`sudo rm /etc/sudoers.d/ntfs-manager /Library/PrivilegedHelperTools/ntfs-manager-helper`

## 注意
- 未开启免密时，挂载/卸载需要 root，会弹系统管理员密码框。
- 若报 “Operation not permitted”：系统设置 › 隐私与安全性 › 完全磁盘访问权限，加入「NTFS 管理器」。重新打包后签名会变，可能要重新勾选。
- 首次使用要在 系统设置 › 隐私与安全性 里放行 fuse-t。
