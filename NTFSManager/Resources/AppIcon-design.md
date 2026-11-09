# 应用图标

设计方向：macOS 蓝色圆角底板、银色外置硬盘、青色与白色双向箭头，表达 NTFS 读写；透明外边距，无文字。

使用内置 image_gen 生成。AppIcon.png 是原始设计图；运行 `bash build-icon.sh` 将其缩放并封装为包含 16–1024px 资源的 AppIcon.icns。`build-app.sh` 会自动生成、复制图标并配置 CFBundleIconFile。

生成提示词：

> Use case: logo-brand. Create a single production-ready macOS application icon for NTFS Manager, an external disk read/write utility. Square 1024 by 1024 canvas, transparent outside the icon. Large macOS rounded-square tile inset with comfortable transparent padding, deep cobalt-to-navy blue subtle gradient, refined softly bevelled edges. Center a beautifully crafted satin silver external SSD enclosure viewed almost straight on with slight dimensional depth, rounded corners, subtle seam and tiny green status light. In front of the drive, two bold opposing horizontal arrows, one cyan pointing right and one white pointing left, expressing read and write. Restrained premium native macOS aesthetic, crisp silhouette, excellent legibility at 32 pixels, balanced composition, soft realistic lighting. No text, letters, numbers, watermark, decorative objects, cables or background scene. Deliver just one icon, no mockup or contact sheet.
