# ShellCrash 路由器部署技术手册

> **版本**: v1.0  
> **日期**: 2026-07-08  
> **适用环境**: ShellCrash（CrashCore v1.19.17 / sing-box 内核）on OpenWrt/LEDE 路由器  
> **配置格式**: Clash Meta YAML 兼容

---

## 一、路由器基本信息

| 项目 | 值 |
|------|-----|
| ShellCrash 版本 | CrashCore v1.19.17（基于 sing-box） |
| 配置格式 | Clash Meta YAML 兼容 |
| 配置文件路径 | `/etc/ShellCrash/yamls/config.yaml` |
| 运行目录 | `/tmp/ShellCrash/` |
| 控制命令 | `/etc/init.d/shellcrash {restart\|stop\|start}` |
| API 端口 | `9999` |

---

## 二、部署流程 SOP

### Step 1: 获取订阅

```bash
wget -qO- "订阅URL" | base64 -d
```

### Step 2: 解析节点

1. 过滤掉 `ss://` 类型的公告/伪节点（详见 [问题4](#问题4ss-公告节点混入有效节点列表)）
2. 提取 `vless://` 节点
3. 解析时先剥离 URI fragment：`line.split('#', 1)[0]`，再提取参数（详见 [问题3](#问题3订阅解析short-id-被-uri-fragment-污染)）

### Step 3: 生成配置

- 使用 Clash Verge 兼容格式
- VLESS REALITY 节点必须使用 `network: http` + `http-opts`，**不要加 `flow: xtls-rprx-vision`**（详见 [问题5](#问题5vless-reality-节点全部-alivefalse核心问题network-类型错误)）
- `proxy-groups` 使用 `url-test`（interval: 300）
- `rules` 末尾使用 `MATCH,PROXY`

### Step 4: 部署配置文件

```bash
gzip 压缩 → SSH channel 上传到 /etc/ShellCrash/yamls/config.yaml
```

### Step 5: 更新订阅 URL

```bash
sed -i "s|^Url=.*|Url='订阅URL'|" /etc/ShellCrash/ShellCrash.cfg
```

### Step 6: 清理标记并重启

```bash
rm -f /etc/ShellCrash/.start_error && /etc/init.d/shellcrash restart
```

> 重启后等待 **5~10 秒**让 TUN 模式和 iptables 规则完全生效后再测试。

### Step 7: 验证

```bash
wget -qO- https://ip.sb
```

确认返回 **非中国 IP**，说明代理工作正常。

---

## 三、疑难问题与解决方案

### 问题1：Clash 开机自启失败（.start_error 标记文件）

**现象**：

路由器重启后 CrashCore 无法自动启动。`bfstart.sh` 启动脚本检测到 `/etc/ShellCrash/.start_error` 文件存在后直接退出，不再尝试拉起进程。

**根因**：

ShellCrash 的 `bfstart.sh` 启动逻辑中，若上一次启动异常退出，会留下 `.start_error` 哨兵文件。后续启动时会检查该文件，存在则跳过自启。

**解决方案**：

```bash
rm -f /etc/ShellCrash/.start_error && /etc/init.d/shellcrash restart
```

删除哨兵文件后立即重启 ShellCrash 服务。

---

### 问题2：配置文件校验失败——规则引用不存在的代理组

**现象**：

CrashCore 启动后立即退出。日志报错：规则引用了不存在的代理组「喵酥云」。

**根因**：

旧配置文件中 40+ 条 `rules` 规则引用 `「喵酥云」` 作为策略组，但 `proxy-groups` 中只定义了 `Proxy` 和 `GLOBAL`，导致 CrashCore 配置校验失败。

**解决方案**：

清理旧配置文件后重新生成部署，确保 `proxy-groups` 和 `rules` 中引用的代理组名称**完全一致**。

---

### 问题3：订阅解析——short-id 被 URI fragment 污染

**现象**：

解析 VLESS URI 时，`short-id` 字段被名称片段污染（如 `YOUR_SHORT_ID#美国1 精品`），导致 CrashCore 报错：

```
invalid REALITY short id
```

**根因**：

VLESS URI 标准格式为：

```
vless://uuid@server:port?params#节点名称
```

其中 `#` 后的 fragment 是节点名称（注释），不是 `sid` 参数值的一部分。如果解析脚本没有先剥离 fragment 就直接提取参数，`sid=YOUR_SHORT_ID#美国1 精品` 会作为一个整体被写入 `short-id`。

**解决方案**：

解析前先剥离 URI fragment：

```python
line = line.split('#', 1)[0]    # 剥离 #节点名称
```

然后再从 `?` 后的参数中提取各个字段。

---

### 问题4：SS 公告节点混入有效节点列表

**现象**：

订阅返回的 base64 节点列表中混入 `ss://` 类型的公告节点，例如：

- `ss://...` — 名称："节点失效先更新订阅"
- `ss://...` — 名称："更新订阅教程：example.com"

这些节点 `server:port` 为 `1:1`，完全不可用；但由于协议字段有效，常规解析器不会过滤它们。当它们被加入 `url-test` 代理组后，会污染延迟测试结果和自动选路。

**解决方案**：

在解析阶段过滤掉这些伪节点：

- 排除 `ss://` 类型且 `server`/`port` 为无效值的节点
- 只保留 `vless://` 类型的真实代理节点
- 或者将这类节点从 `url-test` 组的测试列表中排除

---

### 问题5：VLESS REALITY 节点全部 alive=false —— **核心问题：network 类型错误**

**现象**：

| 检查项 | 结果 |
|--------|------|
| API `/proxies` 状态 | 全部 10 个节点 `alive:false, delay:0` |
| TCP 连通性（`nc -zv`） | 所有代理服务器端口可达 |
| CrashCore outbound 连接 | `netstat` 无任何到代理服务器的连接 |
| `wget https://ip.sb` | 返回中国 IP，流量未走代理 |
| 同电脑 Clash Verge + 相同订阅 | 所有节点正常工作 |

**根因**：

路由器配置中 VLESS 节点错误使用了 `network: tcp` 并添加了 `flow: xtls-rprx-vision`，但该订阅的 VLESS REALITY 节点实际传输层是 **HTTP**（`network: http`），需要配合 `http-opts`（含 `headers.Host` 和 `path`）。

TCP 传输与 HTTP 传输的 TLS 握手方式**完全不同**：TCP 模式在 TCP 层之上直接做 REALITY TLS 协商，而 HTTP 模式需要先建立 HTTP/2 或 HTTP/1.1 传输通道再进行 TLS 协商。类型不匹配导致 REALITY 握手失败，sing-box 内核直接放弃连接。

**错误配置示例**：

```yaml
- name: 日本
  type: vless
  server: jp1.example.com
  port: 8800
  uuid: YOUR_UUID
  network: tcp                    # ❌ 错误！应为 http
  tls: true
  flow: xtls-rprx-vision          # ❌ 多余！Clash Verge 正常配置中无此字段
  servername: www.deepseek.com
  client-fingerprint: chrome
  reality-opts:
    public-key: YOUR_REALITY_PUBLIC_KEY
    short-id: YOUR_SHORT_ID
```

**正确配置**（与 Clash Verge 导出格式一致）：

```yaml
- name: 日本
  type: vless
  server: jp1.example.com
  port: 8800
  uuid: YOUR_UUID
  udp: true
  tls: true
  skip-cert-verify: false
  client-fingerprint: chrome
  servername: www.deepseek.com
  reality-opts:
    public-key: YOUR_REALITY_PUBLIC_KEY
    short-id: YOUR_SHORT_ID
  network: http                   # ✅ 正确：HTTP 传输
  http-opts:                      # ✅ 必须配合 http-opts
    headers:
      Host:
      - www.deepseek.com
      - www.deepseek.com
    path:
    - /
```

**排查技巧**：

1. **TCP 连通性先验**：先用 `nc -zv <server> <port>` 确认物理网络可达
2. **API 诊断**：查询 CrashCore API 获取节点实时状态：
   ```bash
   echo -e 'GET /proxies HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | nc 127.0.0.1 9999
   ```
3. **注意日志盲区**：CrashCore 的 stdout/stderr 被重定向到 `/dev/null`（fd 1 → /dev/null, fd 2 → /dev/null），debug 日志**不会**输出到 `ShellCrash.log`。排查时只能依赖 API 和网络抓包
4. **对比法**：当节点在 PC 端 Clash Verge 可用但路由器不可用时，**逐字段对比两边的 proxy 配置格式**，特别关注 `network`、transport options（`http-opts`/`grpc-opts` 等）、`flow` 等字段

---

### 问题6：ip.sb 返回中国 IP 但节点显示 alive

**注意**：

即使 API 显示 `alive:true`，ShellCrash 刚重启时 TUN 模式和 iptables 规则可能尚未完全生效。此时 `wget` 可能走直连而非代理，导致返回中国 IP。

**解决方案**：执行 `restart` 后等待 **5~10 秒**，确认 TUN 路由和 iptables 规则加载完毕后再测试。

---

## 四、常用诊断命令

```bash
# 检查 CrashCore 进程
ps | grep CrashCore

# 检查端口监听（7890=tun, 9999=API）
netstat -tlnp | grep -E '7890|9999'

# 检查 TUN 路由
ip route show table all | grep utun

# 删除启动错误标记
rm -f /etc/ShellCrash/.start_error

# 查询 API 获取代理组和节点状态
echo -e 'GET /proxies HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | nc 127.0.0.1 9999

# 检查 CrashCore 文件描述符（确认日志重定向情况）
ls -la /proc/$(pgrep CrashCore)/fd/

# 批量 TCP 连通性测试
for s in us1.example.com us2.example.com jp1.example.com us3.example.com hk1.example.com; do
    nc -zv -w3 $s 8886 2>&1
done

# 强制重载配置
/etc/init.d/shellcrash restart

# 查看 CrashCore 配置
cat /etc/ShellCrash/yamls/config.yaml
```

---

## 五、关键教训总结

| # | 教训 | 影响范围 |
|---|------|----------|
| 1 | **不要假设 transport 类型**——同一订阅中 VLESS 可能走 TCP、HTTP、gRPC 等不同传输，必须根据实际订阅解析结果配置，而非套用默认值 | 节点全部不可用 |
| 2 | **对比 PC 端可用配置**——当路由器端异常而 PC 端正常时，最有效的排查手段是逐字段对比两边的 proxy 配置格式 | 问题5的最终突破口 |
| 3 | **CrashCore 日志不可见**——stdout/stderr 被重定向到 `/dev/null`，debug 日志不会写入日志文件，排查依赖 API 和网络抓包 | 增加排查难度 |
| 4 | **URI 解析注意 fragment**——`#` 后的节点名称会污染参数值，必须在提取参数前剥离 | short-id 污染导致节点解析失败 |
| 5 | **过滤伪节点**——订阅中常混入公告/推广节点，server:port 为无效值，必须过滤 | 影响 url-test 自动选路 |
| 6 | **哨兵文件陷阱**——ShellCrash 的 `.start_error` 机制会在异常退出后阻止后续自启 | 开机自启失败 |
| 7 | **TUN 生效需时间**——restart 后 iptables/TUN 规则有加载延迟，立即测试可能误判 | 误判代理未生效 |
