#!/bin/sh
# 收集第三方 apk 到 packages/ 目录 (供 ImageBuilder 的 make image 使用)
#
# 包源: https://github.com/wukongdaily/apk.git 的 run/x86 目录
#   - *.run 是自解压包, 用 --target/--noexec 解出其中的 .apk
#   - 一级子目录下的 .apk 直接收集
#
# 用法: sh shell/prepare-packages.sh

PKG_EXT="apk"

BASE_DIR="extra-packages"
TEMP_DIR="$BASE_DIR/temp-unpack"
TARGET_DIR="packages"

# 清理旧的目录
rm -rf "$TEMP_DIR" "$TARGET_DIR"
mkdir -p "$TEMP_DIR" "$TARGET_DIR"

# 解压 .run 文件
for run_file in "$BASE_DIR"/*.run; do
    [ -e "$run_file" ] || continue
    echo "🧩 解压 $run_file -> $TEMP_DIR"
    sh "$run_file" --target "$TEMP_DIR" --noexec
done

# 1. 收集 run 解压出的 .${PKG_EXT} 文件
find "$TEMP_DIR" -type f -name "*.${PKG_EXT}" -exec cp -v {} "$TARGET_DIR"/ \;

# 2. 收集 extra-packages/*/ 下的 .${PKG_EXT} 文件（只查一级子目录）

find "$BASE_DIR" -mindepth 2 -maxdepth 2 -type f -name "*.${PKG_EXT}" ! -path "$TEMP_DIR/*" \
  -exec echo "👉 Found:" {} \; \
  -exec cp -v {} "$TARGET_DIR"/ \;

echo "✅ 所有 .${PKG_EXT} 文件已整理至 $TARGET_DIR/"
