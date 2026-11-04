#!/bin/bash
set -euo pipefail

# 目标版本: ImmortalWrt 25.12.x (APK)
# 23.05.x / 24.10.x (ipk) 链路已清除, 官方 docker 镜像也不再提供对应标签
# 非官方 LuCI 插件已全部清除, 构建只用官方源里的包。

CUSTOM_PACKAGES=""
source "shell/custom-packages.sh"

echo "核心软件包: $CUSTOM_PACKAGES"
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "pppoe-settings written (enable_pppoe=${ENABLE_PPPOE}, account=${PPPOE_ACCOUNT:+已设置})"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ---- 官方 LuCI 应用: 按本次构建版本动态解析 ----
# custom-packages.sh 里写的是应用名(LUCI_APPS), 这里按 LUCI_VERSION 去官方源的
# index.json 查真实包名; 该版本没有这个应用就直接失败并列出可选项。
LUCI_APP_NAMES="$LUCI_APPS"
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    LUCI_APP_NAMES="$LUCI_APP_NAMES dockerman"
fi
LUCI_PKGS=""
if [ -n "$LUCI_APP_NAMES" ]; then
    if [ -z "${LUCI_VERSION:-}" ]; then
        echo "❌ 解析 LuCI 应用需要 LUCI_VERSION (由 workflow 传入)" >&2
        exit 1
    fi
    echo "🔄 按版本 $LUCI_VERSION 解析 LuCI 应用: $LUCI_APP_NAMES"
    LUCI_PKGS=$(sh shell/luci-apps.sh "$LUCI_VERSION" $LUCI_APP_NAMES) || exit 1
    echo "✅ LuCI 应用解析结果: $LUCI_PKGS"
fi

PACKAGES="$CUSTOM_PACKAGES $LUCI_PKGS $EXCLUDE_PACKAGES"

# PACKAGES 会被塞进 ImageBuilder 的 USER_PACKAGES="..." (Makefile:361), 是双引号
# 里的 shell 字符串: 只要里面有一个换行, make 的 shell 命令就被截断, 构建会报
# "unexpected EOF while looking for matching" 而失败。这里显式拦一道, 不让它
# 静默变成一个不存在的包名。
if [[ "$PACKAGES" == *$'\n'* ]]; then
  echo "❌ 包列表里出现了换行, 会破坏 make 命令行, 已中止构建" >&2
  exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 修正软件源地址与构建版本一致 (cat 回写避免破坏 bind-mount 的 inode)
if [ -n "${LUCI_VERSION:-}" ] && [ -f .config ]; then
  tmp=$(mktemp)
  sed "s|^CONFIG_VERSION_REPO=\".*\"|CONFIG_VERSION_REPO=\"https://downloads.immortalwrt.org/releases/${LUCI_VERSION}\"|" .config > "$tmp"
  cat "$tmp" > .config
  rm -f "$tmp"
  echo "CONFIG_VERSION_REPO -> https://downloads.immortalwrt.org/releases/${LUCI_VERSION}"
fi

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE="$PROFILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
