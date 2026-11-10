# 小米 R3G 刷机资料清单

本文件是仓库内容索引，同时记录整理口径。整理时间 2026-11-01，最后更新 2026-11-10。

所有凭据均已替换为占位符（`YOUR_*`、`example.com`、`<YOUR_ROOT_PASSWORD>`），固件的真实性由 `engineering/firmware/SHA256SUMS` 保证。

---

## 一、目录结构

```
r3g/
├── README.md            入口：路线决策树、快速开始、踩坑速查表
├── listing.md           本文件（内容索引）
├── CHANGELOG.md         文档变更记录
├── LICENSE              自有内容 MIT，固件归上游
├── .gitignore           固件入库策略与凭据排除规则
├── .gitattributes       换行符与二进制标记
├── docs/                实测文档 12 个
├── images/              插图 1 个
├── logs/                日志占位（无实际日志入库）
└── engineering/
    ├── configs/         配置模板 2 个
    ├── firmware/        固件 7 个 + 来源与校验清单
    └── scripts/         脚本 4 个 + 说明
```

## 二、docs（12）

| # | 文件 | 大小 | 内容 |
| --- | --- | --- | --- |
| 1 | `R3G完整配置教程.md` | 16.2 KB | 刷机与代理的实操参数：硬件参数、三步刷机流程、ShellCrash 离线安装与配置持久化、API 切节点、TUN 切换，每步附验证方法与失败判据 |
| 2 | `R3G刷机常见问题指南.md` | 5.7 KB | 按踩坑顺序整理的问答：原厂 2.28.24 封堵 U 盘刷机、OpenWRTInvasion 被杀软拦截、Breed 直刷的三类报错及解法 |
| 3 | `R3G_ShellCrash_故障排查手册.md` | 11.8 KB | 更换主路由后透明代理失效的完整排查：`firewall_area` 未配置导致规则创建失败、`fw_start.sh` 关键判断行、TUN 与 CrashCore v1.19.17 环境说明 |
| 4 | `ShellCrash部署指南.md` | 9.7 KB | 部署 SOP：配置文件路径、运行目录、控制命令、API 9999、订阅解析（剥离 URI fragment、过滤公告节点）、REALITY 节点必须 `network: http` 且不加 `flow` |
| 5 | `串行级联网关组网与选路实录.md` | 17.3 KB | 串行级联网关形态的实测记录：iptables 形态参数、关闭无线的硬件依据、分流规则顺序、15 个代理组的分工、配置演进时间线 |
| 6 | `故障隔离与watchdog设计.md` | 12.1 KB | 代理故障不拖垮全网的三层隔离设计：规则层隔离、双条件探活、fail-open 降级，含三个验证方法与已知局限 |
| 7 | `刷机指南_必读.txt` | 5.0 KB | 面向新手的准备清单与 30 分钟流程：Breed 盲刷、静态 IP、`xiaomi.r3g.bootfw=2`、刷 OpenWrt、装代理 |
| 8 | `刷机说明.txt` | 5.0 KB | OpenWrt 23.05.6 刷机说明：文件清单与各自用途、Telnet 进 Breed、`flash bank` / `boot linux` 内存启动、LuCI 刷正式固件 |
| 9 | `标准设置手册.md` | 5.5 KB | 刷机后还原标准：硬件接线、UCI 网络配置命令、DHCP/WiFi/防火墙/代理设置 |
| 10 | `部署与排障手册.md` | 7.9 KB | 部署排障：二层环路事故（`own address as source address`）、指示灯含义、Breed 命令行刷 initramfs、故障树 |
| 11 | `网络拓扑图.txt` | 1.4 KB | ASCII 接线拓扑与 IP 分配表，附「LAN 口不接线」的环路规避说明 |
| 12 | `dnsmasq-init-修复说明.txt` | 2.2 KB | DHCP 获取失败根因：23.05 的 ujail 沙箱限制 RAW socket，含四步握手日志分析与 `procd_add_jail` 的 sed 修复命令 |

## 三、engineering/configs（2）

| # | 文件 | 大小 | 内容 |
| --- | --- | --- | --- |
| 1 | `工程文件_config.yaml` | 3.8 KB | 从 R3G 实际配置提取并脱敏的模板：mixed-port 7890、TUN system 栈（mips 必须）、`tun.enable: false`、敏感字段为 `<YOUR_PUBLIC_KEY>` / `<YOUR_SHORT_ID>` 占位符 |
| 2 | `nftables规则.txt` | 4.8 KB | ShellCrash 透明代理实际生效的 nftables 规则集，用于核对 TUN/TProxy 转发与 DNS 劫持链路 |

## 四、engineering/firmware（7 个固件 + 2 个说明）

| # | 文件 | 大小 | 内容 |
| --- | --- | --- | --- |
| 1 | `breed-mt7621-xiaomi-r3g.bin` | 134 KB | Breed 不死引导，版本 r1416（2022-07-24） |
| 2 | `miwifi_r3g_firmware_dbc3c_2.28.46.bin` | 23.3 MB | 小米原厂固件，用于回滚 |
| 3 | `openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-initramfs-kernel.bin` | 3.4 MB | 19.07.2 临时内存系统，Breed Web 可直接上传 |
| 4 | `openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-squashfs-sysupgrade.bin` | 4.3 MB | 19.07.2 正式固件 |
| 5 | `openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-initramfs-kernel.bin` | 5.5 MB | 23.05.6 临时内存系统，超过 Breed Web 上传上限，走内存启动 |
| 6 | `openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin` | 6.4 MB | 23.05.6 正式固件 |
| 7 | `openwrt-24.10.4-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin` | 7.0 MB | 24.10.4 正式固件，需先用 19.07.2 initramfs 进临时系统再刷 |

说明文件：

- `SOURCES.md`：各固件的上游 URL、版本命名差异（19.07.2 用 `xiaomi_mir3g`，23.05.6 起改为 `xiaomi_mi-router-3g`）、v1/v2 适配警告。
- `SHA256SUMS`：7 个固件的实际哈希，`sha256sum -c SHA256SUMS` 格式，可直接校验。

## 五、engineering/scripts（4）

| # | 文件 | 大小 | 内容 |
| --- | --- | --- | --- |
| 1 | `00-backup-nand.sh` | 7.2 KB | 刷机前 NAND 全量备份（OpenWrt 侧执行，只读） |
| 2 | `01-fetch-firmware.ps1` | 7.8 KB | 按 `SOURCES.md` 下载固件并强制 SHA256 校验（Windows 侧） |
| 3 | `02-split-sysupgrade.py` | 9.9 KB | 把 sysupgrade 固件拆成 kernel1 / rootfs0 两个分区文件 |
| 4 | `03-breed-memboot.txt` | 7.9 KB | Breed 控制台内存启动（mem boot）的命令序列与失败处理 |

`README.txt` 记录四个脚本的调用顺序与前置条件。

## 六、images 与 logs

- `images/文件共享说明.jpg`（250.7 KB）：小米路由器手机 APP 的功能说明截图。
- `logs/README.txt`：说明日志未入库的原因，并指向几份含日志摘录的文档。

## 七、内容边界

本仓库只覆盖两类内容：**刷机**（原厂到 OpenWrt 的完整路径与救砖）与**代理**（ShellCrash 部署、透明代理、故障隔离）。其他用途的配置不在收录范围。

已知缺口：

- 本机未保留独立的刷机日志（`dmesg` 导出、`dnsmasq.log`），相关现象只以摘录形式记录在文档中。
- 缺少 Breed 与 LuCI 后台的操作截图，只有一张 APP 截图。
- 24.10.4 只入库 sysupgrade，未入库对应的 initramfs。
