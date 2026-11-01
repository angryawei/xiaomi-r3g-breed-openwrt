本目录暂无独立脚本文件。

说明：全盘检索未发现 R3G 刷机用的独立 .sh / .py / .ps1 / .bat 脚本。
相关命令均以代码块形式内嵌于 ../docs 下的文档中，主要包括：

1. Breed 命令行内存启动 initramfs（见 docs\刷机说明.txt、docs\部署与排障手册.md）
   wget http://192.168.1.10/openwrt-r3g-initramfs.bin
   flash bank 0x80001000 0x80000000 0x<文件大小>
   boot linux 0x80001000

2. OpenWrt 网络一键配置（见 docs\标准设置手册.md）
   uci set network.lan.proto='static' 等 UCI 命令集

3. dnsmasq ujail 沙箱修复（见 docs\dnsmasq-init-修复说明.txt）
   sed -i 's/^\tprocd_add_jail dnsmasq ubus log$/\t#procd_add_jail dnsmasq ubus log/' /etc/init.d/dnsmasq

4. ShellCrash 订阅获取与解析（见 docs\ShellCrash部署指南.md）
   wget -qO- "订阅URL" | base64 -d

如需可执行脚本，可从上述文档抽取后放入本目录。
