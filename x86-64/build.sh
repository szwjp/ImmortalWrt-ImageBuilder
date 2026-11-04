#!/bin/bash
set -euo pipefail

# 目标版本: ImmortalWrt 25.12.x (APK)
# 23.05.x / 24.10.x (ipk) 链路已清除, 官方 docker 镜像也不再提供对应标签
PKG_FORMAT="apk"
STORE_REPO="https://github.com/wukongdaily/apk.git"

CUSTOM_PACKAGES=""
source "shell/custom-packages.sh"

echo "第三方软件包: $CUSTOM_PACKAGES"
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

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  echo "🔄 正在同步第三方软件仓库 Cloning repo..."
  git clone --depth=1 "$STORE_REPO" /tmp/store-repo

  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-repo/run/x86/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run || true

  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
PACKAGES="$CUSTOM_PACKAGES"

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz"
    wget -qO- "$META_URL" | tar xOvz > files/etc/openclash/core/clash_meta
    [ -s files/etc/openclash/core/clash_meta ] || { echo "Error: clash_meta download failed or empty"; exit 1; }
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    for f in files/etc/openclash/GeoIP.dat files/etc/openclash/GeoSite.dat; do
        [ -s "$f" ] && ! head -c 15 "$f" | grep -qi "<html" || { echo "Error: $f download failed or looks like HTML"; exit 1; }
    done
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*${PKG_FORMAT}" \
      | head -n1 \
      | cut -d '"' -f 4)
    [ -n "$URL" ] || { echo "Error: no ${PKG_FORMAT} asset found in OpenClash latest release"; exit 1; }
    echo "OpenClash latest ${PKG_FORMAT}: $URL"
    wget -q "$URL" -P /home/build/immortalwrt/packages/
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ 已选择 luci-app-ssr-plus，添加 mihomo core"
    mkdir -p files/usr/bin
    MIHOMO_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
      | grep '"tag_name"' \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "mihomo latest version: $MIHOMO_VERSION"
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-amd64-compatible-${MIHOMO_VERSION}.gz"
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    [ -s files/usr/bin/mihomo ] || { echo "Error: mihomo download failed or empty"; exit 1; }
    chmod +x files/usr/bin/mihomo
    echo "✅ 已下载 mihomo core"
    ls -lah files/usr/bin
else
    echo "⚪️ 未选择 luci-app-ssr-plus"
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
