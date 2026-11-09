#!/bin/bash
# 将现有 GitHub 仓库更名为 NTFS-Flow-for-Mac，更新项目简介和主题，并推送 main。
set -euo pipefail
cd "$(dirname "$0")/.."

OLD_REPO="476139183/ntfs-manager"
PREVIOUS_REPO="476139183/ntfs-flow"
NEW_REPO="476139183/NTFS-Flow-for-Mac"
DESCRIPTION="NTFS Flow for Mac: open-source macOS NTFS read/write manager. Native SwiftUI menu bar app powered by FUSE-T and ntfs-3g. Mac NTFS 硬盘读写工具。"

command -v gh >/dev/null || { echo "请先安装 GitHub CLI：brew install gh" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || {
    echo "请先提交当前改动，再运行发布脚本。" >&2
    exit 1
}
case "$(git remote get-url origin)" in
    "https://github.com/$OLD_REPO.git"|"https://github.com/$PREVIOUS_REPO.git"|"https://github.com/$NEW_REPO.git"|"git@github.com:$OLD_REPO.git"|"git@github.com:$PREVIOUS_REPO.git"|"git@github.com:$NEW_REPO.git") ;;
    *) echo "origin 不是预期的 NTFS Flow 仓库，已中止。" >&2; exit 1 ;;
esac

# 仓库更名后，旧地址会重定向；据此支持重复执行，并避免覆盖同名仓库。
CURRENT_REPO=$(gh api "repos/$OLD_REPO" --jq .full_name)
case "$CURRENT_REPO" in
    "$OLD_REPO"|"$PREVIOUS_REPO") gh repo rename "${NEW_REPO##*/}" --repo "$CURRENT_REPO" --yes ;;
    "$NEW_REPO") ;;
    *) echo "GitHub 返回了非预期的仓库：$CURRENT_REPO" >&2; exit 1 ;;
esac

gh repo edit "$NEW_REPO" --description "$DESCRIPTION" \
    --add-topic macos --add-topic ntfs --add-topic ntfs-for-mac \
    --add-topic ntfs-macos --add-topic ntfs-3g --add-topic fuse-t \
    --add-topic swift --add-topic swiftui --add-topic menu-bar \
    --add-topic apple-silicon --add-topic disk-management --add-topic read-write

git remote set-url origin "https://github.com/$NEW_REPO.git"
git push --set-upstream origin main
echo "已发布：https://github.com/$NEW_REPO"
