#!/bin/bash
# This shell script is executed inside the chroot
#
# 必须 fail-fast: 本脚本跑在 chroot 里, 父进程(容器入口)的 set -e 管不到这里。
# 任何一步 apt 失败若被放过, 最终会产出一个"构建成功"但缺包的 ISO —— 失败要到
# 用户装机时才暴露。upstream 版本没有 set -e, 这里补上。
set -euo pipefail

# 归档源(EOL)偶尔超时/断流, 失败自动重试, 别让一次网络抖动毁掉整次 ISO 构建。
cat > /etc/apt/apt.conf.d/99-network-retries <<EOF
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

echo Set hostname
echo "installer" > /etc/hostname

# Set as non-interactive so apt does not prompt for user input
export DEBIAN_FRONTEND=noninteractive

echo Install security updates and apt-utils
apt-get update
# 安装/升级 apt 本身失败不致命(基础镜像里 apt 已经可用), 其余步骤会兜住问题;
# 但不要让这一条把整次构建拦下来。
apt-get -y install apt || echo "warning: 'apt-get install apt' 失败, 继续" >&2
apt-get -y upgrade

echo Set locale
apt-get -y install locales
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
update-locale LANG=en_US.UTF-8

echo Install packages
# 只装安装流程真正用到的: 内核、live-boot、systemd、网卡固件, 以及 iproute2
# (发布说明让用户用 `ip a` 查地址)。dd/lsblk 等由 Debian 基础系统提供。
# 刻意不装 sshd: 安装器只需本地控制台, 同网段 root 登录就能 dd 磁盘。
apt-get install -y --no-install-recommends linux-image-amd64 live-boot systemd-sysv firmware-linux-free iproute2

echo Clean apt post-install
apt-get clean

echo Enable systemd-networkd as network manager
systemctl enable systemd-networkd

echo Set resolv.conf to use systemd-resolved
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo Remove machine-id
rm -f /etc/machine-id
