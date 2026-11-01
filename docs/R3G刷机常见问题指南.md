# 小米 R3G 刷机常见问题指南

> 适用场景：原厂固件刷 Breed → 内存启动 initramfs → LuCI 刷写 OpenWrt 23.05.6
> 整理自实际刷机全过程踩坑记录，按出现顺序排列。

---

## 1. U 盘法刷机被封堵

**现象**：小米 R3G 原厂固件 2.28.24 不再支持 U 盘自动刷机（放入 factory.bin 后不触发升级）。

**原因**：小米后期固件封堵了 U 盘刷机入口。

**解决**：改用 OpenWRTInvasion 漏洞（CVE-2019-18370 系列）远程植入后门刷入 Breed，无需拆机、无需 U 盘。

---

## 2. OpenWRTInvasion 被杀毒软件拦截

**现象**：运行 OpenWRTInvasion 时 Windows Defender 报毒/隔离脚本。

**原因**：利用脚本涉及漏洞利用载荷，被杀软特征库识别。

**解决**：将 OpenWRTInvasion 所在目录加入 Defender 排除项，或临时关闭实时防护，刷完再恢复。

---

## 3. Breed Web 直刷 OpenWrt 官方镜像失败

**现象**（三条报错，此路不通）：

- 刷 `initramfs` → 报 `[kernel1] 数据太大`
- 刷 `sysupgrade` → 报 `[rootfs0] 数据预处理失败`
- 刷编程器固件 → 报 `数据无效`

**原因**：Breed（r1416）对官方 OpenWrt 镜像的格式与大小存在限制，UBI 布局与 Breed 预期不兼容。

**解决**：**不要走 Breed Web 直刷**，必须走「Telnet 内存启动 initramfs → LuCI 上传 sysupgrade」流程。

---

## 4. Breed Telnet 连接问题

**现象**：
- Telnet 连接不稳定，经常连不上或中途断开；
- 输入命令只有回显不执行。

**原因**：
- Breed 控制台对连接较敏感，需多次重试；
- 换行符必须是 CRLF（`\r\n`），仅用 `\n` 不会触发执行。

**解决**：
- 使用 raw socket + CRLF 换行，连不上就重试（实测最多约 8 次成功）；
- Web 管理页与 Telnet 控制台同一时间只能使用一个会话，互斥。

---

## 5. wget 下载报 Connection aborted

**现象**：Breed 内 `wget http://电脑IP:端口/xxx.bin` 下载失败，报连接被中断。

**原因**：`python -m http.server`（SimpleHTTP 0.6）返回 HTTP/1.0 响应，Breed 的 wget 不兼容。

**解决**：使用自定义 HTTP/1.1 + `Connection: close` 的服务器（端口 8001）提供 initramfs 文件。

---

## 6. wget 下载地址与 uImage 加载地址重叠

**现象**：`boot mem 0x80001000` 后启动卡死 / 崩溃，或下载后的内存校验不过。

**原因**：initramfs 下载到 `0x80001000` 与后续内核解压/加载地址重叠；且部分 Breed 版本 wget 会忽略传入的内存地址参数。

**解决**：
- 下载到安全地址 `0x81000000`；
- 下载后用 `mem read 0x81000000 16` 校验魔数 `0x27051956`（uImage 头），确认下载成功再启动。

---

## 7. flash bank 命令报 Specified flash bank does not exist

**现象**：执行 `flash bank 0x80001000 0x80000000 <大小>` 报指定 flash bank 不存在。

**原因**：该写法本身多余，内存启动不需要经过 flash bank。

**解决**：跳过此步骤，直接 `boot mem`。

---

## 8. boot linux 卡死，必须用 boot mem

**现象**：`boot linux 0x81000000` 后 ping 不通（TTL expired in transit），启动失败。

**原因**：`boot linux` 直接跳到 uImage 头地址执行，而 initramfs 不是完整可执行镜像，导致崩溃。

**解决**：正确命令是 **`boot mem 0x81000000`**（解析 uImage 头引导），等待约 30-75 秒后 `ping 192.168.1.1` 通即可进入临时 OpenWrt。

---

## 9. 临时 OpenWrt（initramfs）的 LuCI ACL 限制

**现象**：SSH/终端里执行部分命令被拒，如 `ubus call system file_exec` 返回错误 6、`uci commit` 被拒。

**原因**：initramfs 恢复模式默认禁止非 root 会话直接调用 file.exec / uci.commit 等敏感接口。

**解决**：
- 不要依赖 SSH 侧执行刷写类命令；
- 改走 LuCI 界面手动刷写：`/cgi-bin/luci/admin/system/flash` 上传 `sysupgrade.bin`（CBI 表单走服务端，不受 ACL 限制）。
- 注意：`system.reboot` 是可用的，**切勿误触发**——重启会丢失内存系统。

---

## 10. 误触发 reboot 后回到原厂系统（不是砖）

**现象**：在 initramfs 里执行了 `reboot`，之后访问 `192.168.1.1` 不通，访问 `192.168.31.1` 却是小米原厂界面。

**原因**：内存系统重启即丢失，Breed autoboot 自动启动了 NAND 上的原厂固件。

**结论**：这是正常回退，**不是变砖**，无需惊慌。

**解决**：断电后按住 Reset 上电重进 Breed，重新走内存启动流程即可。

---

## 11. 如何重新进入 Breed

**方法**：路由器断电 → 按住 Reset（复位键）不松手 → 上电 → 等指示灯快闪后松开 → 浏览器访问 `192.168.1.1` 进入 Breed Web，或 Telnet 进控制台。

**注意**：电脑网卡需配置静态/副 IP `192.168.1.100/24`，才能与 Breed 同一网段通信。

---

## 12. 刷写成功后的验证

**现象**：LuCI 上传 `sysupgrade.bin` 完成后重新进入界面，不确定是否真正写入 NAND。

**验证方法**：
- `ping 192.168.1.1` 通且 TTL=64；
- SSH 执行 `ubus system board`，返回 `rootfs_type=squashfs` 即表示已从 NAND 正式启动（若为 `initramfs` 则是内存系统，未持久化）。

---

## 附：关键参数速查

| 项目 | 值 |
|------|-----|
| Breed 控制台地址 | 192.168.1.1:23（Telnet） |
| Breed Web 地址 | http://192.168.1.1 |
| 电脑副 IP | 192.168.1.100/24 |
| uImage 魔数 | 0x27051956 |
| 下载安全地址 | 0x81000000 |
| 正确启动命令 | `boot mem 0x81000000` |
| HTTP 服务器 | 自定义 HTTP/1.1 + Connection: close，端口 8001 |
| LuCI 刷写地址 | /cgi-bin/luci/admin/system/flash |
| 验证命令 | `ubus system board` → rootfs_type=squashfs |
| 刷写期间 | 切勿断电 |
*（内容由AI生成，仅供参考）*
