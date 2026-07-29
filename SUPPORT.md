# 支持的设备

## x86-64 工作流

| 🖥️ 工作流分类            | 处理器            | 备注         | luci版本        |
| ---------------- | -------------- | ---------- |---------- |
| x86-64 efi.img.gz  | Intel/AMD | EFI向下兼容传统BIOS |23.05.4, 24.10.x, 25.12.x |
| x86-64 OpenWrt安装器   | Intel/AMD | ISO格式适用于任何虚拟机和任何物理机 引导后输入ddd来安装 |24.10.x, 25.12.x |

## 📁 项目功能目录树

```
ImmortalWrt-ImageBuilder/
├── .github/workflows/          # GitHub Actions 工作流目录
│   ├── build-x86-64-23.05.4.yml    # x86-64 23.05.4 版本构建
│   ├── build-x86-64-24.10.x.yml    # x86-64 24.10.x 版本构建
│   ├── build-x86-64-25.12.x.yml    # x86-64 25.12.x 版本构建
│   ├── build-iso.yml               # ISO 安装器构建 (24.10.x)
│   ├── build-iso-25.12.x.yml       # ISO 安装器构建 (25.12.x)
│   └── clean-workflow.yml          # 工作流清理
├── x86-64/                      # x86-64 平台配置目录
│   ├── build.sh                 # 统一构建脚本 (通过 IMM_VERSION 区分版本)
│   ├── imm.config               # 23.05.4/24.10.x 版本配置
│   └── imm25.config             # 25.12.x 版本配置
├── shell/                       # 构建脚本和包管理目录
│   ├── custom-packages-23.sh     # 自定义软件包配置 (23.05.4)
│   ├── custom-packages-24.sh     # 自定义软件包配置 (24.10.x)
│   ├── custom-packages-25.sh     # 自定义软件包配置 (25.12.x, APK)
│   ├── prepare-packages.sh      # 软件包准备脚本 (opkg)
│   ├── apk-prepare-packages.sh  # 软件包准备脚本 (apk)
│   └── switch_repository.sh     # 仓库切换脚本
└── files/etc/uci-defaults/      # 固件自定义文件目录
    └── 99-custom.sh             # 固件首次启动配置脚本
```
