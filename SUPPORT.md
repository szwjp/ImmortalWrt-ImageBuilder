# 支持的设备

## x86-64 工作流

| 🖥️ 工作流分类            | 处理器            | 备注         | luci版本        |
| ---------------- | -------------- | ---------- |---------- |
| x86-64 efi.img.gz  | Intel/AMD | EFI向下兼容传统BIOS |25.12.x |
| x86-64 OpenWrt安装器   | Intel/AMD | ISO格式适用于任何虚拟机和任何物理机 引导后输入ddd来安装 |25.12.x |

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
│   ├── luci-apps.sh             # 按构建版本解析官方 LuCI 应用名 -> 真实包名
│   ├── refresh-release-date.sh  # 刷新 release 的 published_at, 让列表页日期跟随构建
│   └── tests/                   # 构建脚本自测 (全部不联网, CI 里跑)
│       ├── luci-apps-test.sh            # luci-apps.sh 解析规则自测
│       ├── custom-packages-test.sh      # 核心集/排除项/LUCI_APPS 静态断言
│       └── refresh-release-date-test.sh # refresh-release-date.sh 行为自测
└── files/etc/uci-defaults/      # 固件自定义文件目录
    └── 99-custom.sh             # 固件首次启动配置脚本
```
