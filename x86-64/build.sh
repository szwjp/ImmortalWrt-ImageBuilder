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

# 包清单 = 核心集 + 排除项。官方 LuCI 应用的包名已直接写在
# shell/custom-packages.sh 的「ImmortalWrt 官方 LuCI 应用」区段里, 不再按版本解析。
PACKAGES="$CUSTOM_PACKAGES $EXCLUDE_PACKAGES"

# Docker 插件按 workflow 的 include_docker 输入决定是否装。
# luci-i18n-dockerman-zh-cn 的依赖闭包会自动带出 luci-app-dockerman /
# dockerd / docker / docker-compose, 只列这一条即可。
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

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
