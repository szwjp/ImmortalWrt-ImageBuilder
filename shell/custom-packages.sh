#!/bin/bash
# 自定义软件包配置 (ImmortalWrt 25.12.x, APK)
#
# 这里只放"封装层最基础的核心组件": 固件必须有的系统基础件。
# 官方 LuCI 应用不在这里写死包名 —— 统一写在文件末尾的 LUCI_APPS 里,
# 构建时由 shell/luci-apps.sh 按本次构建版本解析成真实包名。
#
# 口径与 szwjp/imageBuilder 的核心清单一致:
#   - 剔除 nginx-full / nginx-mod-luci (Web 主入口属可选档, 不进核心)
#   - 剔除 autocore / kmod-tcp-bbr (调优偏好, 归自维护调优插件)
#   - 剔除各应用的 luci-i18n-* (改由 LUCI_APPS 动态解析)
#   - 显式补入 ttyd (原本是被 luci-i18n-ttyd-zh-cn 顺带带入的, 删静态表后必须显式列出)

#==== 系统基础（base 系统组件） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES base-files"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES libc"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES libgcc"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES uci"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES procd-ujail"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES logd"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES urandom-seed"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES urngd"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES uclient-fetch"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES ca-bundle"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES libustream-openssl"
#==== 包管理器（APK） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES apk-openssl"
#==== Web 管理界面 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-base-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-firewall-zh-cn"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-package-manager-zh-cn"
#==== 网络核心与防火墙 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES netifd"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES firewall4"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES nftables"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-nft-offload"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-nf-nathelper"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES dnsmasq-full"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES odhcp6c"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES odhcpd-ipv6only"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES ppp"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES ppp-mod-pppoe"
#==== 远程管理（SSH + 网页终端） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES dropbear"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES ttyd"
#==== 存储与文件系统 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES block-mount"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES automount"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES fstools"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES fdisk"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES partx-utils"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-fs-f2fs"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES mkf2fs"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-fs-vfat"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES mtd"
#==== 引导加载 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES grub2-bios-setup"
#==== 中国区默认设置 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES default-settings-chn"
#==== 有线网卡驱动（Intel） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-e1000"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-e1000e"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-igb"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-igbvf"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-igc"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-i40e"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-ixgbe"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-ixgbevf"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-dwmac-intel"
#==== 有线网卡驱动（Realtek） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-8139cp"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-8139too"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-r8101"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-r8125"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-r8126"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-r8168"
#==== 有线网卡驱动（其他厂商/虚拟化） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-pcnet32"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-tulip"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-vmxnet3"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-amazon-ena"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-amd-xgbe"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-bnx2"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-forcedeth"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-tg3"
#==== USB 设备驱动 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-usb-hid"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-usb-net"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-usb-net-asix"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-usb-net-asix-ax88179"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-usb-net-rtl8150"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-usb-net-rtl8152-vendor"
#==== GPU 驱动与固件（Intel） ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-drm-i915"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES i915-firmware-dmc"
#==== 其他 ====
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-button-hotplug"
CUSTOM_PACKAGES="$CUSTOM_PACKAGES openssh-sftp-server"

# ============= 第三方插件 apk (来源: wukongdaily/apk 的 run/x86) =============
# 第三方包不在官方 luci 源里, 无法按版本动态解析, 因此仍显式列出(含配套中文包)。
# 新增非常好用的文件管理器 by github sbwml
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES bash quickfile luci-app-quickfile luci-i18n-quickfile-zh-cn"
# 极光主题和配置 by github eamonxg
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn"
# 分区扩容 by sirpdboy
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"
# 流量监控 by timsaya
CUSTOM_PACKAGES="$CUSTOM_PACKAGES bandix luci-app-bandix luci-i18n-bandix-zh-cn"
# 新增ssr apk
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES xray-core naiveproxy luci-app-ssr-plus luci-i18n-ssr-plus-zh-cn"
# 新增passwall2 apk
CUSTOM_PACKAGES="$CUSTOM_PACKAGES xray-core sing-box hysteria kmod-nft-socket kmod-nft-tproxy luci-app-passwall2 luci-i18n-passwall2-zh-cn"
# 仓库内代理相关apk
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nikki-zh-cn"
#CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-openclash"

# ============= 官方 LuCI 应用: 随构建版本动态解析 =============
# 这里写的是"应用名", 不是包名。构建时由 shell/luci-apps.sh 按本次构建版本
# (LUCI_VERSION) 去官方源的 index.json 里查真实包名:
#   有 zh-cn 翻译 -> luci-i18n-<名>-zh-cn
#   没有翻译     -> luci-app-<名>, 或 mod 型包 luci-mod-<名>
# 应用名在该版本里不存在时, 构建直接失败并列出该版本可用的应用名, 不会静默出图。
# "*" 表示该版本全部 LuCI 应用。
# 底线界面(基础界面/防火墙/软件包页)的中文包已在核心集合里, 不在此列。
LUCI_APPS="acme adblock autoreboot banip ddns-go ddns diskman homeproxy ipsec-vpnd netdata passwall samba4 sqm ttyd uhttpd upnp wol"
