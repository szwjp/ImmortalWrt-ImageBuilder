# 支持的设备

## x86-64 工作流

| 🖥️ 工作流分类            | 处理器            | 引导方式         | luci版本 | 固件大小 |
| ---------------- | -------------- | ---------- |---------- | -------- |
| x86-64 efi.img.gz  | Intel/AMD | EFI，向下兼容传统BIOS |25.12.x | 默认 1GB，可在工作流里改 |
| x86-64 OpenWrt安装器   | Intel/AMD | ISO，适用任何虚拟机和物理机；引导后输入 ddd 安装 |25.12.x | 同上 |

## 📁 项目功能目录树

```
ImmortalWrt-ImageBuilder/
├── .github/workflows/          # GitHub Actions 工作流目录
│   ├── build-x86-64.yml            # 统一构建工作流 (通过参数选择版本和输出格式)
│   └── clean-workflow.yml          # 工作流清理
├── x86-64/                      # x86-64 平台配置目录
│   ├── build.sh                 # 统一构建脚本 (25.12.x, APK)
│   └── imm.config               # 25.12.x 版本配置
├── shell/                       # 构建脚本和包管理目录
│   ├── custom-packages.sh       # 核心软件包配置 + 官方 LuCI 应用清单 (25.12.x, APK)
│   ├── refresh-release-date.sh  # 刷新 release 的 published_at, 让列表页日期跟随构建
│   └── tests/                   # 构建脚本自测 (全部不联网, CI 里跑)
│       ├── run-all.sh                    # 统一入口, 依次跑下面全部测试
│       ├── custom-packages-test.sh       # 核心集/排除项/静态表 静态断言
│       ├── refresh-release-date-test.sh  # refresh-release-date.sh 行为自测
│       └── firmware-config-test.sh       # 首启脚本/构建脚本 行为断言
└── files/etc/uci-defaults/      # 固件自定义文件目录
│   └── 99-custom.sh             # 固件首次启动配置脚本
└── iso/                         # ISO 安装器构建 (vendored, 不再 clone 第三方仓库)
    ├── autobuild.sh             # 固件 img.gz -> 安装器 ISO
    ├── info.md                  # ISO 发布说明
    ├── supportFiles/            # Debian live 环境与引导配置
    └── README.md                # 上游出处与本地改动说明
```
