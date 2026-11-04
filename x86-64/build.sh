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

# 凭据文件用 UCI 格式写, 值用双引号包裹并转义反斜杠与双引号。
#
# 为什么不用 shell 的 key=value 写法: 设备端 99-custom.sh 若用 . (source) 读这个
# 文件, 密码里的 $ ' " ; 等字符会被 shell 当成语法解释 —— $$ 展开成 PID、
# $VAR 展开成环境变量、单引号导致整个文件语法错误、分号导致命令注入。
# UCI 的双引号值只对反斜杠和双引号做转义, 其余字符(含 $ ' ; )都是字面量,
# 设备端用 uci get 取值, 完全不经过 shell 求值。
#
# 注意: UCI 单引号值内部无法表示单引号本身(parse_single_quote 无转义分支),
# 所以这里必须用双引号。
uci_escape_dq() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

{
  printf "config settings 'pppoe'\n"
  printf '\toption enabled "%s"\n' "$(uci_escape_dq "$ENABLE_PPPOE")"
  printf '\toption account "%s"\n' "$(uci_escape_dq "$PPPOE_ACCOUNT")"
  printf '\toption password "%s"\n' "$(uci_escape_dq "$PPPOE_PASSWORD")"
} > /home/build/immortalwrt/files/etc/config/pppoe-settings

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
