# ImmortalWrt-ImageBuilder

基于 CI 的 ImageBuilder 工作流，用于自动化构建 ImmortalWrt 固件（仅支持 x86-64）。

## 功能特性

- 支持自定义固件大小（默认 1GB，支持逗号分隔多档）
- 支持可选预安装 Docker
- 官方 LuCI 应用随构建版本动态解析
- 支持 25.12.x 版本
- 提供 ISO 安装器格式

> 23.05.x / 24.10.x (ipk) 链路已清除：官方 docker 镜像不再提供这两个版本的 x86-64 标签。
>
> **非官方 LuCI 插件已全部清除**（第三方 apk 源、代理内核下载、第三方插件的固件内配置一并移除），以后统一安排。当前固件只含官方源里的包。

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
│   └── tests/luci-apps-test.sh  # luci-apps.sh 规则自测 (不联网)
└── files/etc/uci-defaults/      # 固件自定义文件目录
    └── 99-custom.sh             # 固件首次启动配置脚本
```

## 操作手册

### 基本用法

1. Fork 本项目
2. 在 fork 后的项目中点击 【Actions】
3. 找到需要的工作流后点击 【Run workflow】

### 固件默认属性

- **单网口设备**：默认采用 DHCP 模式，自动获取 IP
- **多网口设备**：默认 WAN 口采用 DHCP 模式，LAN 口 IP 为 192.168.1.1（最后一个网口为 WAN，其余为 LAN）
- 若在工作流中勾选了拨号信息，则 WAN 口模式为 PPPoE 拨号模式
- 建议拨号用户使用之前重启一次光猫

### 包集合怎么组织

- **`shell/custom-packages.sh`** 只放封装层的**核心组件**（系统基础件、网络核心、驱动、存储、引导、中文界面底线），与 `szwjp/imageBuilder` 口径一致。
- **官方 LuCI 应用**不再写死包名，统一写在 `custom-packages.sh` 末尾的 `LUCI_APPS`（写的是**应用名**，不是包名）。构建时由 `shell/luci-apps.sh` 按本次构建版本（`LUCI_VERSION`）去官方源索引 `index.json` 查真实包名：

  | 应用名 | 解析规则 |
  | --- | --- |
  | 有中文翻译 | `luci-i18n-<名>-zh-cn`（i18n 包会带上对应 app 的依赖闭包） |
  | 无中文翻译 | `luci-app-<名>` |
  | mod 型包 | `luci-mod-<名>` |
  | 都不存在 | **构建失败**，并列出该版本可用的应用名 |

  应用名写 `*` 表示该版本全部 LuCI 应用。

- **非官方 LuCI 插件**不在官方源里，无法按版本动态解析，因此当前**全部清除**，以后统一安排。需要时再按统一方案接回（届时会带上自己的包源、版本解析与固件内配置）。

### 特别说明

- 本项目构建的固件，WAN 口防火墙规则入站默认是开启的，待首次调试完毕后，建议自行关闭。操作方法：网络 - 防火墙 - WAN 的入站选择拒绝，然后保存并应用即可。
- 固件默认 root 无密码，且 SSH、ttyd（网页终端）默认监听所有网口（含 WAN）。公网或不可信网络环境下请务必：设置 root 密码、在【系统 - 登录/SSH】中限制监听接口，或关闭 ttyd。
