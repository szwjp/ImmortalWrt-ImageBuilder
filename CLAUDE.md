
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述
这是 ImmortalWrt-ImageBuilder，一个基于 CI 的项目，用于自动化构建 ImmortalWrt 固件镜像，仅支持 x86-64 设备。

## 重要目录和文件
- **.github/workflows/**: GitHub Actions 工作流文件，仅保留 x86-64 和 ISO 相关的工作流
- **shell/**: 构建脚本目录
- **files/etc/uci-defaults/99-custom.sh**: 固件首次启动时运行的脚本，用于配置网络、防火墙、Docker 等
- **x86-64/**: x86-64 平台的构建脚本和配置
- **README.md**: 项目文档，包含使用说明
- **SUPPORT.md**: 支持的设备列表（仅 x86-64）

## 构建流程
1. 通过 GitHub Actions 的 workflow_dispatch 事件触发构建
2. 使用 ImmortalWrt ImageBuilder 的 Docker 容器运行 `make image`
3. 从 `files/` 目录包含自定义文件
4. 在 shell 脚本中定义自定义软件包
5. 输出文件上传到 GitHub releases

## 关键配置点
- **自定义软件包**: 编辑 `shell/custom-packages.sh` 或 `shell/apk-custom-packages.sh` 来选择软件包
- **首次启动配置**: 编辑 `files/etc/uci-defaults/99-custom.sh` 来修改固件首次启动时的行为
- **构建参数**: 每个工作流都有固件大小、是否包含 Docker、路由器 IP、PPPoE 设置等输入参数

## README 中的重要说明
- 单网口设备默认采用 DHCP 模式（无静态 IP）
- 多网口设备默认 eth0 为 WAN（DHCP），其他为 LAN，静态 IP 为 192.168.100.1
- WAN 防火墙入站默认 ACCEPT，方便首次访问；配置完成后建议设置为 REJECT
- ISO 镜像可通过 Ventoy（Windows）或 balenaEtcher（macOS）进行物理机安装

