#!/bin/bash
# 基于 willhaley 的 "custom debian live environment" 方案改编
# (上游 img-installer, 见 iso/README.md 的出处说明)

set -euo pipefail

echo "🔧 修复 buster 的源..."

# debian:buster 基础镜像里没有 ca-certificates(只有 91 个核心包),
# 所以第一次 apt 必须走 HTTP 才能把证书装上。装完立刻切回 HTTPS,
# 后面的所有下载(debootstrap / chroot 内的 apt)都走加密通道。
# archive.debian.org 同时支持 http 和 https, 实测 https 返回 200。
cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian buster main contrib non-free
deb http://archive.debian.org/debian-security buster/updates main
EOF

echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

# 归档源(EOL)偶尔超时/断流: 失败自动重试, 别让一次网络抖动毁掉整次 ISO 构建。
cat > /etc/apt/apt.conf.d/99-network-retries <<EOF
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

apt-get update

echo "🚀 开始执行 build.sh ..."

echo "Install ca-certificates (先用 HTTP 装证书, 装完切 HTTPS)"
apt-get -y install ca-certificates

cat > /etc/apt/sources.list <<EOF
deb https://archive.debian.org/debian buster main contrib non-free
deb https://archive.debian.org/debian-security buster/updates main
EOF

echo Install required tools
apt-get update
# 只装真正用到的: debootstrap(装 chroot)、squashfs-tools(mksquashfs)、
# xorriso(合成 ISO)、isolinux(BIOS 引导 + isohdpfx.bin)、
# syslinux-common(isolinux.cfg 用到的 vesamenu 等 BIOS 模块, 它是 isolinux 的
# Recommends, 这里显式列出以免 apt 配置关掉 recommends 时缺文件)、
# grub-efi-amd64-bin(EFI 模块, grub-mkstandalone 由依赖的 grub-common 提供)、
# mtools(mmd/mcopy 写 FAT ESP)、dosfstools(mkfs.vfat)。
apt-get -y install debootstrap squashfs-tools xorriso isolinux syslinux-common \
    grub-efi-amd64-bin mtools dosfstools

echo Create directory where we will make the image
mkdir -p $HOME/LIVE_BOOT

echo Install Debian
# 这里用 http 而不是 https: debootstrap 的二阶段会在目标 chroot 里跑一次
# apt-get update, 而 chroot 此刻还没证书, 走 https 会因证书校验失败而中断。
# debian buster 已 EOL, archive.debian.org 的 Release 文件带 GPG 签名,
# debootstrap 默认会校验签名, 所以 http 通道下完整性仍然有保障。
# --include=ca-certificates 把证书装进 chroot, 之后 chroot 内的源才切 https。
debootstrap --arch=amd64 --variant=minbase \
    --include=ca-certificates \
    buster $HOME/LIVE_BOOT/chroot http://archive.debian.org/debian/

echo Copy supporting documents into the chroot
cp -v /supportFiles/installChroot.sh $HOME/LIVE_BOOT/chroot/installChroot.sh
cp -v /supportFiles/custom/ddd $HOME/LIVE_BOOT/chroot/usr/bin/ddd
chmod +x $HOME/LIVE_BOOT/chroot/usr/bin/ddd
cp -v /supportFiles/sources.list $HOME/LIVE_BOOT/chroot/etc/apt/sources.list

echo Mounting dev / proc / sys
mount -t proc none $HOME/LIVE_BOOT/chroot/proc
mount -o bind /dev $HOME/LIVE_BOOT/chroot/dev
mount -o bind /sys $HOME/LIVE_BOOT/chroot/sys

echo Run install script inside chroot
chroot $HOME/LIVE_BOOT/chroot /installChroot.sh

echo Cleanup chroot
rm -v $HOME/LIVE_BOOT/chroot/installChroot.sh

echo Copy in systemd-networkd config
cp -v /supportFiles/99-dhcp-en.network $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chown -v root:root $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chmod -v 644 $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network

echo Enable autologin
mkdir -p -v $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/
cp -v /supportFiles/override.conf $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/override.conf

echo Unmounting dev / proc / sys
umount $HOME/LIVE_BOOT/chroot/proc
umount $HOME/LIVE_BOOT/chroot/dev
umount $HOME/LIVE_BOOT/chroot/sys

echo Create directories that will contain files for our live environment files and scratch files.
mkdir -p $HOME/LIVE_BOOT/{staging/{EFI/boot,boot/grub/x86_64-efi,isolinux,live},tmp}

echo Compress the chroot environment into a Squash filesystem.
cp /mnt/custom.img ${HOME}/LIVE_BOOT/chroot/mnt/
ls ${HOME}/LIVE_BOOT/chroot/mnt/
mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/staging/live/filesystem.squashfs -e boot

echo Copy kernel and initrd
cp -v $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/staging/live/vmlinuz
cp -v $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/staging/live/initrd

echo Copy boot config files
cp -v /supportFiles/custom/isolinux.cfg $HOME/LIVE_BOOT/staging/isolinux/isolinux.cfg
cp -v /supportFiles/custom/grub.cfg $HOME/LIVE_BOOT/staging/boot/grub/grub.cfg
cp -v /supportFiles/grub-standalone.cfg $HOME/LIVE_BOOT/tmp/grub-standalone.cfg
touch $HOME/LIVE_BOOT/staging/DEBIAN_CUSTOM

echo Copy boot images
cp -v /usr/lib/ISOLINUX/isolinux.bin "${HOME}/LIVE_BOOT/staging/isolinux/"
cp -v /usr/lib/syslinux/modules/bios/* "${HOME}/LIVE_BOOT/staging/isolinux/"
cp -v -r /usr/lib/grub/x86_64-efi/* "${HOME}/LIVE_BOOT/staging/boot/grub/x86_64-efi/"

echo Make UEFI grub files
grub-mkstandalone --format=x86_64-efi --output=$HOME/LIVE_BOOT/tmp/bootx64.efi --locales=""  --fonts="" "boot/grub/grub.cfg=$HOME/LIVE_BOOT/tmp/grub-standalone.cfg"

cd $HOME/LIVE_BOOT/staging/EFI/boot
SIZE=$(( $(stat --format=%s "$HOME/LIVE_BOOT/tmp/bootx64.efi") + 65536 ))
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
/sbin/mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img $HOME/LIVE_BOOT/tmp/bootx64.efi ::efi/boot/

echo Build ISO
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "${HOME}/LIVE_BOOT/debian-custom.iso" \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot \
        isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e /EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 0xef ${HOME}/LIVE_BOOT/staging/EFI/boot/efiboot.img \
    "${HOME}/LIVE_BOOT/staging"

echo Copy output
cp -v $HOME/LIVE_BOOT/debian-custom.iso /output/custom-installer-x86_64.iso
chmod -v 666 /output/custom-installer-x86_64.iso
ls -lah /output
