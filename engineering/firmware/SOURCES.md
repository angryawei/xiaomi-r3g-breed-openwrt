# 固件来源与校验清单（SOURCES）

本目录固件全部来自**上游官方发布**，未做任何二次修改。下表的 SHA256 均为本仓库**实测值**（下载后本地计算），可与上游发布页逐一比对。

- 下载根：`https://downloads.openwrt.org/releases/<版本>/targets/ramips/mt7621/`
- 适配硬件：**小米路由器 3G（R3G）v1，MT7621A + 128MB NAND + 128MB DDR3**
- ⚠️ **v1 与 v2 固件不通用**：R3G v2 为 16MB SPI NOR 版本，硬件分区完全不同，刷入 v1 固件必砖。本项目**全部文件仅适用于 v1**；**其他机型作者从未测试，且多数没有 USB 口**，一律不可套用。判定方法见根目录 `README.md`。

---

## 一、已入库文件（7 个）

| 文件名 | 体积 | 用途 | 官方下载 URL | SHA256 |
|---|---|---|---|---|
| `breed-mt7621-xiaomi-r3g.bin` | 134 KB (137,250 B) | Breed 不死引导（Bootloader），刷机前必须先有这个 | https://breed.hackpascal.net/breed-mt7621-xiaomi-r3g.bin | `05ebb31fd889b148022346179346d91c60a1b4518bdc4d8b9717a62aec638bed` |
| `openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-initramfs-kernel.bin` | 3.38 MB (3,546,780 B) | 19.07.2 内存启动镜像（3.38 MB **< 4MB**，可由 Breed Web 直接上传） | https://downloads.openwrt.org/releases/19.07.2/targets/ramips/mt7621/openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-initramfs-kernel.bin | `8dc92a041dce94d1e4a667fcbdf0dea5ed60d90e2641a31918ce974dc3206462` |
| `openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-squashfs-sysupgrade.bin` | 4.32 MB (4,526,355 B) | 19.07.2 正式系统（老版本，占用小，适合 128MB NAND 小空间场景） | https://downloads.openwrt.org/releases/19.07.2/targets/ramips/mt7621/openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-squashfs-sysupgrade.bin | `0acd42cf8d11c796a748ebff4d1a8e071f3b2569649cdc54d1e5cdc169377d38` |
| `openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-initramfs-kernel.bin` | 5.51 MB (5,781,518 B) | 23.05.6 内存启动镜像（5.51 MB **> 4MB**，必须走内存启动路线，Breed Web 传不上去） | https://downloads.openwrt.org/releases/23.05.6/targets/ramips/mt7621/openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-initramfs-kernel.bin | `2b670fa0fa0306bd724e91ebb4062c75ad2a96fcdcec466853a6c6d8b1fc093c` |
| `openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin` | 6.39 MB (6,697,608 B) | 23.05.6 正式系统（**推荐主力版本**，dnsmasq 走 ujail，注意踩坑表） | https://downloads.openwrt.org/releases/23.05.6/targets/ramips/mt7621/openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin | `b310f1a2cf71242c10703c0e341ef10acdcc8f85823dbbf9dfc0214dd1166286` |
| `openwrt-24.10.4-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin` | 7.03 MB (7,373,448 B) | 24.10.4 正式系统（最新稳定，内核 6.6，插件生态更完整） | https://downloads.openwrt.org/releases/24.10.4/targets/ramips/mt7621/openwrt-24.10.4-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin | `a53dcf136bce8c3c942423c05d038e12d22497546c2f6a14fd06aa96344540b4` |
| `miwifi_r3g_firmware_dbc3c_2.28.46.bin` | 23.35 MB (24,482,204 B) | **原厂回滚包**（小米官方 2.28.46）。想退回原厂、或刷坏后救砖时用 | https://cdn.cnbj1.fds.api.mi-img.com/xiaoqiang/rom/r3g/miwifi_r3g_firmware_dbc3c_2.28.46.bin（官方入口 https://www1.miwifi.com/miwifi_download.html ，版本索引 https://mirom.ezbox.idv.tw/miwifi/R3G/ ） | `4b2b45e1e6c2dcacb9ad2b741345414eb8ba4bb434d5932a6dbd7e7354b20432` |

原厂回滚包官方校验值（小米发布页标注）：**MD5 `8a8db88ff46ecbb35b8dc829898dbc3c`**（本仓库实测 MD5 与之一致，文件为原版未改动）。

### 1.1 各文件许可状态（重要）

本目录所有二进制均为**上游原样收录，未修改一字节**。许可归属如下，与根目录 `LICENSE`（MIT，仅覆盖脚本）无关：

| 文件 | 许可证 | 说明 |
|---|---|---|
| `openwrt-19.07.2-*` / `openwrt-23.05.6-*` / `openwrt-24.10.4-*`（共 5 个） | **GPL-2.0** | 源码见 <https://git.openwrt.org/openwrt/openwrt.git>；本仓库分发的是未修改的官方构建产物 |
| `breed-mt7621-xiaomi-r3g.bin` | **未声明开源许可证** | 作者 hackpascal 以二进制形式免费发布，未公开源码树；本仓库不做任何授权主张，权利人异议即删 |
| `miwifi_r3g_firmware_dbc3c_2.28.46.bin` | **版权归小米科技** | 仅作回滚 / 救砖存档，不构成再分发授权，禁止商用 |

商用或二次分发前，请直接前往上表对应的上游渠道获取授权。完整许可矩阵见根目录 `README.md` §9。

---

## 二、可选文件（未入库，脚本可自动拉取）

| 文件名 | 体积 | 用途 | 官方下载 URL | SHA256 |
|---|---|---|---|---|
| `openwrt-24.10.4-ramips-mt7621-xiaomi_mi-router-3g-initramfs-kernel.bin` | 约 7 MB | 24.10.4 内存启动镜像，走"内存启动"路线时与新 sysupgrade 配套使用 | https://downloads.openwrt.org/releases/24.10.4/targets/ramips/mt7621/openwrt-24.10.4-ramips-mt7621-xiaomi_mi-router-3g-initramfs-kernel.bin | `97e4d2fed954654dbdb1a9b5b393307c83d5c116dde72d321f2f9c2f44e2bd0d` |

> 未入库原因：仓库体积控制。需要时执行 `engineering\scripts\01-fetch-firmware.ps1 -IncludeOptional` 自动下载并校验。

---

## 三、命名差异说明（容易搞混，务必看）

同一台机器在不同 OpenWrt 版本里设备代号改过名，**文件内容都是给 R3G v1 的**，不要因为名字不同以为下错：

| OpenWrt 版本 | 设备代号 | 文件名关键字 |
|---|---|---|
| 19.07.2 | `xiaomi_mir3g` | `xiaomi_mir3g-*` |
| 23.05.6 / 24.10.4 | `xiaomi_mi-router-3g` | `xiaomi_mi-router-3g-*` |

---

## 四、不在本目录的东西

`xiaomi_mir3g-universal-sysupgrade.bin`（Pineapple Cloner，Hak5 商业固件）**已移出本仓库**，原因是授权与用途不匹配（它是给 WiFi Pineapple MK7 硬件商业产品配套的，不是给 R3G 刷的开源固件）。不要去找它，也不要往 R3G 上刷。

---

## 五、上游项目与官方仓库

| 项目 | 地址 |
|---|---|
| Breed 官方发布站（作者 hackpascal，含历史版本目录） | <https://breed.hackpascal.net/> |
| Breed 历史版本 r1338（2021-12-16） | <https://breed.hackpascal.net/r1338%20%5b2021-12-16%5d/breed-mt7621-xiaomi-r3g.bin> |
| OpenWrt 源码（官方 Git） | <https://git.openwrt.org/openwrt/openwrt.git> |
| OpenWrt 源码（GitHub 镜像） | <https://github.com/openwrt/openwrt> |
| OpenWrt 官方固件下载站 | <https://downloads.openwrt.org/releases/> |
| OpenWRTInvasion（原厂提权脚本） | <https://github.com/acecilia/OpenWRTInvasion> |
| ShellCrash（透明代理脚本） | <https://github.com/juewuy/ShellCrash> |
| OpenWrt-MiR3G（第三方编译，未经验证） | <https://github.com/super5xy/OpenWrt_MiR3G> |

> **Breed 没有官方 GitHub 仓库**：作者以官方站直接发布编译好的 `.bin` 与历史版本目录，源码不公开托管在 GitHub。网上任何标称"breed 官方仓库"的地址都不是上游。
>
> **版本提示**：社区教程多建议 R3G 使用 2021 年版本（官方站的 r1338，2021-12-16）；本目录入库的是 r1416（2022-07-24），已在 v1 实机验证可正常刷 19.07.2 / 23.05.6。两者同为官方原版，差异只在版本号，详见根目录 `README.md` §7.1。

---

## 六、校验方法

Windows（PowerShell）：

```powershell
Get-FileHash .\openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin -Algorithm SHA256
```

Linux / macOS：

```bash
sha256sum -c SHA256SUMS
```

OpenWrt 设备上：

```sh
sha256sum /tmp/openwrt-*-sysupgrade.bin
```
*（内容由AI生成，仅供参考）*
