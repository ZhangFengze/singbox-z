#!/bin/bash
set -e

# ==============================================================================
# 更新 sing-box 和 sing-tun 上游代码脚本
# 
# 用法:
# ./update_upstream.sh <sing-box版本标签>
# 例如:
# ./update_upstream.sh v1.15.0
# ==============================================================================

if [ -z "$1" ]; then
    echo "❌ 错误: 请提供要更新的 sing-box 版本标签 (例如: v1.15.0)"
    echo "用法: ./update_upstream.sh <版本标签>"
    exit 1
fi

TARGET_VERSION="$1"
WORKDIR=$(pwd)
TMPDIR=$(mktemp -d)

echo "🚀 开始更新到 sing-box $TARGET_VERSION..."

# 1. 备份你需要保留的自定文件/文件夹
echo "📦 正在备份你的自定义文件..."
cp -r .github "$TMPDIR/"
cp -r sing-tun "$TMPDIR/"
cp update_upstream.sh "$TMPDIR/"
[ -f sing-box-auto-redirect-fw4.md ] && cp sing-box-auto-redirect-fw4.md "$TMPDIR/"

# 2. 清理当前目录中所有不再需要的文件（除了 .git 和保留文件）
echo "🧹 清理旧版本的 sing-box 文件..."
# 开启 extglob 方便排除特定目录
shopt -s extglob
rm -rf !(.|..|.git|.cursor|.github|sing-tun|update_upstream.sh|sing-box-auto-redirect-fw4.md)

# 3. 克隆最新目标版本的 sing-box
echo "⬇️ 正在拉取官方 sing-box $TARGET_VERSION..."
git clone -b "$TARGET_VERSION" --depth 1 https://github.com/SagerNet/sing-box.git "$TMPDIR/sing-box"

# 4. 把新的 sing-box 源码移入根目录
echo "📂 将新版源码移入当前仓库..."
# 先删掉新版里的 .git 等没用的
rm -rf "$TMPDIR/sing-box/.git"
rm -rf "$TMPDIR/sing-box/.github" # 使用你的.github
cp -a "$TMPDIR/sing-box/"* "$WORKDIR/"
cp -a "$TMPDIR/sing-box/".* "$WORKDIR/" 2>/dev/null || true # 拷贝隐藏文件，忽略无匹配时的报错

# 5. 读取新版 sing-box 依赖的 sing-tun 哈希
echo "🔍 检查新版依赖的 sing-tun 版本..."
TUN_COMMIT=$(grep "github.com/sagernet/sing-tun" "$WORKDIR/go.mod" | awk '{print $2}' | awk -F'-' '{print $3}')

if [ -n "$TUN_COMMIT" ]; then
    echo "💡 发现新版依赖的 sing-tun 提交为: $TUN_COMMIT"
    # 这里我们只提示用户，不自动覆盖用户可能改过的 sing-tun，因为你加了自定义补丁
    echo "⚠️ 提示: 你可能需要更新 ./sing-tun 目录以匹配新版本 $TUN_COMMIT"
    echo "更新 sing-tun 的方法:"
    echo "  1. 删掉旧的 sing-tun: rm -rf sing-tun"
    echo "  2. 拉取新的: git clone https://github.com/SagerNet/sing-tun.git sing-tun && cd sing-tun && git checkout $TUN_COMMIT && rm -rf .git"
    echo "  3. 重新打上你在 fw4 上的自定补丁"
else
    echo "ℹ️ 未能从 go.mod 识别出确切的 sing-tun commit，可能格式有变。"
fi

# 6. 在 go.mod 末尾追加 replace 指令
echo "🔧 在 go.mod 中注入 replace 指令..."
# 先确保有换行符
echo "" >> "$WORKDIR/go.mod"
echo "replace github.com/sagernet/sing-tun => ./sing-tun" >> "$WORKDIR/go.mod"

echo "✅ 更新完成！"
echo "👉 请执行 'git status' 检查变动，然后使用 'git commit' 提交。"

# 清理临时目录
rm -rf "$TMPDIR"
