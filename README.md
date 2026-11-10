<div align="center">

# 小米路由器 3G（R3G v1）刷机完整手册

**从原厂固件到 OpenWrt 的一站式工程仓库：固件、脚本、配置模板、踩坑记录全部在此，拿到就能刷。**

**只适用于小米路由器 3G（R3G）v1 这一种机型。其他机型作者从未测试，且多数没有 USB 口，不要套用本仓库的任何内容。**

**每次改了什么、为什么改，见 [CHANGELOG.md](CHANGELOG.md)。**

</div>

---

## 一、这是什么

> **定位说明：本仓库不是刷机方案的发明者。**
> 刷机方法来自 OpenWrt、Breed 等上游项目与社区既有做法，固件为上游官方原版。本项目做的是三件事：把散落的资料整合成可复现结构、把重复劳动脚本化、在**单台 R3G v1** 上逐条实测并记录失败分支。
> 上游归属见 §7.1 与 [`engineering/firmware/SOURCES.md`](engineering/firmware/SOURCES.md)，许可边界见 §9。方法属于社区，坑和笔记属于我。

本仓库把一台小米路由器 3G（R3G **v1**，MT7621A / 128MB NAND / 128MB RAM）从原厂固件刷到 OpenWrt、并落地串行级联网关形态透明代理的**完整可用资料**整理成可复现的工程结构：

- 官方固件（含原厂回滚包）+ 官方 SHA256，全部标源、可校验；
- 刷机、备份、下载、拆包四段脚本，Windows 与路由器两端都能跑；
- 一条决策树告诉你该走哪条路线，一张踩坑表告诉你哪里会翻车。

> 本仓库所有固件均为**上游官方原版**，未做任何修改；所有哈希均为本地实测值。不含任何订阅链接、WiFi 密码、root 口令等凭据。

### 1.1 为什么值得刷 R3G（本方案的价值）

- **性价比极高**：R3G v1 二手价远低于任何同规格的 MT7621 设备，却能给到 128MB NAND + 128MB RAM + USB 3.0 + AC1200 双频。跑透明代理（ShellCrash / mihomo 内核）时 CPU 和内存都有余量，不容易因为并发连接数被打满。
- **刷机方案成熟**：Breed 引导、OpenWrt 官方 `ramips/mt7621` 支持、救砖路径全都齐备，社区验证过成千上万台，坑基本已经被踩平，本文第五节的踩坑表就是证据。**它不是"能刷"，而是"刷坏了也能救回来"。**
- **它的最佳用途不是当普通路由器**：作者建议刷完后用 **ShellCrash（CrashCore 内核）** 把它做成**全屋代理软路由**（串行级联网关形态：主路由 WAN 接 R3G LAN，R3G 开 DHCP + NAT，全屋流量自动经过它）。ShellCrash 上游仓库：[`juewuy/ShellCrash`](https://github.com/juewuy/ShellCrash)（全部上游链接见 §7.1）。理由是：与其在手机、平板、电视、游戏机上一个个装客户端、一个个改配置，不如让一个设备在网关层统一接管：任意设备连上 WiFi 就自动走代理，不用装 App、不用逐台维护，换设备也不用重新配。

### 1.2 卡住了怎么办

按这个顺序来，别硬猜：

1. 先查**第五节踩坑表**，那里是本文作者实际翻车过的点，命中率最高；
2. 再看 `docs/` 下对应的原始记录与命令输出（`logs/` 里有真实串口/终端回显）；
3. 仍然不明确的，**直接问 AI**，把现象 + 完整报错 + 你执行到的步骤一起贴给它，比只描述"刷坏了"有效得多；
4. 需要人类经验时去 **R3G 刷机社区**（恩山无线论坛、OpenWrt 官方论坛 / GitHub issue）求助，附上机型、Breed 版本、固件版本。

> 唯一不能做的事：在没搞清楚状态的情况下反复乱刷。R3G 有 Breed 兜底，但**乱刷会覆盖掉 Breed**，那才是真的变砖。

---

### 1.3 这套方案的定位与边界

这不是一套"通用 OpenWrt 代理教程"，而是**一台 R3G v1 在真实家庭网络中跑了一年多之后的实录**。下面把边界写清楚，你动手前可以先判断它是否匹配需求。

#### 它是什么

- **串行级联网关**：主路由的 WAN 口接 R3G 的 LAN 口，R3G 开 DHCP + NAT，全屋流量自动经过它。注意**不是"旁路由"**。两者接线、网段、DHCP、覆盖方式完全不同，按旁路由去接线第一步就会错。
- **纯 Redir 模式，无 TUN**：`config.yaml` 中 `tun.enable: false`，靠 iptables REDIRECT 把 TCP 流量劫持到代理内核。
- **关闭无线**：R3G 只承担有线网关职责，WiFi 交给下游主路由。
- **规则驱动的静态编排**：537 条显式规则，未使用 GEOSITE。

#### 它能做到

- 全屋设备自动覆盖，不需要逐台改网关或装客户端。
- 国内流量直接走 DIRECT，不经过代理内核的用户态处理。
- 代理内核故障时，watchdog 在 1 分钟内降级为纯 NAT 直连，**国内网络保持可用**。
- 多节点自动故障转移，大带宽流量走负载聚合组。

#### 它做不到（重要）

| 限制 | 原因 | 影响 |
|---|---|---|
| **游戏等 UDP 流量不走代理** | Redir 只劫持 TCP 的 22/80/443/8080/8443；明文 UDP 不重定向（仅 DNS 53 劫持到 1053） | 游戏联机、QUIC/HTTP3 直连。需要 UDP 代理请改用 TUN |
| **无法按终端分流** | 下游主路由做了第二层 NAT，R3G 上看不到终端真实 IP | 做不到"手机走代理、游戏机直连"这类设备级策略 |
| **P2P / UDP 打洞成功率低** | 双层 NAT，NAT 类型劣化为 Symmetric | 部分 P2P 应用、语音对局异常 |
| **R3G 是单点** | 架构决定 | R3G 故障即全屋断网 |
| **延迟低 ≠ 速度快** | 探针只测延迟，不测吞吐 | 视频/下载需人工实测后调组序 |

#### 两个会让人判断失误的配置陷阱

1. **fwmark 是双值**。`/etc/ShellCrash/configs/ShellCrash.cfg` 写 `fwmark=7894`（`0x1ed6`），但实际 iptables 规则用的是 `0x1ed8`（7896），`routing-mark` 同样是 7896。**Redir 模式下生效的只有后者**，按 cfg 的 7894 去理解规则会全错。核对：`iptables -t nat -L shellcrash -v -n | grep -i mark`。
2. **仓库里有两套部署形态**。本仓库的文档分别来自两个真实部署，参数不通用：

| 维度 | iptables 形态 | nftables / fw4 形态 |
|---|---|---|
| 防火墙 | `iptables -t nat -L shellcrash` | `nft list table inet shellcrash` |
| fwmark | `0x1ed8`（7896） | `0x1ed4` |
| `firewall_area` | 3 | 1 |
| `tun.enable` | false | true |
| fake-ip 段 | `198.18.0.1/16` | `28.0.0.0/8` |
| UDP 处理 | 不重定向（仅 DNS 53） | 与 TCP 一同打标 |

   **动手前先确认自己是哪一套**，再决定读哪份文档。判断命令：

   ```sh
   iptables -t nat -L shellcrash -n 2>/dev/null | head    # 有输出 = iptables 形态
   nft list table inet shellcrash 2>/dev/null | head      # 有输出 = nftables 形态
   ```

#### 如果你需要

| 你的需求 | 应该怎么做 |
|---|---|
| 游戏加速 / UDP 代理 | 改用 TUN 模式（R3G 上会有性能开销，需实测） |
| 设备级精细分流 | 主路由改桥接 / AP 模式，消掉双层 NAT |
| 更高吞吐 | 换 x86 或 ARMv8 设备；MT7621 已接近其能力上限 |
| 配置版本管理 | 本项目靠 `.bak_*` 快照人工回溯，未 git 化 |

#### 想深入看设计依据

- 拓扑取舍、分流规则为什么是这个顺序、选路体系怎么搭 → [`docs/串行级联网关组网与选路实录.md`](docs/串行级联网关组网与选路实录.md)
- 代理故障为什么会拖垮全网、watchdog 怎么设计 → [`docs/故障隔离与watchdog设计.md`](docs/故障隔离与watchdog设计.md)

---

## 二、适配硬件与 v1 / v2 判定（**先做这一步，否则可能刷砖**）

### 2.1 唯一适配的硬件

| 项目 | 规格 |
|---|---|
| 型号 | 小米路由器 3G（Xiaomi Mi Router 3G），**v1** |
| SoC | MediaTek MT7621A（MIPS 1004Kc，双核 880MHz） |
| 存储 | **128MB NAND Flash**（这才是 v1 的标志） |
| 内存 | 128MB DDR3 |
| 无线 | MT7603（2.4G）+ MT7612（5G），AC1200 |
| 固件架构 | `ramips/mt7621` |
| USB | **USB 3.0 × 1**（机身背面；资料中涉及 U 盘的操作依赖此口） |

> **适用范围（硬性，动手前必须读完）**
>
> 1. **本仓库只对上面这一种机型负责**：小米路由器 3G（R3G）**v1**。作者只在这一台上实测过，其余一律没有验证。
> 2. **其他机型全部未测试**，包括但不限于 R3G v2、小米路由器 4A / 4A 千兆版、3A、3C、4C，以及其他 MT7621 方案设备。本仓库**不声明兼容、不提供支持**，照刷的后果自负。
> 3. **其他机型多数没有 USB 接口**：R3G v1 背面带一个 USB 3.0 口，本资料里的 U 盘相关操作正是靠它完成；没有 USB 口的机型连这一步都无法复现。而且 Bootloader 写入方式、分区布局、救砖手段各家都不同，不存在“改个文件名就能用”。
> 4. 机型只要对不上（不是 R3G，或没有 v1 的 128MB NAND 特征），**立即停止，不要套用本文任何步骤**。

### 2.2 v1 与 v2 固件**不通用**

R3G v2 是 **16MB SPI NOR** 版本，分区布局、引导方式、镜像尺寸全部不同。**把 v1 固件刷进 v2，或者反过来，必然变砖。**

### 2.3 怎么确认自己是 v1

按可靠性从高到低，任选其一：

1. **已刷 OpenWrt / 有 SSH**：
   ```sh
   cat /proc/mtd          # 总容量接近 128MB → v1；只有 16MB → v2
   dmesg | grep -i nand   # 出现 NAND device（如 MT7621 NAND）→ v1
   ```
2. **在 Breed 里**：Breed 首页的「内存信息 / Flash 信息」会直接显示 Flash 类型与容量（`NAND 128MB` → v1）。
3. **原厂系统**：登录 miwifi.com 后台 → 路由状态/关于，查看型号与固件版本；机身底部标签型号为 `R3G`。
4. **看板子**：v1 有一颗 NAND 芯片 + 一颗内存颗粒；v2 为 SPI NOR 小容量芯片。

> 三种方法都拿不到结论时，**不要刷**。请先在原厂后台截图型号页确认。

---

## 三、三条刷机路线：先看决策树再动手

```
开始
 │
 ├─ 现在是小米原厂固件，从未刷过机？
 │    └─▶ 【路线一】OpenWRTInvasion（软件漏洞，不拆机）
 │          用 CVE-2019-18370 系列漏洞拿到 root → 写 Breed 进 Bootloader
 │          会被杀软报毒，需临时加白名单
 │
 ├─ 已经刷好 Breed，想刷正式系统，且 initramfs 镜像 < 4MB？
 │    └─▶ 【路线二】Breed Web 直接上传 initramfs（最省事）
 │          本仓库 19.07.2 initramfs = 3.38MB，可走这条
 │
 ├─ 已经刷好 Breed，但 initramfs 镜像 > 4MB？
 │    └─▶ 【路线三】Breed 控制台内存启动（mem boot）
 │          23.05.6 = 5.51MB、24.10.4 ≈ 7MB，Web 传不上，必须走这条
 │          详见 engineering/scripts/03-breed-memboot.txt
 │
 └─ 已经刷坏 / 想退回原厂？
      └─▶ 【回滚】Breed 里刷 miwifi_r3g_firmware_dbc3c_2.28.46.bin
```

### 路线一：原厂 → Breed（OpenWRTInvasion）

1. 电脑与路由器 LAN 口直连，确认原厂后台可访问（默认 `192.168.31.1` 或 `miwifi.com`）。
2. 下载 [OpenWRTInvasion](https://github.com/acecilia/OpenWRTInvasion)（Python 3 项目），安装依赖后运行 `python remote_command_execution_vulnerability.py`。
3. 按提示输入路由器 IP 与后台的 stok（登录后 URL 里的 `;stok=xxxx` 段）。
4. 拿到 telnet/ssh 后，把 Breed 写进 Bootloader：
   ```sh
   # 先把 breed-mt7621-xiaomi-r3g.bin 上传到 /tmp，再执行
   mtd write /tmp/breed-mt7621-xiaomi-r3g.bin Bootloader
   ```
5. 断电 → 按住 Reset 不放 → 插电 → 等 5~8 秒 → 浏览器开 `192.168.1.1`，看到 Breed 界面即成功。

### 路线二：Breed Web 直刷 initramfs（镜像 < 4MB）

1. 进入 Breed（断电 → 按住 Reset → 插电 → `192.168.1.1`）。
2. 「固件更新」→ 勾选「固件」→ 选择 `openwrt-19.07.2-...-initramfs-kernel.bin`（3.38MB）→ 上传。
3. 上传完成后自动启动，浏览器进 `192.168.1.1` 得到临时 OpenWrt。
4. 在临时系统里「系统 → 备份/升级」上传 `*-squashfs-sysupgrade.bin` 写入 NAND。

> 提示：想刷 23.05.6 / 24.10.4，先用 19.07.2 的 initramfs 进临时系统，再在 LuCI 里直接 sysupgrade 到目标版本即可，不必走内存启动。这是**最省事的一条捷径**。

### 路线三：Breed 控制台内存启动（镜像 > 4MB）

完整命令序列见 [`engineering/scripts/03-breed-memboot.txt`](engineering/scripts/03-breed-memboot.txt)，核心三步：

```text
wget http://192.168.1.2:8001/openwrt-23.05.6-...-initramfs-kernel.bin 0x80001000
mem read 0x80001000 16      # 应看到 27 05 19 56（uImage 魔数）
boot mem 0x80001000
```

等待 30~75 秒后 `ping 192.168.1.1` 通 → LuCI 里 sysupgrade 正式固件。

---

## 四、5 分钟快速开始（假设已刷 Breed、只想尽快上网）

### 4.1 动手前必须准备的硬件（缺一项就别开始）

| 物品 | 要求 | 为什么需要它 |
|---|---|---|
| 一台电脑 | 必须有**有线网口**（RJ45） | 进 Breed、改静态 IP、`ping 192.168.1.1` 全走这根线；USB 转网口不一定稳，不建议 |
| 同一台电脑 | 必须有 **WiFi 上网能力** | 刷机全程电脑会断网（网口被路由器独占），只有 WiFi 能继续下固件、查文档、让 Agent 保持在线 |
| 网线 | **≥ 1 米** | 太短没法把路由器挪到顺手的位置；反复"断电 + 按 Reset"时特别容易把设备从桌上拖下来 |
| 插线板 | 带独立开关更佳 | R3G 进 Breed 要反复"断电 → 按住 Reset → 上电"，插线板开关是最可靠的断电方式，比反复拔电源头稳 |

> **"为什么非要 WiFi"：这条最容易被忽略，但它是硬要求。**
>
> 刷机时电脑的有线网口是**独占给路由器**的：你要把 IP 改成静态 `192.168.1.2`、要访问 `192.168.1.1`，这条路只能通到 R3G，通不到外网。**从设静态 IP 那一刻起，这台电脑就断网了**。固件没提前下完、文档没存到本地、命令没记下来，当场就卡死。
>
> 更关键的是**用 AI Agent 代刷的场景**：Agent 靠网络才能工作，网口一切断，Agent 立刻失联，剩下步骤没人接手。所以必须让电脑**有线口服务路由器、WiFi 连外网**，两条链路并行，Agent 才能全程在线把刷机跑完。
>
> 一句话记法：**有线口给路由器，WiFi 给自己（和 Agent）。**

> **执行顺序别搞反**：先在**联网状态下**把固件下齐并校验（下面的 ①），再设静态 IP 接路由器（② 之后）。设完静态 IP，这台电脑就上不了网了，那时候才发现固件没下，只能重来。

```powershell
# ① 联网状态下先取齐固件（在仓库根目录打开 PowerShell，此时还没接路由器）
powershell -ExecutionPolicy Bypass -File .\engineering\scripts\01-fetch-firmware.ps1

# ② 电脑侧：设静态 IP 192.168.1.2 / 255.255.255.0，网线接路由器 LAN 口

# ③ 进 Breed：断电 → 按住 Reset → 插电 → 5~8 秒后浏览器访问 http://192.168.1.1

# ④ 按路线二用 19.07.2 initramfs 起临时系统（3.38MB，能直接 Web 上传）

# ⑤ 临时系统 LuCI：系统 → 备份/升级 → 上传 23.05.6 sysupgrade → 不保留配置 → 刷写
```

刷完之后：

```sh
# 路由器上：设置 root 密码与 LAN IP（默认 192.168.1.1）
passwd

# 刷机前第一件事：备份 NAND（脚本只读，安全）
sh /tmp/00-backup-nand.sh
# 按脚本末尾提示把备份取回电脑
```

---

## 五、踩坑速查表（都是本项目实测踩过的）

| 现象 | 根因 | 正确处理 |
|---|---|---|
| Breed 控制台执行 `flash bank 0x80001000 0x80000000 <大小>` 报 `Specified flash bank does not exist` | 内存启动根本不经过 flash bank，这条命令本身多余 | 跳过它，直接 `boot mem 0x80001000` |
| `boot linux 0x80001000` 卡死 / ping 报 `TTL expired in transit` | `boot linux` 直接跳到 uImage 头地址执行，initramfs 不是可执行镜像 | 改用 `boot mem 0x80001000`（由 Breed 解析 uImage 头） |
| `boot mem 0x80001000` 启动卡死或校验不过 | 部分 Breed 版本 wget 忽略地址参数；或下载地址与内核解压区重叠 | 改下到 `0x81000000`：`wget ... 0x81000000` → `mem read 0x81000000 16` 看到 `27051956` → `boot mem 0x81000000` |
| wget 报 `Connection aborted` | Python `http.server` 返回 HTTP/1.0，Breed 的 wget 不兼容 | 用 HTTP/1.1 + `Connection: close` 的自建服务器（`03-breed-memboot.txt` 做法 B） |
| Breed Web 上传固件失败 / 提示固件太大 | initramfs > 4MB（23.05.6 = 5.51MB、24.10.4 ≈ 7MB） | 走内存启动（路线三），或先用 19.07.2 initramfs 过渡 |
| 临时系统里 SSH 执行 `uci commit` / `ubus call system file_exec` 被拒 | initramfs 恢复模式默认开启 LuCI ACL，禁止敏感接口 | 改在 LuCI 网页「系统 → 备份/升级」刷写，不受 ACL 限制 |
| 犹豫 OpenClash 与 ShellCrash 怎么选 | — | **OpenClash 在 R3G v1 上可安装、可启动、可正常运行**，本项目未对它做并发压力测试。本项目主动选 ShellCrash：纯 shell 实现、依赖少、内存占用低，与 128MB 内存 + MT7621 单核的余量更匹配。这是**资源取舍**，不是 OpenClash 不可用 |
| 23.05 起 LAN 口拿不到 IP / DHCP 不响应 | 23.05 默认把 dnsmasq 跑在 **ujail 沙箱**里，沙箱限制 RAW socket 权限，DHCP 无法发包 | `uci set dhcp.@dnsmasq[0].ujail='0'; uci commit dhcp; /etc/init.d/dnsmasq restart`；仍无效则注释 `/etc/init.d/dnsmasq` 中 `procd_add_jail` 相关行 |
| ShellCrash 显示运行中，但 `nft list table inet shellcrash` 是空表，代理不生效 | `/etc/ShellCrash/configs/ShellCrash.cfg` 缺 `firewall_area`（及 `ipv6_redir`），`fw_start.sh` 里 `"" -le 3` 报 `sh: out of range`，nftables 规则被跳过 | 补 `firewall_area=1` 与 `ipv6_redir=OFF`，再 `sh /etc/ShellCrash/starts/fw_start.sh` |
| 在内存系统里执行 `reboot` 后进不去 OpenWrt，反而出现小米原厂界面 | 内存系统重启即消失，Breed autoboot 启动了 NAND 上的原厂固件 | 这是正常回退，**不是变砖**；重新走路线二/三即可 |
| 游戏联机不走代理、部分视频明明要走代理却仍是直连 | Redir 模式只劫持 TCP 的 22/80/443/8080/8443；明文 UDP 不做重定向，QUIC/HTTP3 因此直连 | **预期行为，不是配置错误**。需要 UDP / QUIC 走代理只能换 TUN 模式；唯一的 UDP 例外是 DNS 53 劫持到 1053 |
| 按 `ShellCrash.cfg` 的 `fwmark=7894` 排查，规则就是匹配不上 | cfg 里的 7894（`0x1ed6`）在 Redir 模式下**不生效**，实际 iptables 规则用的是 `0x1ed8`（7896） | 以实际规则为准：`iptables -t nat -L shellcrash -v -n \| grep -i mark`。按 cfg 值去理解规则会得出完全错误的判断 |
| 照本文档改完，规则写得对但流量不进来 | 仓库里存在两套部署形态（iptables 形态与 nftables/fw4 形态），fwmark、`firewall_area`、`tun.enable`、fake-ip 段全部不同，混用会失效 | 先判断当前是哪一套：`iptables -t nat -L shellcrash -n`（有输出即 iptables 形态）或 `nft list table inet shellcrash`（有输出即 nftables 形态），再按对应文档读 |
| OpenWRTInvasion 被杀软报毒/隔离 | 漏洞利用脚本被判定为 HackTool | 临时把该目录加入 Defender 排除项，刷完立即恢复 |

---

## 六、目录说明

```
r3g刷机（github上传版）/
├── README.md                    本文件：路线、快速开始、踩坑表
├── CHANGELOG.md                 更新记录：每次改动的内容、原因与影响
├── listing.md                   文件级清单（来源与用途索引）
├── .gitignore / .gitattributes  版本控制配置
├── docs/                        实测文档：完整配置教程、故障排查手册、
│                                串行级联网关组网实录、故障隔离设计、
│                                标准设置手册、部署与排障、dnsmasq 修复说明等
├── images/                      拓扑图等插图
└── engineering/                 工程目录（可复现的全部资产）
    ├── configs/                 配置模板（已脱敏：ShellCrash 模板、nftables 规则）
    ├── firmware/                官方固件（7 个 bin）+ SOURCES.md + SHA256SUMS
    └── scripts/
        ├── 00-backup-nand.sh          刷机前 NAND 全量/分区备份（OpenWrt 上跑）
        ├── 01-fetch-firmware.ps1      Windows 端按 SOURCES.md 下载并强校验
        ├── 02-split-sysupgrade.py     拆 sysupgrade 为 kernel1 / rootfs0
        ├── 03-breed-memboot.txt       Breed 内存启动命令序列
        ├── 03-verify-firmware.ps1     Windows 端本地固件 SHA256 校验
        ├── 03-verify-firmware.sh      Linux / macOS / OpenWrt 端同款校验
        └── 04-check-upstream.py       巡检上游地址与哈希是否变更（CI 每周跑）
```

各文档的分工：

| 文件 | 用途 |
|---|---|
| [docs/R3G完整配置教程.md](docs/R3G完整配置教程.md) | 从刷机到网关侧透明代理配置的完整流程 |
| [docs/R3G刷机常见问题指南.md](docs/R3G刷机常见问题指南.md) | 刷机阶段的异常处理（wget、boot、ACL 等） |
| [docs/ShellCrash部署指南.md](docs/ShellCrash部署指南.md) | ShellCrash 部署标准流程：配置路径、控制命令、API、订阅解析 |
| [docs/R3G_ShellCrash_故障排查手册.md](docs/R3G_ShellCrash_故障排查手册.md) | 透明代理落地后的排障 |
| [docs/dnsmasq-init-修复说明.txt](docs/dnsmasq-init-修复说明.txt) | ujail 沙箱导致 DHCP 故障的修复细节 |
| [docs/标准设置手册.md](docs/标准设置手册.md) | 系统层的标准设置项 |
| [docs/部署与排障手册.md](docs/部署与排障手册.md) | 部署顺序与常见故障的处理清单 |
| [docs/串行级联网关组网与选路实录.md](docs/串行级联网关组网与选路实录.md) | **设计依据**：拓扑取舍、地址规划、分流顺序原理、15 个代理组的分工、延迟≠带宽的实测反例 |
| [docs/故障隔离与watchdog设计.md](docs/故障隔离与watchdog设计.md) | **设计依据**：两种失效模式的区分、三层故障隔离、watchdog 四个设计要点、验证方法 |

---

## 七、固件获取与校验

固件清单、体积、用途、官方 URL、SHA256 全部在 [`engineering/firmware/SOURCES.md`](engineering/firmware/SOURCES.md)；汇总哈希在 [`engineering/firmware/SHA256SUMS`](engineering/firmware/SHA256SUMS)。

一键下载 + 强制校验（哈希不匹配立即中止，绝不使用错误文件）：

```powershell
# 仅下载已入库的 7 个固件
powershell -ExecutionPolicy Bypass -File .\engineering\scripts\01-fetch-firmware.ps1

# 同时下载可选的 24.10.4 initramfs
powershell -ExecutionPolicy Bypass -File .\engineering\scripts\01-fetch-firmware.ps1 -IncludeOptional
```

下载完成后单独再校验一遍（不重新下载，只比哈希，**刷机前必做**）：

```powershell
# Windows：逐个比对 SHA256SUMS，失败时打印期望值 / 实际值
powershell -ExecutionPolicy Bypass -File .\engineering\scripts\03-verify-firmware.ps1

# 固件在别的目录，或只校验手头已有的几个
powershell -ExecutionPolicy Bypass -File .\engineering\scripts\03-verify-firmware.ps1 -Dir D:\firmware -AllowMissing
```

```bash
# Linux / macOS / OpenWrt（POSIX sh 编写，兼容 BusyBox）
chmod +x engineering/scripts/03-verify-firmware.sh
./engineering/scripts/03-verify-firmware.sh
```

脚本以退出码交付结果（`0` 通过 / `1` 不通过 / `2` 环境或清单错误），可直接串进自动化流程；失败时输出差异明细，不需要肉眼比对 64 位十六进制。**校验不通过就不要刷。**

上游地址本身是否还有效，用巡检脚本查（也由 GitHub Actions 每周自动跑一次）：

```bash
python engineering/scripts/04-check-upstream.py --mode head   # 只比体积，快
python engineering/scripts/04-check-upstream.py --mode deep   # 下载算哈希，严
```

已入库 7 个文件（合计约 50.1MB，单文件最大 23.35MB）：

| 文件 | 用途 |
|---|---|
| `breed-mt7621-xiaomi-r3g.bin` | Breed 不死引导 |
| `openwrt-19.07.2-...-initramfs-kernel.bin` | 19.07.2 内存启动（3.38MB，可 Web 直传） |
| `openwrt-19.07.2-...-squashfs-sysupgrade.bin` | 19.07.2 正式系统 |
| `openwrt-23.05.6-...-initramfs-kernel.bin` | 23.05.6 内存启动（5.51MB，需 mem boot） |
| `openwrt-23.05.6-...-squashfs-sysupgrade.bin` | 23.05.6 正式系统（推荐主力） |
| `openwrt-24.10.4-...-squashfs-sysupgrade.bin` | 24.10.4 正式系统（最新） |
| `miwifi_r3g_firmware_dbc3c_2.28.46.bin` | 原厂回滚包（2.28.46，救砖/退货用） |

> `xiaomi_mir3g-universal-sysupgrade.bin` 是**第三方为商业硬件产品编译的镜像**，既非 OpenWrt 官方产物，也不是为 R3G 编译的，**不在本仓库**，勿刷入 R3G。

### 7.1 上游项目与官方链接

刷机用到的每一环，上游地址都在这里。**遇到"某文件哪来的、是不是正版"的疑问，回到这张表核对。**

| 项目 | 用途 | 官方站 | GitHub |
|---|---|---|---|
| **Breed 不死引导** | 刷机底座（Bootloader），本仓库最核心的前置 | <https://breed.hackpascal.net/> | 上游**未托管在 GitHub**（作者 hackpascal 直接以官方站发布二进制与历史版本目录），不要去找所谓"breed 官方仓库" |
| **OpenWrt 源码** | 固件本体，`ramips/mt7621` 目标含 R3G 支持 | <https://git.openwrt.org/openwrt/openwrt.git> | <https://github.com/openwrt/openwrt> |
| **OpenWrt 固件下载站** | 官方 sysupgrade / initramfs / `sha256sums` | <https://downloads.openwrt.org/releases/> | —（固件只在官方下载站发布，不在 GitHub Releases） |
| **R3G 设备 DTS** | 分区定义，可核对 128MB NAND 与 v1/v2 差异 | 源码树内 `target/linux/ramips/dts/mt7621_xiaomi_mi-router-3g.dts` | 同上仓库同一路径 |
| **OpenWRTInvasion** | 原厂固件拿 root/SSH 的漏洞利用脚本（本文路线一） | — | <https://github.com/acecilia/OpenWRTInvasion> |
| **ShellCrash** | 透明代理一键部署脚本，R3G 上跑代理的主力（内核由脚本自行下载） | — | <https://github.com/juewuy/ShellCrash> |
| **OpenWrt-MiR3G**（第三方编译） | 别人云编译好的 R3G 整包，带 Releases，适合懒人**另行**试 | — | <https://github.com/super5xy/OpenWrt_MiR3G> |

> **关于 Breed 版本（重要，别当耳边风）**
>
> 社区教程（如 openwrt.ai 的 R3G 篇）普遍建议：R3G 用 **2021 年那版** Breed，而不是最新的 2022-07-24 版。官方站保留了历史版本目录，可直接取：
> <https://breed.hackpascal.net/r1338%20%5b2021-12-16%5d/breed-mt7621-xiaomi-r3g.bin>
>
> 本仓库入库的是 **r1416（2022-07-24，134KB）**，作者在这一台 v1 上实测刷 19.07.2 与 23.05.6 均正常。**两者都来自同一个官方站，都是原版**，差异只在版本。结论：已实测版本可以直接用；真遇到莫名异常，回退 r1338 是社区常见做法，但**不要因为"社区说旧的好"就跳过校验**，拿到任何 breed 都先比哈希/看来源。

> 注意：上表最后一行是**第三方编译固件**，不是 OpenWrt 官方产物，默认账号密码、内置插件都由编译者决定。本仓库**没有验证过它**，只作为"想省事"的备选项列出，出问题与本项目无关。

---

## 八、免责与变砖回滚

### 8.1 免责

刷机有风险，操作不当会导致设备无法启动。本仓库提供的是**经过实测的资料与脚本**，但不对任何因操作失误、硬件差异（尤其误刷 v2）、供电中断造成的损坏负责。请确认：

- 全程使用原装或足额 12V/1A 电源，刷写过程**禁止断电**；
- 已按第二节确认自己是 **v1**；
- 已按第五节完成 NAND 备份；
- **手上这台就是 R3G v1**：本仓库对其他机型（含没有 USB 口的型号）从未测试，套用即属超出适用范围，后果不在本仓库的责任边界内。

### 8.2 变砖分级与应对

| 状态 | 表现 | 处理 |
|---|---|---|
| 软故障 | 系统起不来，但能进 Breed（`192.168.1.1`） | 在 Breed 里重刷 sysupgrade，或刷回原厂包 |
| 配置错乱 | 能进系统但网络全错 | Breed 里刷 sysupgrade 并**不保留配置** |
| 想退回原厂 | 不适用 | Breed「固件更新」上传 `miwifi_r3g_firmware_dbc3c_2.28.46.bin` |
| Bootloader 损坏 | 进不去 Breed，插电无反应/只有灯闪 | 需 USB-TTL（CH341A/CP2102）接板载 UART，用 MTK 官方 `mtk_uartboot` 或 tftpd 恢复；属硬件级操作，不在本文范围 |

回滚要点：原厂包刷回后首次启动较慢（约 2~3 分钟），期间不要断电；恢复出厂设置后 WiFi 名称回到 `Xiaomi_XXXX`，需重新配置。

---

## 九、许可

**本仓库自有内容（脚本、文档、配置模板）统一采用 MIT 许可证**，全文见根目录 [`LICENSE`](LICENSE)。简言之：可自由使用、修改、分发、商用，唯一义务是保留版权声明与许可声明。

### 9.1 为什么不给文档单独上限制性许可

本仓库文档的大量事实来自社区既有教程，作者做的是整合与实测。把这类内容再套上"相同方式共享"一类的条款，等于给公共知识加一道门，自己也是从公共资源里取的，再对下游设限并不合适。用 MIT 让信息自由流动，署名由 `LICENSE` 里的版权声明和 git 提交历史体现，这已经够了。

### 9.2 哪些内容不在本仓库授权范围内

**固件二进制不是本项目的作品，MIT 许可证不覆盖它们。** 逐文件许可状态见 [`engineering/firmware/SOURCES.md`](engineering/firmware/SOURCES.md) §1.1，此处只列结论：

| 内容 | 版权 / 许可 | 本仓库的角色 |
|---|---|---|
| OpenWrt 固件（5 个） | GPL-2.0，版权属上游 OpenWrt 项目 | 原样汇集，未修改一字节 |
| Breed 引导程序 | 作者 hackpascal，以二进制形式免费发布，未公开源码、未声明开源许可证 | 原样汇集，不对其授权状态作任何主张，权利人异议即删 |
| 小米原厂固件 | 版权归小米科技 | 仅作回滚 / 救砖存档，不构成再分发授权 |

商用或二次分发固件前，请直接前往各上游获取授权，本仓库无权代为授权。

### 9.3 免责

刷机存在变砖风险。作者仅在两台 R3G v1 上验证过本仓库内容，对其他机型、其他固件组合不做任何兼容性承诺。因使用本仓库内容导致的设备损坏、数据丢失、保修失效，作者不承担责任。使用即视为知悉并接受。

---

<div align="center">

**刷机前请务必确认：确认 v1、备份 NAND、不要断电。**
