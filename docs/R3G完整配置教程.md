# R3G 刷机与 ShellCrash 代理部署实操记录

> 适用设备：小米路由器 3G（R3G v1，MT7621，UBI 117MB 高配）
> 固件：OpenWrt 19.07.2（过渡与验证）、23.05.6 / 24.10.4（长期使用）
> 本文记录本机从原厂固件到代理跑通的具体参数与踩坑结论，每一步给出验证方法与失败判据。

本文与仓库其他文档的分工：

| 文档 | 负责内容 |
| --- | --- |
| `README.md` | 选型、路线决策树、固件清单与速查表 |
| 本文 | 刷机与代理的具体参数、命令原文、失败判据 |
| `docs/ShellCrash部署指南.md` | 部署 SOP 与疑难定位流程 |
| `docs/串行级联网关组网与选路实录.md` | 串行级联网关形态的拓扑与选路设计 |

> **部署形态声明（先读这条，否则参数会对不上）**
>
> 本文第三章的 ShellCrash 参数取自 R3G 直接承担网关与 WiFi 接入的形态：`firewall_area=1`、启用 TUN、`fake-ip-range` 为 `28.0.0.0/8`。
>
> 仓库另有 **iptables / Redir 形态**的实测记录（R3G 关闭无线、作为串行级联网关串在主路由之后）：`firewall_mod=iptables`、`firewall_area=3`、`tun.enable: false`、`fwmark` 生效值 `0x1ed8`、`fake-ip` 段 `198.18.0.1/16`，详见 `docs/串行级联网关组网与选路实录.md` 与 `docs/故障隔离与watchdog设计.md`。
>
> 两套形态的分流规则、TUN 开关、DNS 处理均不同，参数不可混用。判别当前设备属于哪一套，SSH 登入后执行：
>
> ```sh
> uci get shellcrash.config.firewall_area
> grep -E 'tun|fake-ip' /etc/ShellCrash/yamls/config.yaml
> ```
>
> 输出 `firewall_area=3` 且 `enable: false` 即为 iptables / Redir 形态，`firewall_area=1` 且 `enable: true` 即为本文所记录的 TUN 形态。

---

## 一、硬件与地址规划

| 项目 | 值 |
| --- | --- |
| 设备 | 小米路由器 3G（R3G v1） |
| CPU | MT7621，mipsel 24kc，softfloat |
| 存储 | UBI 117MB（高配版） |
| WAN | 192.168.1.54，由上级交换机 DHCP 分配 |
| 上级网段 | 192.168.1.0/22 |
| SSH | 22/tcp，root，密码见个人凭据，仓库内一律写作 `YOUR_ROOT_PASSWORD` |
| 代理 API | 127.0.0.1:9999 |
| Breed 引导 | `breed-mt7621-xiaomi-r3g.bin` |

电脑侧工具为 PuTTY 套件的 `plink76.exe` 与 `pscp76.exe`：

```sh
plink76.exe -ssh -batch -pw YOUR_ROOT_PASSWORD root@192.168.1.54
pscp76.exe -pw YOUR_ROOT_PASSWORD <本地文件> root@192.168.1.54:/tmp/
```

### 1.1 架构判定（决定代理内核选型）

MT7621 是 softfloat 平台。代理内核若取成 hardfloat 版本，运行时报 `Illegal instruction`。刷机后先确认架构：

```sh
uname -m
opkg print-architecture
```

预期输出：`uname -m` 返回 `mips`，`opkg print-architecture` 列表中含 `mipsel_24kc`。
失败判据：`uname -m` 返回 `mips64` 说明刷错固件型号，需回到刷机流程重刷。

---

## 二、刷机流程

### 2.1 OpenWRTInvasion 开启 SSH/Telnet（仅原厂固件阶段）

适用于尚未刷入第三方固件的原厂系统，利用原厂 Web 的 `stok` 校验漏洞执行命令并拉起 Telnet/SSH。

1. 电脑用网线接 R3G 原厂 LAN 口，登录原厂管理页。
2. 从浏览器地址栏取 `stok` 值（`http://192.168.1.1/cgi-bin/luci/;stok=<此串>/web/home`）。
3. 运行 OpenWRTInvasion（Python 3），按提示填入路由器 IP 与 `stok`。
4. 工具执行成功后，`telnet 192.168.1.1` 或 `ssh root@192.168.1.1` 可进入 root shell。

验证：

```sh
telnet 192.168.1.1
```

预期：出现 `root@XiaoQiang:~#` 提示符（部分版本为空密码，直接回车）。
失败判据：工具报 `stok` 无效或 401，说明原厂固件版本与该漏洞不匹配；路由器若已非原厂系统，此步骤不适用，直接走 2.2。

### 2.2 U 盘盲刷 Breed

本机主刷路径。R3G 的 Breed 可通过 U 盘加 Reset 键触发，无需已有 shell。

1. U 盘格式化为 **FAT32**，把 `breed-mt7621-xiaomi-r3g.bin` 放在根目录。
2. 路由器断电。
3. U 盘插入路由器 USB 口。
4. 按住 Reset 键不放，插电。
5. 观察指示灯，**黄灯快速闪烁**后松开 Reset。

验证：指示灯由常亮转为快速闪烁即表示已进入 Breed 并完成刷写。
失败判据：
- 通电 30 秒后指示灯仍常亮不闪：U 盘未插紧、U 盘为 exFAT/NTFS 而非 FAT32、或文件不在根目录。
- 闪烁后无法进入 Breed Web：断电重来一次；仍失败则用 2.1 的 shell 路径写入。

### 2.3 进入 Breed Web

1. 电脑网卡设静态地址：IP `192.168.1.10`，掩码 `255.255.255.0`，网关 `192.168.1.1`。
2. 网线接路由器 **LAN 口**（灰色口），不要接 WAN 口（蓝色口）。
3. 浏览器访问 `http://192.168.1.1`。

验证：出现黑底黄字的 Breed 配置界面，界面顶部显示 Breed 版本与设备型号。
失败判据：页面打不开时，先 `ping 192.168.1.1` 确认静态地址生效；能 ping 通但页面不出，换浏览器禁用缓存或改用无痕窗口。

### 2.4 刷入 OpenWrt

固件文件名在 19.07.2 与 23.05.6 之间有过变更，注意区分：

| 版本 | initramfs | sysupgrade |
| --- | --- | --- |
| 19.07.2 | `openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-initramfs-kernel.bin` | `openwrt-19.07.2-ramips-mt7621-xiaomi_mir3g-squashfs-sysupgrade.bin` |
| 23.05.6 | `openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-initramfs-kernel.bin` | `openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin` |
| 24.10.4 | 无（直接 sysupgrade） | `openwrt-24.10.4-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin` |

刷机前先校验固件完整性，`SHA256SUMS` 在 `engineering/firmware/` 目录下：

```sh
# Linux / macOS
cd engineering/firmware && sha256sum -c SHA256SUMS
```

```powershell
# Windows PowerShell
Get-FileHash .\openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-3g-squashfs-sysupgrade.bin -Algorithm SHA256
```

预期：`sha256sum -c` 逐行输出 `OK`；PowerShell 输出的 Hash 值与 `SHA256SUMS` 中同一文件名后的值逐字符一致。
失败判据：出现 `FAILED` 或哈希不一致，说明文件下载损坏或被中间层篡改，重新下载，不要刷入。

刷入步骤：

1. Breed 界面进入「环境变量」，新增 `xiaomi.r3g.bootfw` = `2`。缺这一项，重启会回退原厂固件。
2. 「固件更新」选择 initramfs 文件上传，约 2 分钟。initramfs 运行在内存中，重启即丢，用于验证固件能否启动。
3. initramfs 启动后，在 LuCI 或 SSH 中上传 sysupgrade 文件，**不保留配置**刷入，约 3 分钟。

验证：

```sh
cat /proc/mtd
```

预期：能看到 `mtd0: ... "u-boot"`、`mtd1: ... " u-boot-env"`、以及容量约 117MB 的 `ubi` 分区。
失败判据：
- Breed 提示「数据无效」或拒绝上传：直接刷 sysupgrade 包会被拒，改走 initramfs 过渡。
- 刷完后反复重启回原厂：`xiaomi.r3g.bootfw` 未设为 2，回 Breed 重新设置。
- initramfs 能启动但 sysupgrade 后起不来：分区大小与固件不符（低配版 UBI 小于 117MB），换对应版本固件。

---

## 三、ShellCrash 代理部署

### 3.1 离线安装

R3G 上直接跑在线安装脚本容易失败，本机采用电脑侧准备、pscp 上传的方式。

1. **内核选 softfloat**：`mihomo-mipsle-softfloat`，文件名形如 `mihomo-mipsle-soft.gz`。hardfloat 版本会 `Illegal instruction`。
2. **gz 在电脑侧压好**：R3G 上执行 gzip 会超时，且 `/tmp` 空间不足。电脑上压缩完成后用 pscp 上传为 `CrashCore.gz`。
3. ShellCrash 版本 1.9.4，安装目录是 `/etc/ShellCrash`（注意不是 `/etc/ShellClash`）。安装时把 `TMPDIR` 指到 Flash，避免 `/tmp` 写满。

```sh
# 电脑侧上传
pscp76.exe -pw YOUR_ROOT_PASSWORD CrashCore.gz root@192.168.1.54:/tmp/
```

```sh
# 路由器侧，按 ShellCrash 安装流程放置内核后重启服务
/etc/init.d/shellcrash restart
```

验证：

```sh
ls -l /etc/init.d/shellcrash
pidof CrashCore
```

预期：`/etc/init.d/shellcrash` 存在且可执行，`pidof` 返回一个进程号。
失败判据：
- `ls` 报不存在：启动脚本名是全小写 `shellcrash`，`ShellCrash` 这个路径不存在。
- `pidof CrashCore` 无输出：内核文件未放到正确位置（`/etc/ShellCrash/CrashCore`），或架构不匹配，查看 `/etc/ShellCrash/.start_error`。

### 3.2 配置持久化

修改必须写 `/etc/ShellCrash/yamls/config.yaml`，这是 `core_config` 的来源。只改 `/tmp/ShellCrash/config.yaml` 会被启动脚本 `clash_modify.sh` 覆盖。`bfstart.sh` 检测到 `yamls/config.yaml` 存在时，会跳过订阅下载直接使用该文件。

```sh
vi /etc/ShellCrash/configs/ShellCrash.cfg
```

该文件至少写入两项，缺失会导致 `fw_start.sh` 变量为空报错、透明代理规则不加载：

```
firewall_area=1
ipv6_redir=OFF
```

`firewall_area=1` 表示本机加局域网，为本机推荐值。

DNS 段必须指向真实公共 DNS。填 `127.0.0.1` 会形成自引用死循环：

```yaml
dns:
  enable: true
  listen: :1053
  default-nameserver:
    - 223.5.5.5
  direct-nameserver:
    - 223.5.5.5
  nameserver:
    - 223.5.5.5
  enhanced-mode: fake-ip
  fake-ip-range: 28.0.0.0/8
```

验证：

```sh
nft list table inet shellcrash | grep -c chain
```

预期：输出大于 0 的整数，表示规则已加载。
失败判据：命令报 `No such file or directory` 或计数为 0，检查 `firewall_area` 与 `ipv6_redir` 是否都在 `ShellCrash.cfg` 中，补齐后执行 `sh /etc/ShellCrash/starts/fw_start.sh` 手动加载一次。

### 3.3 订阅导入（在线拉取失败的兜底）

在线订阅常见失败形式：服务端返回 520/522、`HTTP 403 token is error`、即使 curl 模拟 Clash Verge 的 UA 仍返回 403。兜底流程：

1. 在已有代理的电脑上，从 Clash Verge 的 profiles 目录取出已下载的 YAML。
2. 过滤占位节点：`server` 为 `'1'` 或 `'11'`、`port` 为 1 或 11 的公告/教程条目，这类节点会污染 `url-test` 分组。
3. 合并配置骨架，写入 `yamls/config.yaml` 后上传。

```sh
pscp76.exe -pw YOUR_ROOT_PASSWORD config.yaml root@192.168.1.54:/etc/ShellCrash/yamls/config.yaml
```

```sh
kill $(pidof CrashCore)
/etc/init.d/shellcrash restart
```

YAML 生成注意：节点压成单行会导致 CrashCore 的 `-t` 校验失败，ShellCrash 随即回退到基础配置。用 `default_flow_style=True` 生成流式格式可以通过校验。

验证：

```sh
wget -q -O - http://127.0.0.1:9999/proxies | head -c 300
```

预期：返回 JSON，`proxies` 字段中含订阅里的节点名。
失败判据：返回 `{}` 或只有 `DIRECT`/`REJECT`，说明 `yamls/config.yaml` 未生效，确认文件路径与 YAML 是否通过 `-t` 校验。

### 3.4 API 切节点

mihomo REST API 用 `PUT /proxies/<组名>`，body 为 `{"name":"<节点名>"}`。

R3G 上没有 curl 和 base64，中文 body 用 printf 十六进制转义写入文件，再用 wget 的 `--body-file` 发送：

```sh
# 切到「日本1」，UTF-8 十六进制为 \xe6\x97\xa5\xe6\x9c\xac1
printf '{"name":"\xe6\x97\xa5\xe6\x9c\xac1"}' > /tmp/body.json
wget -qO- --header='Content-Type: application/json' --body-file=/tmp/body.json \
  -X PUT http://127.0.0.1:9999/proxies/%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9
```

```sh
# 节点延迟测试，URL 中的中文需 percent-encode
wget -qO- 'http://127.0.0.1:9999/proxies/%E6%97%A5%E6%9C%AC1/delay?timeout=3000&url=http://www.gstatic.com/generate_204'
```

验证：切节点返回空 body（HTTP 204）；延迟测试返回 `{"delay":<毫秒数>}`。
失败判据：返回 `400` 说明节点名与实际不一致，用 3.3 结尾的 `proxies` 接口确认准确名称。

API 实时切换不写配置文件，重启 ShellCrash 后回到配置里的默认选择组。要固定节点，改 `yamls/config.yaml` 中对应 `proxy-groups` 的 `proxies` 顺序。

### 3.5 TUN 模式切换

R3G 原厂内核没有 tun 模块，需先安装：

```sh
# opkg update 慢或超时，可从阿里云镜像手动下载 kmod-tun 后本地安装
opkg install /tmp/kmod-tun_*.ipk
modprobe tun
```

验证：

```sh
ls -l /dev/net/tun
```

预期：设备节点存在。
失败判据：`No such file or directory` 说明 kmod-tun 版本与内核不符（19.07.2 对应 4.14.171-1），装错版本不会创建节点。

切换为 TUN 模式，在 `/etc/ShellCrash/configs/ShellCrash.cfg` 写入：

```
redir_mod=Tun模式
```

重启服务：

```sh
/etc/init.d/shellcrash restart
```

重启后生成的 tun 配置：

```yaml
tun:
  enable: true
  stack: system
  device: utun
  auto-route: false
  auto-detect-interface: false
```

路由由 ShellCrash 防火墙脚本管理：`fw_start.sh` 等待 utun 出现后执行 `ip route add default dev utun table 100`，配合 `ip rule fwmark 7894` 分流。mihomo 自身的 `auto-route` 保持 false。

验证：

```sh
ip route show table all | grep utun
netstat -tlnp | grep -E '7890|9999'
wget -qO- https://www.gstatic.com/generate_204
wget -qO- https://www.baidu.com
```

预期：第一条输出含 `default dev utun table 100`；第二条显示 7890（tun）与 9999（API）在监听；两条 wget 均返回 0 字节。
失败判据：`ip route` 无 utun 输出说明 fw_start.sh 超时未建表，等待 15 秒后重查；仍无则手动执行 `sh /etc/ShellCrash/starts/fw_start.sh`。

TUN 模式的两点限制：

- IPv6 受限：内核缺 `ip6table_nat`，重启时 ip6tables nat 报 `Table does not exist`。IPv4 不受影响，需要 IPv6 时补装 `kmod-ipt-nat6`。
- CPU 占用高于 Redir 模式。R3G 性能有限，日常代理建议切回 Redir 模式。

---

## 四、网络与无线规划

本文记录的是无线启用形态，用于终端直接连 R3G 上网。当前设备已转为关闭无线的串行级联网关形态，两套形态的配置不可混用，判别与拓扑见 `docs/串行级联网关组网与选路实录.md`。

无线启用形态的约定：

1. 上网 WiFi 走 radio1（5G，ch153）。
2. radio0（2.4G）与管理用途的 `wlan0`、`wlan0-1` 接口保持 `disabled='1'`。
3. 上级交换机网段 192.168.1.0/22，不改 WAN IP，WAN 保持 192.168.1.54 DHCP 自动获取。

管理入口：

| 用途 | 地址 |
| --- | --- |
| OpenWrt LuCI / SSH | 192.168.1.54（WAN） |
| ShellCrash API | 127.0.0.1:9999 |

验证无线状态：

```sh
wifi status
uci show wireless | grep -E 'disabled|ssid|channel'
```

预期：`wifi status` 返回 JSON，`up: true` 的接口只有 radio1 对应项；`disabled` 属性对 wlan0 系列为 `1`。
失败判据：radio0 状态为 up 说明有终端在走 2.4G，与规划不符。

---

## 五、排障速查

### 5.1 刷机与固件

- 刷 Breed 前确认原厂固件版本与 OpenWRTInvasion 的匹配关系，刷后回 Breed 验证 `xiaomi.r3g.bootfw=2` 是否写入。
- R3G 分高低配，高配 UBI 117MB 可直接刷；低配需先扩容，两类固件不可混用。
- Breed Web 直接刷 sysupgrade 报数据无效，改走 initramfs 过渡再刷正式包。
- 刷机前一律先跑 `sha256sum -c SHA256SUMS`，哈希不符的文件不要刷。

### 5.2 代理（ShellCrash）

- **hardfloat 内核 Illegal instruction**：换 `mihomo-mipsle-softfloat`。
- **gzip 压缩极慢或超时**：在电脑侧压好 gz 再 pscp 上传，不要在路由器上压。
- **opkg 锁死**：`/var/lock/opkg.lock` 被占用，kill 残留 opkg 进程后删除锁文件；`opkg update` 慢时从阿里云镜像直接 wget ipk 本地安装。
- **防火墙不生效**：`firewall_area` 缺失或 `ipv6_redir` 未定义导致 `fw_start.sh` 报 out of range、nftables 规则不加载。补 `firewall_area=1` 与 `ipv6_redir=OFF` 后执行 `sh /etc/ShellCrash/starts/fw_start.sh`。
- **DNS 死循环**：`nameserver` 或 `direct-nameserver` 指向 127.0.0.1，改为 223.5.5.5。
- **重启后规则丢失**：`afstart.sh` 异步等待 CrashCore 或 utun 超时。等 15 秒再查 `nft list table inet shellcrash`，兜底方案是在 `rc.local` 中延迟 30 秒重试 `fw_start.sh`。
- **.start_error 哨兵**：上次异常退出会阻止自启，执行 `rm -f /etc/ShellCrash/.start_error && /etc/init.d/shellcrash restart`。
- **订阅假节点**：`server` 为 `1` 或 `11` 的占位节点污染 `url-test`，在本机提取 YAML 时过滤掉。
- **CrashCore 日志不可见**：stdout 与 stderr 重定向到 `/dev/null`，排查只能靠 API（`nc 127.0.0.1 9999`）与抓包。

### 5.3 中文与编码

SSH/plink 传中文（节点名、`redir_mod` 的值）容易乱码，统一用 printf 十六进制转义：

| 文本 | 转义 |
| --- | --- |
| `模式` | `\xe6\xa8\xa1\xe5\xbc\x8f` |
| `日本1` | `\xe6\x97\xa5\xe6\x9c\xac1` |

URL 中出现中文时需 percent-encode，例如 `日本1` 编码为 `%E6%97%A5%E6%9C%AC1`。

### 5.4 常用命令

```sh
# SSH 与文件传输（电脑侧）
plink76.exe -ssh -batch -pw YOUR_ROOT_PASSWORD root@192.168.1.54
pscp76.exe -pw YOUR_ROOT_PASSWORD 本地文件 root@192.168.1.54:/tmp/

# 无线与网络服务
wifi reload && wifi up radio1
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart

# 代理状态
pidof CrashCore
nft list table inet shellcrash | grep -c chain
ip route show table all | grep utun
http_proxy=http://127.0.0.1:7890 wget -q -O - -T5 http://www.gstatic.com/generate_204
wget -q -O - http://127.0.0.1:9999/proxies
```

### 5.5 参考文档

- `docs/R3G_ShellCrash_故障排查手册.md`（ShellCrash 故障手册）
- 本文第三章 3.4（TUN 模式的启用条件与 mips 平台限制）
- `docs/R3G刷机常见问题指南.md`（刷机常见问题）
