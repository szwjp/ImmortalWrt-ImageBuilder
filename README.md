# ImmortalWrt-ImageBuilder

基于 CI 的 ImageBuilder 工作流，用于自动化构建 ImmortalWrt 固件（仅支持 x86-64）。

## 功能特性

- 支持自定义固件大小（默认 1GB）
- 支持可选预安装 Docker
- 官方 LuCI 应用按需启用（包名直接写在配置里）
- 支持 25.12.x 版本
- 提供 ISO 安装器格式

> 23.05.x / 24.10.x (ipk) 链路已清除：官方 docker 镜像不再提供这两个版本的 x86-64 标签。
>
> **非官方 LuCI 插件已全部清除**（第三方 apk 源、代理内核下载、第三方插件的固件内配置一并移除），以后统一安排。当前固件只含官方源里的包。
>
> **ISO 安装器链路已改为仓库内自带**：原先每次构建都现 clone 第三方仓库 `wukongdaily/img-installer` 再执行，构建产物会随上游改动而变化。现已把所需代码 vendored 进 `iso/` 目录，CI 不再 clone 任何外部仓库。详见 [`iso/README.md`](iso/README.md)。

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
├── files/etc/uci-defaults/      # 固件自定义文件目录
│   └── 99-custom.sh             # 固件首次启动配置脚本
└── iso/                         # ISO 安装器构建 (vendored, 不再 clone 第三方仓库)
    ├── autobuild.sh             # 固件 img.gz -> 安装器 ISO
    ├── info.md                  # ISO 发布说明
    ├── supportFiles/            # Debian live 环境与引导配置
    └── README.md                # 上游出处与本地改动说明
```

## 操作手册

### 基本用法

1. Fork 本项目
2. 在 fork 后的项目中点击 【Actions】
3. 找到需要的工作流后点击 【Run workflow】

### 固件默认属性

- **单网口设备**：默认采用 DHCP 模式，自动获取 IP
- **多网口设备**：默认 WAN 口采用 DHCP 模式，LAN 口 IP 为 192.168.1.1（最后一个网口为 WAN，其余为 LAN）
- 若在工作流中勾选了拨号信息，则 WAN 口模式为 PPPoE 拨号模式（仅多网口设备生效）
- 建议拨号用户使用之前重启一次光猫

### 包集合怎么组织

- **`shell/custom-packages.sh`** 只放封装层的**核心组件**（系统基础件、网络核心、驱动、存储、引导、中文界面底线）。
- **要排除的包**写在同一文件的 `EXCLUDE_PACKAGES`，用 ImageBuilder 的 `-包名` 语法（表示这个包不装进固件）。当前排除了 `autocore`（自动调频）——x86 的 ImageBuilder 默认会带上它，与核心集口径不一致。
- **官方 LuCI 应用**写在 `custom-packages.sh` 末尾的「ImmortalWrt 官方 LuCI 应用」区段，直接写包名（`luci-i18n-<名>-zh-cn`），按需启用/注释：

  ```sh
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-homeproxy-zh-cn"
  #CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nextdns-zh-cn"
  ```

  包名写错时 apk 装包会直接失败，构建不会静默出图。`luci-i18n-<名>-zh-cn` 的依赖闭包会自动带上对应的 `luci-app-<名>` 本体。

- **Docker 插件**由工作流的 `include_docker` 输入项控制（`build.sh` 按需追加 `luci-i18n-dockerman-zh-cn`），不写在静态表里——否则该输入项就失效了。

- **非官方 LuCI 插件**不在官方源里，当前**全部清除**，以后统一安排。需要时再按统一方案接回（届时会带上自己的包源与固件内配置）。

### 特别说明

- 本项目构建的固件，WAN 口防火墙规则入站默认是开启的，待首次调试完毕后，建议自行关闭。操作方法：网络 - 防火墙 - WAN 的入站选择拒绝，然后保存并应用即可。
- 固件默认 root 无密码，且 SSH、ttyd（网页终端）默认监听所有网口（含 WAN）。公网或不可信网络环境下请务必：设置 root 密码、在【系统 - 登录/SSH】中限制监听接口，或关闭 ttyd。
- **启用 PPPoE 时，宽带密码会以明文写入固件镜像**（首启脚本读完即删设备上的副本，但镜像本身仍含明文）。这类固件请勿公开分发。
