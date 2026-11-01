---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 69862c49f4ec4e710eaf569fae513e34_cd3943a6d5f111f19101525400de85a5
    ReservedCode1: VRKOugveXKIrIqitbglWyiMVs0U4TVM5WYoUpS9ka7jrWFBnS9cG66ckanoKMKEXUHHiPijDO7JCGfzqozJ9jQaASM9qLFhNVcEgIcm66LzTm9IG+Aula1L3m150zuOXXd5EEiTbArK3La+hyw+a3kviWjAEQJ6QlpJKHzg6kB2rzT5YnUca3wVyM8Y=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 69862c49f4ec4e710eaf569fae513e34_cd3943a6d5f111f19101525400de85a5
    ReservedCode2: VRKOugveXKIrIqitbglWyiMVs0U4TVM5WYoUpS9ka7jrWFBnS9cG66ckanoKMKEXUHHiPijDO7JCGfzqozJ9jQaASM9qLFhNVcEgIcm66LzTm9IG+Aula1L3m150zuOXXd5EEiTbArK3La+hyw+a3kviWjAEQJ6QlpJKHzg6kB2rzT5YnUca3wVyM8Y=
---

﻿# 小米 R3G 刷机资料清单（listing）

> **GitHub 上传版说明**：本目录为脱敏副本，`configs\RBf60If6TGXb.yaml`（含机场订阅域名与节点 UUID）已移除，
> 文中 WiFi 密码、root/SSH 口令、节点 UUID、REALITY 公钥与服务器域名均已替换为 `YOUR_*` 占位符或 `example.com`。
> 下文"共 20 个文件"等统计与目录树描述的是原始整理版本（R3G-Flash），仅作历史记录参考。

---

## 当前发布版目录结构（以本节为准）

```
r3g刷机（github上传版）/
├── README.md            陌生人入口：路线决策树 + 快速开始 + 踩坑速查表
├── listing.md           本文件（历史整理记录，见下节）
├── .gitignore           固件入库策略：允许 engineering/firmware/*.bin，排除凭据/日志
├── .gitattributes       换行符与二进制标记
├── LICENSE              许可证：自有内容统一 MIT（固件归上游，不在此授权范围）
├── docs/                实测文档 10 个（教程/排障/标准设置/拓扑等）
├── images/              插图 1 个
├── logs/                日志占位（无实际日志入库）
└── engineering/         工程目录
    ├── configs/         配置模板 2 个（含凭据的订阅 yaml 已移除）
    │   ├── 工程文件_config.yaml     脱敏模板
    │   └── nftables规则.txt
    ├── firmware/        官方固件 7 个 bin + 校验清单
    │   ├── SOURCES.md               来源/URL/SHA256/版本命名差异
    │   └── SHA256SUMS               实际哈希汇总（sha256sum 格式）
    └── scripts/         脚本 4 个
        ├── 00-backup-nand.sh        刷机前 NAND 备份（OpenWrt 侧）
        ├── 01-fetch-firmware.ps1    按 SOURCES.md 下载并强校验（Windows 侧）
        ├── 02-split-sysupgrade.py   拆 kernel1 / rootfs0
        └── 03-breed-memboot.txt     Breed 内存启动命令序列
```

与历史版本的差异：原 `configs/`、`firmware/`、`scripts/` 已统一收进 `engineering/`；固件由 6 个调整为 7 个（新增 OpenWrt 24.10.4 sysupgrade、新增小米原厂回滚包 2.28.46，移除 Pineapple Cloner 商业固件）；补 README、SOURCES.md、SHA256SUMS 与 4 个脚本。

---

## 历史整理记录（R3G-Flash 阶段）

- 整理时间：2026-11-01
- 目标目录：`C:\Users\15363\Desktop\R3G-Flash`
- 原始文件：**全部保留在原位，本次仅做复制**
- 扫描范围：`C:\Users\15363`（排除系统目录与 AppData 缓存）、`D:\`（全盘文件名 + 文档类正文扫描）、`E:\`（本机不存在该盘）
- 检索方式：文件名正则（R3G / r3g / 小米路由器3G / MiWiFi / breed / OpenWrtInvasion / sysupgrade / ShellCrash / ShellClash / OpenWrt / MT7621 / mir3g / 小米AX）+ 文档/脚本正文关键词匹配
- 命中结果：C 盘文件名命中 45 个、文档正文命中 82 个（多数为无关项目的 "breed/openwrt" 字面误命中）；D 盘 54.6 万文件中文件名命中 8 个、正文命中 38 个，**均为游戏资源或软件内置文件，与本任务无关**
- 去重后实际归档：**20 个文件，约 32.0 MB**

## 目录结构

```
C:\Users\15363\Desktop\R3G-Flash\
├─ docs\        10 个 75.1 KB  —— 教程/指南/手册/排障记录/拓扑
├─ scripts\      0 个         —— 本机未发现独立刷机脚本（命令均内嵌于文档）
├─ configs\      3 个 36.9 KB —— Clash/ShellCrash 配置与 nftables 规则
├─ firmware\     6 个 31.6 MB —— Breed、OpenWrt 23.05.6、19.07.2、Pineapple Cloner
├─ images\       1 个 250.7 KB—— 路由器 APP 文件共享说明截图
├─ logs\         0 个         —— 未发现刷机日志文件
└─ listing.md    本清单
```

## docs（10）

| # | 文件 | 大小 | 内容概要 | 核心 |
|---|------|------|----------|------|
| 1 | R3G完整配置教程.md | 19.0 KB | 总纲式教程：硬件参数（MT7621 / mipsel 24kc / UBI 117MB）、刷机全流程（OpenWRTInvasion 开 SSH → U 盘盲刷 Breed → Breed 刷 19.07.2 + Pineapple Cloner）、IP 规划、SSH 命令（plink/pscp）、整合了 U 盘内各手册的实操细节 | ★ |
| 2 | R3G刷机常见问题指南.md | 6.4 KB | 按踩坑顺序记录的 169 行问答：原厂 2.28.24 封堵 U 盘刷机、OpenWRTInvasion 被杀软拦截、Breed 直刷官方镜像三类报错（kernel1 太大 / rootfs0 预处理失败 / 数据无效）等及解法 | ★ |
| 3 | R3G_ShellCrash_故障排查手册.md | 12.5 KB | 更换 ZTE 主路由后旁路由透明代理失效的完整排查：`firewall_area` 未配置导致 nftables 规则创建失败、`fw_start.sh` 关键判断行、TUN/CrashCore v1.19.17 环境说明 | ★ |
| 4 | ShellCrash部署指南.md | 9.8 KB | ShellCrash 部署 SOP v1.0：配置文件路径、运行目录、控制命令、API 9999、订阅获取与解析（剥离 URI fragment、过滤 ss 公告节点）、REALITY 节点必须 `network: http` 且不加 `flow` | ★ |
| 5 | 刷机指南_必读.txt | 5.0 KB | 面向新手的“傻瓜指南”：准备清单、Breed 盲刷、静态 IP 设置、Breed 环境变量 `xiaomi.r3g.bootfw=2`、刷 OpenWrt、装 Clash，30 分钟流程 | ★ |
| 6 | 刷机说明.txt | 5.0 KB | OpenWrt 23.05.6 版刷机说明：文件清单（breed/initramfs/sysupgrade 各自用途）、Telnet 进 Breed、`flash bank`/`boot linux` 内存启动、LuCI 刷正式固件 | ★ |
| 7 | 标准设置手册.md | 5.7 KB | 刷机后一键还原标准：硬件接线（LAN 必须留空）、UCI 网络配置命令、DHCP/WiFi/防火墙/代理设置 | ★ |
| 8 | 部署与排障手册.md | 8.1 KB | 旁路由 + TUN 透明代理部署排障：二层环路事故（`own address as source address`）、指示灯含义、Breed 命令行刷 initramfs、常见故障树 | ★ |
| 9 | 网络拓扑图.txt | 1.4 KB | ASCII 接线拓扑：光猫 192.168.1.1 → 交换机 → R3G WAN 192.168.1.66 → LAN/WiFi 192.168.1.1 → TUN 代理 :7890；附 IP 分配表 | ○ |
| 10 | dnsmasq-init-修复说明.txt | 2.2 KB | DHCP 获取 IP 失败根因：OpenWrt 23.05 ujail 沙箱限制 RAW socket，附 DHCP 四步握手日志分析与注释 `procd_add_jail` 的 sed 修复命令 | ★ |

## configs（3）

| # | 文件 | 大小 | 内容概要 | 核心 |
|---|------|------|----------|------|
| 1 | RBf60If6TGXb.yaml | 28.4 KB | 机场订阅生成的 Clash Meta 全量配置：DNS fake-ip、proxy-groups（url-test）、规则集与节点列表（552 行） | ★（含敏感口令，见下） |
| 2 | 工程文件_config.yaml | 3.8 KB | 从 R3G `/etc/ShellCrash/config.yaml` 提取并**去敏**的配置模板：mixed-port 7890、TUN system 栈（mips 必须）、敏感字段已替换为占位符 | ★ |
| 3 | nftables规则.txt | 4.8 KB | ShellCrash 透明代理实际生效的 nftables 规则集，可用于核对 TUN/TProxy 转发与 DNS 劫持链路 | ★ |

## firmware（6）

| # | 文件 | 大小 | 内容概要 | 核心 |
|---|------|------|----------|------|
| 1 | breed-mt7621-xiaomi-r3g.bin | 134 KB | Breed 不死引导（已刷入路由器；与 `U盘备份_20260825\factory.bin` 为同一文件，MD5 级相同） | ★ |
| 2 | openwrt-r3g-initramfs.bin | 5.5 MB | OpenWrt 23.05.6 临时内存系统（Breed 阶段内存启动用） | ★ |
| 3 | openwrt-r3g-sysupgrade.bin | 6.4 MB | OpenWrt 23.05.6 正式固件（LuCI 刷写） | ★ |
| 4 | xiaomi_mir3g-universal-sysupgrade.bin | 11.9 MB | Pineapple Cloner 通用 sysupgrade 镜像（WiFi Pineapple 克隆固件） | ★ |
| 5 | openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-initramfs-kernel.bin | 3.4 MB | OpenWrt 19.07.2 initramfs（旧版方案阶段产物） | ○ |
| 6 | openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-squashfs-sysupgrade.bin | 4.3 MB | OpenWrt 19.07.2 squashfs 正式固件 | ○ |

## images（1）

| # | 文件 | 大小 | 内容概要 |
|---|------|------|----------|
| 1 | 文件共享说明.jpg | 250.7 KB | 小米路由器手机 APP 功能说明截图：安全的私人数据 / 自由的文件共享 / 一键开启全盘访问 |

## 重复与原位说明

- `<原始备份目录>\U盘备份_20260825\factory.bin` 与 `breed-mt7621-xiaomi-r3g.bin` 内容完全相同（同一 134 KB 文件改了名），只保留 Breed 命名的一份。
- `<原始备份目录>\RBf60If6TGXb.yaml` 与刷机包内同名文件内容相同，只保留一份。
- `U盘备份_20260825` 根目录与 `R3G_OpenWrt_刷机包` 子目录内各有一份 `openwrt-r3g-initramfs.bin` / `openwrt-r3g-sysupgrade.bin`（同内容），归档时取子目录版本。

## 未归档但相关的材料（第三方仓库 / 历史中间产物）

以下内容确实与本任务相关，但因是第三方 GitHub 仓库副本或历史会话临时文件，未复制进 R3G-Flash，原始路径保留以备查：

| 材料 | 原始路径 | 未归档原因 |
|------|----------|-----------|
| OpenWRTInvasion 工具仓库（含 R3G v2 固件、漏洞利用脚本、README、演示 gif） | `<原始目录>\OpenWRTInvasion\OpenWRTInvasion-master\` | 第三方开源仓库（其上游已在 GitHub），属于“工具”而非本人资料；如需引用建议直接给上游链接 |
| OpenClash 源码仓库（含 luci-app-openclash、img 截图 30+ 张） | `<原始目录>\U盘备份_20260825\OpenClash-master\` | 同上，第三方仓库副本，体积大且与本机刷机记录无关 |
| r3g-rootfs.bin / r3g-kernel.bin（分区拆分文件） | `...\Marvis\workspace\conv_1a034a4702e_21559da618cb\temp\` | 历史会话的中间产物，非刷机实际使用固件 |
| 各类 `.lnk` 最近访问快捷方式 | `%APPDATA%\Microsoft\Windows\Recent\` | 仅快捷方式，无内容 |

## ⚠ 上传 GitHub 前必须处理的敏感信息

1. **`docs\网络拓扑图.txt`**：明文 WiFi 名称与密码（`YOUR_WIFI_PASS`）、完整内网 IP 规划。
2. **`configs\RBf60If6TGXb.yaml`**：机场订阅生成的节点列表，含订阅服务域名与节点 `password`（UUID 形式，可能是真实凭据），552 行全部为节点信息。
3. **`docs\R3G_ShellCrash_故障排查手册.md` / 部署与排障手册.md**：含内网 IP、SSH 端口与 root 口令提示（后者已用 `<YOUR_ROOT_PASSWORD>` 占位）。

建议做法：`RBf60If6TGXb.yaml` 直接删除或替换为 `工程文件_config.yaml` 这份去敏模板；拓扑与排障文档中的密码/域名做脱敏后再提交；如需保留历史，可用 `.gitignore` 排除 `configs/RBf60If6TGXb.yaml`。

## 内容缺口

- **scripts**：本机未发现独立的 `.sh` / `.py` / `.ps1` 刷机脚本，所有命令（`flash bank`、`boot linux`、`uci set`、`sed` 修复、`wget` 订阅）均以代码块形式内嵌在上述文档中，可按需抽取成脚本。
- **logs**：未发现 `dnsmasq.log`、`dmesg` 导出等刷机日志文件。
- **images**：仅 1 张 APP 截图；未见 Breed/ LuCI 后台操作截图与网络拓扑图图片版。
*（内容由AI生成，仅供参考）*
