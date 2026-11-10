本目录脚本索引
================

所有脚本均为只读或可安全重跑，不会在未提示的情况下覆盖已有文件。
按执行顺序编号，刷机流程中建议依次使用。


00-backup-nand.sh
-----------------
刷机前在 OpenWrt 设备上做 NAND 全量 / 分区备份。
输出到 /tmp 或外挂 U 盘，务必先拷出再刷机。
运行环境：OpenWrt（BusyBox sh）。


01-fetch-firmware.ps1
----------------------
Windows 端按 engineering/firmware/SOURCES.md 下载全部固件，下载后强制比对 SHA256，
不匹配立即中止并报错，绝不留下错误文件。
参数：
  -IncludeOptional   连同可选的 24.10.4 initramfs 一起下载
运行环境：Windows PowerShell 5.1 及以上。


02-split-sysupgrade.py
----------------------
把官方 sysupgrade 镜像拆成 kernel1 / rootfs0 两部分，供需要手动写分区的场景使用。
运行环境：Python 3.8+。


03-breed-memboot.txt
--------------------
不是脚本，是 Breed 控制台下的内存启动命令序列（wget / flash bank / boot mem），
按注释逐行敲入即可。含两次实测的命令与地址说明。


03-verify-firmware.ps1
----------------------
Windows 端按 engineering/firmware/SHA256SUMS 校验本地固件完整性。
不联网、不下载、不改名、不删文件，只比哈希。
参数：
  -Dir <路径>        固件所在目录，默认本脚本同级的 ../firmware
  -SumsFile <路径>   校验清单，默认 <Dir>/SHA256SUMS
  -AllowMissing      缺失的文件只警告，不判为失败（手头只有部分文件时用）
退出码：0 全部通过 / 1 存在缺失或哈希不符 / 2 环境或清单错误。
运行环境：Windows PowerShell 5.1 及以上。
用法（在仓库根目录）：
  powershell -ExecutionPolicy Bypass -File .\engineering\scripts\03-verify-firmware.ps1


03-verify-firmware.sh
---------------------
同上，Linux / macOS / OpenWrt 版本，POSIX sh 编写，兼容 BusyBox，可直接在路由器上跑。
参数：-d 目录 / -s 清单 / -m 放行缺失项 / -h 帮助。退出码含义与 ps1 版一致。
用法：
  chmod +x engineering/scripts/03-verify-firmware.sh
  ./engineering/scripts/03-verify-firmware.sh


04-check-upstream.py
--------------------
巡检 SOURCES.md 中登记的官方上游地址：是否仍可达、体积是否一致、内容是否被替换。
这是给「上游下架老版本」和「同名文件被静默替换」两种情况用的，不检查本地文件。
参数：
  --mode head        只比 Content-Length，快（默认）
  --mode deep        下载并计算 SHA256，严格但慢
  --only all|required|optional   限定检查范围
  --report <文件>    额外输出 Markdown 报告
  --timeout <秒>     单请求超时，默认 120
退出码：0 全部正常 / 1 存在异常 / 2 清单解析失败。
运行环境：Python 3.8+，仅用标准库。
用法：
  python engineering/scripts/04-check-upstream.py
  python engineering/scripts/04-check-upstream.py --mode deep

该脚本由 .github/workflows/watch-upstream-firmware.yml 每周一自动运行，
异常时在仓库内开 issue 告警，恢复正常后自动关闭。
