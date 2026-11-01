# R3G ShellCrash 故障排查手册

> 记录时间：2026-08-07  
> 触发背景：更换 ZTE 主路由后 R3G 重启，ShellClash 透明代理失效，LAN 客户端无法访问外网。

---

## 环境概览

| 设备 | 角色 | IP / 说明 |
|------|------|-----------|
| ZTE 主路由 | 上网网关 | 192.168.5.1，不可改动 |
| 小米 R3G | OpenWrt 旁路由 | 管理 IP 192.168.1.1，WAN 接 ZTE LAN 口，蓝口=WAN，黄口=LAN |
| ShellClash | 代理客户端 | TUN 模式，nftables 透明代理，CrashCore (meta v1.19.17) |

---

## 问题一：外网不通（最核心）

### 现象

- R3G 自身通过 `http_proxy=http://127.0.0.1:7890` 可访问 Google
- DNS 解析 google.com 返回 28.x.x.x（fake-ip），说明 Clash DNS 正常
- LAN 客户端无法访问外网

### 根本原因

**`firewall_area` 未配置**。`/etc/ShellCrash/configs/ShellCrash.cfg` 中缺少 `firewall_area=1`，导致 `fw_start.sh` 在创建 nftables 透明代理规则时失败。

`fw_start.sh` 脚本中有这样一行：

```bash
[ "$ipv6_redir" = "ON" -a "$firewall_area" -le 3 ]
```

当 `firewall_area` 为空字符串时，ash 做算术比较 `"" -le 3` 直接报 `sh: out of range`，后续 nftables 规则创建被跳过。nautilus 执行 `nft list table inet shellcrash` 返回空表。

同时 `ipv6_redir` 也未定义，即使 `firewall_area` 存在也会因为 `ipv6_redir` 为空触发同样的错误。

### 解决方法

**Step 1**：编辑 `/etc/ShellCrash/configs/ShellCrash.cfg`，添加以下两行：

```bash
firewall_area=1
ipv6_redir=OFF
```

`firewall_area` 取值说明：
- `1` = 代理本机 + 局域网（推荐）
- `2` = 仅代理本机
- `3` = 代理本机 + 局域网 + 虚拟机
- `4` = 仅 DNS 代理
- `5` = 主旁转发模式

**Step 2**：手动加载防火墙规则：

```bash
export CRASHDIR=/etc/ShellCrash
sh /etc/ShellCrash/starts/fw_start.sh
```

**Step 3**：验证：

```bash
nft list table inet shellcrash          # 应有 3 个 chain
nft list chain inet shellcrash prerouting_dns | grep redirect  # DNS 劫持
ip route show table 100                 # default dev utun
```

---

## 问题二：DNS 死循环

### 现象

- nslookup 通过 Clash DNS (127.0.0.1:1053) 解析 google.com 超时或返回空
- Clash 日志中 DNS 解析反复失败

### 根本原因

`/etc/ShellCrash/config.yaml` 的 DNS 配置中，`nameserver` 和 `direct-nameserver` 都指向了 `127.0.0.1`（即 Clash 自身），形成自引用死循环。

Clash 收到 DNS 请求后，把请求发给 127.0.0.1，结果又回到了自己，无限循环直至超时。

```yaml
dns:
  nameserver:
    - 127.0.0.1          # ❌ 死循环
  direct-nameserver:
    - 127.0.0.1          # ❌ 死循环
```

### 解决方法

将上游 DNS 改为真实公共 DNS：

```bash
sed -i 's/nameserver: \[ 127.0.0.1 \]/nameserver: [ 223.5.5.5 ]/' /etc/ShellCrash/config.yaml
sed -i 's/direct-nameserver: \[ 127.0.0.1 \]/direct-nameserver: [ 223.5.5.5 ]/' /etc/ShellCrash/config.yaml
```

修改后 DNS 段应为：

```yaml
dns:
  enable: true
  listen: :1053
  use-hosts: true
  ipv6: true
  default-nameserver:
    - 223.5.5.5
    - 2400:3200::1
  direct-nameserver:
    - 223.5.5.5
  nameserver:
    - 223.5.5.5
  enhanced-mode: fake-ip
  fake-ip-range: 28.0.0.0/8
```

然后重载 Clash：

```bash
/etc/init.d/shellcrash restart
```

> **注意**：init 脚本名是全小写 `shellcrash`，`ShellCrash` 不存在。

---

## 问题三：wget 订阅更新失败

### 现象

`/etc/init.d/shellcrash restart` 时输出大量 `wget: unrecognized option: header=Authorization: Bearer`。

### 原因

ShellCrash 启动时会尝试用 wget 拉取订阅更新，但 OpenWrt 内置的 BusyBox wget 不支持 `--header` 参数。此错误**不影响代理功能**，仅导致节点列表无法自动更新。

### 解决方法

安装完整版 wget 或 curl：

```bash
opkg update && opkg install wget-ssl
# 或
opkg install curl
```

如不关心自动更新，可忽略此错误。手动更新订阅可通过 ShellCrash 菜单（`crash` 命令）进行。

---

## 问题四：防火墙规则重启后丢失

### 现象

R3G 重启后 `nft list table inet shellcrash` 返回空，LAN 客户端无法上网。

### 原因

`/etc/init.d/shellcrash` 的 `start_service()` 流程为：

```
bfstart.sh → CrashCore (procd) → afstart.sh (& 后台) → fw_start.sh
```

`afstart.sh` 在后台异步执行，其中 `fw_start.sh` 需要等待：
1. CrashCore 完全启动（通过 `/tmp/ShellCrash.log` 判断，最多等 20 秒）
2. utun 接口出现（最多等 29 秒）

如果等待超时或脚本中途因变量缺失报错（如问题一的 `out of range`），规则就不会加载。

### 解决方法

**方法 A（推荐）**：修复问题一后，开机自启即可正常。修复配置后执行：

```bash
/etc/init.d/shellcrash restart
sleep 15  # 等待 afstart.sh 后台完成
nft list table inet shellcrash  # 确认规则已加载
```

**方法 B（兜底）**：若重启后规则仍未加载，手动执行：

```bash
export CRASHDIR=/etc/ShellCrash
sh /etc/ShellCrash/starts/fw_start.sh
```

**方法 C（治本）**：在 `/etc/rc.local` 的 `exit 0` 之前添加延迟重试：

```bash
# 开机后 30 秒重试 ShellCrash 防火墙
(sleep 30 && export CRASHDIR=/etc/ShellCrash && sh /etc/ShellCrash/starts/fw_start.sh) &
```

---

## 快速验证清单

重启 R3G 后，SSH 登录执行以下检查：

```bash
# 1. CrashCore 是否运行
pidof CrashCore

# 2. nftables 规则是否加载（应有 3 个 chain）
nft list table inet shellcrash | grep -c chain

# 3. DNS 劫持是否生效（应有 redirect to :1053）
nft list chain inet shellcrash prerouting_dns | grep redirect

# 4. 策略路由是否就绪
ip route show table 100

# 5. 代理是否正常工作
http_proxy=http://127.0.0.1:7890 wget -q -O - -T5 http://www.gstatic.com/generate_204

# 6. 节点列表是否纯净（应无 server:1/11 占位节点）
wget -q -O - http://127.0.0.1:9999/proxies | grep -c '"port":1'

# 7. DNS fake-ip 是否正常（应返回 28.x.x.x）
nslookup www.google.com 127.0.0.1 -port=1053
```

---

## 问题五：前面板蓝灯不亮

### 现象

R3G 前面板蓝色指示灯不亮。

### 排查过程

初判为"硬件无蓝灯"，后经 GPIO 调试信息纠正：

```
gpio-488 (blue:status) out lo ACTIVE LOW
```

`blue:status` 的 `trigger=default-on, brightness=1`，GPIO 输出 lo（ACTIVE LOW 下 lo=亮），**软件层面一切正常，蓝灯确实存在于硬件中**。

逐一测试结果：

| LED | GPIO | 控制正常 | 前面板效果 |
|-----|------|---------|-----------|
| red:status | gpio-486 | 是 | 鲜红色 |
| yellow:status | gpio-490 | 是 | 故障黄 |
| blue:status | gpio-488 | 是 | **不亮** |

### 结论

疑似硬件故障——灯珠烧毁或排线松动（搬动设备时可能导致）。不影响功能，可忽略。

---

## 问题六：订阅节点混入假节点导致代理不可用

### 现象

- PC 端能上网但无法科学上网（国内网站正常，国外不通）
- `ps | grep CrashCore` 确认 CrashCore 进程正在运行
- `nft list table inet shellcrash` 防火墙规则完整
- CrashCore API 返回的节点列表中大量显示 `server:1` / `server:11` / `port:1` / `port:11` 等占位节点

### 根本原因

ShellCrash 通过 subconverter 转换订阅时，原始订阅链接中前 6 个节点为**占位假节点**（`server:1/11, port:1/11`），它们是服务商的公告/教程节点，并非真实代理节点。subconverter 合并处理后，生成的 `config.yaml` 中 proxies 列表几乎全被占位节点占据，仅有极个别真实节点被引用。

真实节点（如日本4/新加坡2/美国2）虽然存在于订阅原始数据中，但在合并后的 `config.yaml` 里未被正确保留，导致 `proxy-groups` 中的 `proxies` 引用了一堆无效占位节点。

### 排查过程

1. **确认进程运行**：
   ```bash
   pidof CrashCore
   # 输出进程 PID → CrashCore 正常运行
   ```

2. **确认防火墙规则正常**：
   ```bash
   nft list table inet shellcrash
   # 三链（input / prerouting_dns / prerouting）规则完整 → 非防火墙问题
   ```

3. **检查 CrashCore API 节点列表**：
   ```bash
   wget -q -O - http://127.0.0.1:9999/proxies
   ```
   返回大量占位节点：
   
   | 节点名 | server | port | 类型 |
   |--------|--------|------|------|
   | 节点失效先更新订阅 | 11 | 11 | 假 |
   | 更新订阅教程：example.com | 1 | 1 | 假 |
   | 所有节点为中国移动优化 | 1 | 1 | 假 |
   | 联通 电信部分网络优化 | 1 | 1 | 假 |
   | 官网防失联页面：example.com | 1 | 1 | 假 |
   | 年付优惠码：11miaosu | 1 | 1 | 假 |

4. **从本机直接下载订阅原始数据核实**：
   在本机（需代理环境）通过 Python 下载订阅链接，base64 解码后确认：订阅源中包含 **8 个真实节点**（日本4个 / 新加坡2个 / 美国2个）混在 6 个占位节点中，共 14 个节点。

### 解决方法

#### 方法一（推荐）：本机生成完整 Clash 配置后替换

1. 在本机（有代理环境）下载订阅链接，base64 解码得到节点列表：
   ```python
   import requests, base64
   resp = requests.get('你的订阅URL')
   raw = base64.b64decode(resp.text).decode()
   links = raw.splitlines()
   # 过滤掉 server 为 1 或 11 的占位节点
   ```

2. 用 Python 脚本将真实节点（vless:// / ss:// 等）转为 Clash YAML 格式，生成完整的 `config.yaml`（包含 proxies、proxy-groups、rules 等）。

3. 上传到 R3G 并替换：
   ```bash
   # SCP 上传
   scp config.yaml root@192.168.1.1:/etc/ShellCrash/yamls/config.yaml
   ```

   > **关键**：必须替换 `/etc/ShellCrash/yamls/config.yaml`，而非 `/tmp/ShellCrash/config.yaml`。
   > 原因：`bfstart.sh` 启动时会检测 `yamls/config.yaml` 是否存在——若存在则**跳过订阅下载，直接使用该文件**。若替换 `/tmp` 下的文件，重启后会被覆盖。

4. 重启 CrashCore：
   ```bash
   kill $(pidof CrashCore)
   /etc/ShellCrash/start.sh start
   ```

5. 手动加载防火墙（若启动脚本未自动加载）：
   ```bash
   export CRASHDIR=/etc/ShellCrash
   . /etc/ShellCrash/libs/get_config.sh
   bash /etc/ShellCrash/starts/fw_start.sh
   ```
   
   确认 `nft list table inet shellcrash` 三链规则完整。

#### 方法二：在 R3G 上手动编辑

SSH 登录 R3G，直接编辑 `/etc/ShellCrash/yamls/config.yaml`，删除 `proxies` 中的占位节点，保留真实节点并在 `proxy-groups` 中正确引用。操作繁琐且易出错，不推荐。

### 验证方法

```bash
# 1. 查看节点列表，确认无占位节点
wget -q -O - http://127.0.0.1:9999/proxies

# 2. 查看「自动选择」组，应选中一个真实节点
wget -q -O - http://127.0.0.1:9999/proxies/%E8%87%AA%E5%8A%A8%E9%80%89%E6%8B%A9
# 或直接访问 Dashboard: http://192.168.1.1:9999/ui

# 3. DNS fake-ip 验证
nslookup www.google.com 127.0.0.1:1053
# 应返回 28.x.x.x（fake-ip 地址段）

# 4. 代理连通性测试
http_proxy=http://127.0.0.1:7890 wget -q -O - -T5 http://www.gstatic.com/generate_204
# 应返回 204 状态码或成功下载
```

---

## 关键文件路径汇总

| 文件 | 用途 |
|------|------|
| `/etc/ShellCrash/configs/ShellCrash.cfg` | ShellCrash 主配置（firewall_area, redir_mod 等） |
| `/etc/ShellCrash/config.yaml` | Clash 核心配置（DNS, TUN, 代理端口等） |
| `/etc/ShellCrash/starts/fw_start.sh` | 防火墙规则加载入口 |
| `/etc/ShellCrash/starts/fw_nftables.sh` | nftables 规则生成脚本 |
| `/etc/init.d/shellcrash` | 系统服务启动脚本 |
| `/etc/rc.d/S99shellcrash` | 开机自启符号链接 |

---

## zsh 重装 ShellClash 时的注意事项

如需重装 ShellClash，务必在重装后立即修改以下两项：

1. `configs/ShellCrash.cfg`：添加 `firewall_area=1` 和 `ipv6_redir=OFF`
2. `config.yaml`：将 `nameserver` 和 `direct-nameserver` 改为真实 DNS（如 `223.5.5.5`）

否则问题会复现。
*（内容由AI生成，仅供参考）*
