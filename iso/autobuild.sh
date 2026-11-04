#!/bin/bash
# 把固件 img.gz 打包成可引导的安装器 ISO
#
# 原本这段逻辑在第三方仓库 wukongdaily/img-installer 里, CI 每次现 clone 一次
# 再执行, 上游一改代码产物就跟着变, 且等于执行了不受本仓库控制的代码。
# 现在整条链路搬进本仓库, 不再有任何 clone。
#
# 用法: bash iso/autobuild.sh <固件文件路径>
set -euo pipefail

RECEIVE_FILE="${1:-}"
if [ -z "$RECEIVE_FILE" ]; then
    echo "用法: $0 <固件文件路径>" >&2
    exit 1
fi
if [ ! -f "$RECEIVE_FILE" ]; then
    echo "错误: 找不到固件文件 $RECEIVE_FILE" >&2
    exit 1
fi

# 必须在 cd 之前转成绝对路径: 下面会切到 ISO_DIR, 而调用方给的固件路径
# 往往是相对当前工作目录的(CI 里是工作区根目录)。先转绝对路径, 否则
# 切目录后就找不到文件了。
RECEIVE_FILE=$(CDPATH= cd -- "$(dirname -- "$RECEIVE_FILE")" && pwd)/$(basename -- "$RECEIVE_FILE")

ISO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ISO_DIR"

# debian:buster 是构建 ISO 的宿主环境(要在里面跑 debootstrap + xorriso)。
# 用 digest 而不是 tag 钉死: tag 指向的内容会随上游重新推送而变化,
# digest 固定不变, 保证每次构建的宿主环境完全一致。
DEBIAN_IMAGE="debian:buster@sha256:58ce6f1271ae1c8a2006ff7d3e54e9874d839f573d8009c20154ad0f2fb0a225"

echo "==> 准备固件"
mkdir -p imm output
filename=$(basename -- "$RECEIVE_FILE")
echo "固件: $filename"

# 解压成 imm/custom.img。固件由 build.sh 产出, 固定是 .img.gz。
case "$filename" in
    *.gz)
        echo "解压 gzip"
        gunzip -f -c "$RECEIVE_FILE" > imm/custom.img
        ;;
    *.zip)
        echo "解压 zip"
        unzip -p "$RECEIVE_FILE" '*.img' > imm/custom.img
        ;;
    *.xz)
        echo "解压 xz"
        xz -d -c "$RECEIVE_FILE" > imm/custom.img
        ;;
    *.img)
        cp -f "$RECEIVE_FILE" imm/custom.img
        ;;
    *)
        echo "错误: 不支持的固件格式: $filename" >&2
        exit 1
        ;;
esac

if [ ! -s imm/custom.img ]; then
    echo "错误: 解压后得到空文件 imm/custom.img" >&2
    exit 1
fi
echo "固件大小: $(ls -lh imm/custom.img | awk '{print $5}')"

echo "==> 合成安装器 ISO"
# --privileged 是必需的: build.sh 要在容器里 mount /proc /dev /sys 并 chroot。
# 固件以只读挂载进去, 容器里只读不改它。
docker run --privileged --rm \
    -v "$ISO_DIR/output:/output" \
    -v "$ISO_DIR/supportFiles:/supportFiles:ro" \
    -v "$ISO_DIR/imm/custom.img:/mnt/custom.img:ro" \
    "$DEBIAN_IMAGE" \
    /supportFiles/custom/build.sh

if [ ! -f output/custom-installer-x86_64.iso ]; then
    echo "错误: 未生成 ISO 产物" >&2
    exit 1
fi

echo "==> 完成: output/custom-installer-x86_64.iso"
ls -lh output/custom-installer-x86_64.iso
