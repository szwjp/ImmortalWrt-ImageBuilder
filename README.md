
# [新手指导](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) 👈🏻
# ImmortalWrt-ImageBuilder

[![GitHub](https://img.shields.io/github/license/wukongdaily/AutoBuildImmortalWrt.svg?label=LICENSE&amp;logo=github&amp;logoColor=%20)](https://github.com/wukongdaily/AutoBuildImmortalWrt/blob/master/LICENSE)
![GitHub Stars](https://img.shields.io/github/stars/wukongdaily/AutoBuildImmortalWrt.svg?style=flat&amp;logo=appveyor&amp;label=Stars&amp;logo=github)
![GitHub Forks](https://img.shields.io/github/forks/wukongdaily/AutoBuildImmortalWrt.svg?style=flat&amp;logo=appveyor&amp;label=Forks&amp;logo=github) [![Github](https://img.shields.io/badge/RELEASE-ImmortalWrtImageBuilder-123456?logo=github&amp;logoColor=fff&amp;labelColor=green&amp;style=flat)](https://github.com/wukongdaily/AutoBuildImmortalWrt/releases) [![Bilibili](https://img.shields.io/badge/Bilibili-123456?logo=bilibili&amp;logoColor=fff&amp;labelColor=fb7299)](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) &lt;br&gt;

## 🤔 这是什么？
基于 CI 的 ImageBuilder 工作流，用于自动化构建 ImmortalWrt 固件。
&gt; 1、支持自定义固件大小 默认1GB 不建议设置过大 推荐1G-2G 更大需求可通过自定义插件里的扩容插件自行扩容&lt;br&gt;
&gt; 2、支持可选预安装docker（可选）支持在UI上勾选是否集成商店 （24.10.6以下）&lt;br&gt;
&gt; 3、支持按需增加[第三方软件](https://github.com/wukongdaily/store/blob/master/README.md)  如何集成 https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209 &lt;br&gt;
&gt; 4、在UI上 新增luci版本的可选项，默认最新版25.12.x https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/426&lt;br&gt;
&gt; 5、支持设置管理地址的ip 比如192.168.100.1 这里强调 这项功能仅针对多网口机型 单网口的逻辑还是自动获取ip模式（dhcp）无固定ip&lt;br&gt;
&gt; 6、对于[插件追新的用户 建议前往run项目 下载run后 ](https://github.com/wukongdaily/RunFilesBuilder/discussions/41)用命令 sh xx.run 覆盖安装 &lt;br&gt;
&gt; 7、支持24.10.x 、25.12.x 等版本 （包括x86-64-ISO、x86-64）

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
│   ├── build23.sh               # 23.05.4 版本构建脚本
│   ├── build24.sh               # 24.10.x 版本构建脚本
│   ├── build25.sh               # 25.12.x 版本构建脚本
│   ├── imm.config               # 23.05.4/24.10.x 版本配置
│   └── imm25.config             # 25.12.x 版本配置
├── shell/                       # 构建脚本和包管理目录
│   ├── custom-packages.sh       # 自定义软件包配置 (opkg)
│   ├── prepare-packages.sh      # 软件包准备脚本 (opkg)
│   ├── apk-custom-packages.sh   # 自定义软件包配置 (apk)
│   ├── apk-prepare-packages.sh  # 软件包准备脚本 (apk)
│   └── switch_repository.sh     # 仓库切换脚本
└── files/etc/uci-defaults/      # 固件自定义文件目录
    └── 99-custom.sh             # 固件首次启动配置脚本
```

## [基本用法步骤](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) 👈🏻
1、fork本项目&lt;br&gt;
2、在fork后的项目中 点击【action】 找到需要的工作流后 run-workflow&lt;br&gt;

## 虚拟机建议用哪条工作流？下图↓
&lt;img width="30%" height="30%" alt="image" src="https://github.com/user-attachments/assets/743027e0-584a-4842-bfb3-0dff22de9101"&gt; &lt;br&gt;
虚拟机用户建议直接构建ISO镜像 此过程分2个阶段 阶段一构建固件imm 阶段二将其封装iso格式的安装器 总计耗时大约7-8分钟 &lt;br&gt;
ISO在虚拟机引导后 跑码后，在命令行输入 `ddd` 按提示 完成虚拟磁盘的写入（安装immortalwrt到虚拟磁盘）&lt;br&gt;
这样做也比较灵活 避免了格式转换和解压 同时还可以指定安装某个硬盘 而安装后的磁盘剩余空间也能加以利用&lt;br&gt;
详细的解说 可以参考我的另一个项目 [img-installer](https://github.com/wukongdaily/armbian-installer)

## 虚拟机用户使用的教学⬇️ ISO
[![操作步骤](https://img.shields.io/badge/YouTube-123456?logo=youtube&amp;labelColor=ff0000)](https://www.youtube.com/watch?v=ftSE3wSJi64) [![Bilibili](https://img.shields.io/badge/Bilibili-123456?logo=bilibili&amp;logoColor=fff&amp;labelColor=fb7299)](https://www.bilibili.com/video/BV1enxMzwEUu/) &lt;br&gt;
【绿联NAS安装immortalwrt25.12】https://www.bilibili.com/video/BV1AyZcBsErt/

## 物理机如何使用ISO格式的安装器(本项目独有)
- Windows 建议将ISO拷贝到制作好的[Ventoy](https://www.ventoy.net/cn/index.html)&lt;br&gt;
  &lt;img width="303" height="90" alt="image" src="https://github.com/user-attachments/assets/34d03f24-3100-4c0d-a904-5f114d867793"&gt;

- macOS 使用[balenaEtcher](https://etcher.balena.io/) 将ISO 刻录到U盘即可&lt;br&gt;
  &lt;img width="285" height="188" alt="image" src="https://github.com/user-attachments/assets/cd09be8d-2670-404c-8878-c2782b3c8374"&gt;

- 将制作好的U盘提前插在软路由 然后启动后 按Del 或者F12、F11、F7等 使U盘成为第一启动盘

  &lt;img width="50%" alt="image" src="https://github.com/user-attachments/assets/a1ba38d9-3056-41dd-8441-9e61c3dcae1d"&gt; &lt;br&gt;
- 启动后在命令行输入 ddd 按提示 完成硬盘的写入 硬盘剩余空间你还可以自动分配&lt;br&gt;
- ISO安装器原理 点这里查看 https://github.com/wukongdaily/img-installer
- 这是一个值得推广的方法 真心希望你能吸收、学会 费了很大心思的 没错、从今往后 [任何OpenWrt都有安装器了](https://github.com/wukongdaily/img-installer)

## 如何查询imm仓库内有哪些插件
https://mirrors.sjtug.sjtu.edu.cn/immortalwrt/releases/24.10.4/packages/x86_64/luci/
## 如何查询imm仓库外目前可以集成哪些插件
https://github.com/wukongdaily/store
&gt; 具体方法 https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209
## 【视频教程】如何集成第三方插件？
https://www.youtube.com/watch?v=KN6AJYV1hBI &lt;br&gt;
https://www.youtube.com/watch?v=7i6BQeitUtI

## 旁路由的用户必读
近期不少用户修改配置文件中的默认ip地址，误以为这个工作流可以直接设置旁路ip。这是巨大的误解，这样设置就乱套了。&lt;br&gt;
旁路的逻辑应该是单网口模式。根据下面的固件属性可知。单网口默认采取`dhcp模式`，用户应当自行在上一级路由器查看给imm路由器分配的ip地址。
然后通过该ip来访问imm后台页面，在imm后台页面中，根据自己主路由的网段 自行配置旁路的ip地址。

## 正常路由模式必读
所谓正常的路由模式 就是指多网口用户，多网口的意思就是2个或者2个以上网口的情况。&lt;br&gt;
一般wan用于拨号或者自动获取ip &lt;br&gt;
而其他lan一般是给其他设备分配dhcp&lt;br&gt;
这种情况下 你可以修改路由器的默认ip  `192.168.100.1` 比如你可以修改为`192.168.80.1` 诸如此类。&lt;br&gt;
没错，修改此ip 无非就是为了避免跟光猫或者跟家庭中的其他路由器网段冲突。大多数用户，无需更改。

## 该固件默认属性？(必读)
- 该固件刷入【单网口设备】默认采用DHCP模式,自动获得ip。类似NAS的做法
- 该固件刷入【多网口设备】默认WAN口采用DHCP模式，LAN 口ip为  `192.168.100.1` &lt;br&gt;其中eth0为WAN 其余网口均为LAN
- 若用户在工作流中勾选了拨号信息 则WAN口模式为pppoe拨号模式。
- 建议拨号用户使用之前重启一次光猫。
- 综合上述特点，【单网口设备】应该先接路由器，先在上级路由器查看一下它的ip 再访问。
- 上述特点 你都可以通过 `99-custom.sh` 配置和调整

## 特别说明
本项目构建的固件 为了易用性 wan口防火墙规则入站 是开启的，待首次调试完毕后，建议自行关闭。操作方法如下
网络——防火墙—— wan 的入站 选择拒绝 然后保存并应用即可。更多讨论[ 请参考这个话题](https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/341)
&lt;img width="3860" height="870" alt="image" src="https://github.com/user-attachments/assets/d823bccd-f0df-4d4a-877d-b711b81fcf1a"&gt;
同时此项设置的相关代码详见 `files/etc/uci-defaults/99-custom.sh` 行首

## ❤️其它GitHub Action项目推荐🌟 （建议收藏）⬇️
- ### [一键生成run插件] 🆕
- https://github.com/wukongdaily/RunFilesBuilder&lt;br&gt;
- ### [一键生成docker离线镜像] 🆕
- https://github.com/wukongdaily/DockerTarBuilder&lt;br&gt;
- ### [OpenWrt/Armbian IMG安装器ISO] 🆕
- https://github.com/wukongdaily/img-installer


## ❤️如何构建docker版ImmortalWrt（建议收藏）⬇️
https://wkdaily.cpolar.cn/15
# 🌟鸣谢
### https://github.com/immortalwrt
### https://github.com/ophub/flippy-openwrt-actions
### https://github.com/ophub/amlogic-s9xxx-openwrt
### https://github.com/sirpdboy
### https://github.com/wukongdaily/ib-overlay
### 高级卸载插件出处 by VedioTalk https://xz.vumstar.com
### 新增极光主题 来自 https://github.com/eamonxg/luci-theme-aurora
### 新增Bandix流量监控 来自 https://github.com/timsaya/luci-app-bandix
### 新增rtp2httpd 来自https://github.com/stackia/rtp2httpd

## ❤️赞助作者 ⬇️⬇️

&lt;a href="https://wkdaily.cpolar.top/01" target="_blank"&gt;
  &lt;img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
       alt="Buy Me A Coffee"
       style="width:15%; height:auto;"&gt;
&lt;/a&gt;

