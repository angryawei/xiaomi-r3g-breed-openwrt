#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02-split-sysupgrade.py —— 把 OpenWrt sysupgrade 固件拆成 kernel1 / rootfs0 两个文件

为什么需要拆：
    Breed Web 界面的「固件」上传框只能放**单一份**固件；但有些场景（底包太小、
    只想单独刷内核、或 sysupgrade 整包被 Breed 判定格式不对）需要把内核与
    根文件系统分开写。OpenWrt sysupgrade 的物理布局是固定的：

        0x0000 .. 0x07FF   预留（u-boot 环境 / 对齐填充）
        0x0800 ..          uImage 内核（64 字节头 + 压缩内核数据）
        其后 4 字节对齐      SquashFS 根文件系统（魔数 'hsqs'）
        文件末尾            sysupgrade 元数据（通常 0x100 字节，含版本/板名）

    本脚本按上述结构定位，输出：
        kernel1.bin  = 0x800 .. squashfs 起始处
        rootfs0.bin  = squashfs 起始 .. squashfs 自身声明的长度（bytes_used）

用法：
    python 02-split-sysupgrade.py openwrt-23.05.6-...-squashfs-sysupgrade.bin
    python 02-split-sysupgrade.py 固件.bin --outdir ./split --prefix R3G-2305
    python 02-split-sysupgrade.py 固件.bin --check          # 只分析不写文件
    python 02-split-sysupgrade.py 固件.bin --pad 0x10000    # 输出补零到 64KB 对齐

退出码：
    0 成功；1 解析失败（不是合法 sysupgrade 镜像）；2 参数/文件错误
"""

import argparse
import os
import struct
import sys

UIMAGE_MAGIC = b"\x27\x05\x19\x56"   # uImage 大端魔数
SQUASHFS_MAGIC = b"hsqs"             # SquashFS 小端魔数
SQUASHFS_MAGIC_BE = b"sqsh"          # SquashFS 大端魔数（少见，兼容一下）
UIMAGE_OFFSET = 0x800                # ramips 平台约定：uImage 头在 0x800
UIMAGE_HDR_LEN = 64
SEARCH_LIMIT = 0x400000              # 找魔数时最多向后扫 4MB，防止死循环


def die(msg, code=1):
    print(f"[错误] {msg}", file=sys.stderr)
    sys.exit(code)


def find_uimage(data):
    """定位 uImage 头，优先按标准 0x800，找不到再全段搜索。"""
    if len(data) >= UIMAGE_OFFSET + 4 and data[UIMAGE_OFFSET:UIMAGE_OFFSET + 4] == UIMAGE_MAGIC:
        return UIMAGE_OFFSET

    limit = min(len(data) - 4, SEARCH_LIMIT)
    for off in range(0, limit, 4):
        if data[off:off + 4] == UIMAGE_MAGIC:
            return off
    return -1


def find_squashfs(data, start):
    """从 start 起找 SquashFS 魔数。

    要点：内核长度不一定是 4 的倍数，必须先把起点向上对齐到 4 字节，
    否则步进会跳过真正的魔数位置（实测 19.07.2 / 24.10.4 就踩这个坑）。
    对齐后仍找不到，再退回逐字节扫描，保证不漏。
    """
    aligned = (start + 3) & ~3
    limit = min(len(data) - 4, aligned + SEARCH_LIMIT)
    for off in range(aligned, limit, 4):
        if data[off:off + 4] == SQUASHFS_MAGIC:
            return off, "小端(LE)"
    for off in range(aligned, limit, 4):
        if data[off:off + 4] == SQUASHFS_MAGIC_BE:
            return off, "大端(BE)"
    # 兜底：逐字节
    off = data.find(SQUASHFS_MAGIC, start, limit + 4)
    if off >= 0:
        return off, "小端(LE)-非对齐"
    off = data.find(SQUASHFS_MAGIC_BE, start, limit + 4)
    if off >= 0:
        return off, "大端(BE)-非对齐"
    return -1, None


def parse_args():
    ap = argparse.ArgumentParser(
        description="拆分 OpenWrt sysupgrade 固件为 kernel1.bin / rootfs0.bin",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("image", help="sysupgrade 固件路径（*squashfs-sysupgrade.bin）")
    ap.add_argument("--outdir", default=None, help="输出目录，默认与固件同目录下的 split\\")
    ap.add_argument("--prefix", default=None, help="输出文件名前缀，默认取固件名（截断）")
    ap.add_argument("--check", action="store_true", help="只分析与校验，不写文件")
    ap.add_argument("--pad", default=None,
                    help="把输出文件补零到指定字节对齐，如 0x10000（64KB）")
    return ap.parse_args()


def main():
    args = parse_args()

    if not os.path.isfile(args.image):
        die(f"文件不存在：{args.image}", 2)

    size = os.path.getsize(args.image)
    if size < 0x1000:
        die(f"文件太小（{size} 字节），不是固件。", 1)

    with open(args.image, "rb") as f:
        data = f.read()

    print("=" * 70)
    print(f"镜像：{os.path.basename(args.image)}")
    print(f"大小：{size:,} 字节（{size / 1048576:.2f} MB）")

    # ---- 1. 定位 uImage ----
    uoff = find_uimage(data)
    if uoff < 0:
        die("未找到 uImage 魔数 0x27051956。\n"
            "       可能原因：① 这不是 sysupgrade 而是 initramfs/整片镜像；"
            "② 文件下载不完整。\n"
            "       请核对 SHA256（见 SHA256SUMS），并确认文件名含 squashfs-sysupgrade。")
    if uoff != UIMAGE_OFFSET:
        print(f"[警告] uImage 头不在标准 0x800，而在 0x{uoff:X}（非 ramips 常规布局，谨慎使用）")
    print(f"[1/4] uImage 头位置：0x{uoff:X}")

    # ---- 2. 解析 uImage 头 ----
    hdr = data[uoff:uoff + UIMAGE_HDR_LEN]
    if len(hdr) < UIMAGE_HDR_LEN:
        die("uImage 头被截断，文件不完整。")

    (magic, hcrc, utime, ksize,
     load_addr, entry, dcrc, os_id, arch, itype, comp) = struct.unpack(">IIIIIIIBBBB", hdr[:32])
    img_name = hdr[32:64].split(b"\x00")[0].decode("ascii", "replace")

    if ksize == 0 or uoff + UIMAGE_HDR_LEN + ksize > len(data):
        die(f"uImage 头声明的内核长度异常（{ksize} 字节），与文件大小 {len(data)} 不匹配。")

    kernel_payload_end = uoff + UIMAGE_HDR_LEN + ksize
    print(f"[2/4] 内核数据：{ksize:,} 字节，头部标注名称 “{img_name}”，"
          f"加载地址 0x{load_addr:08X}")
    print(f"      内核数据结束于：0x{kernel_payload_end:X}")

    # ---- 3. 定位 SquashFS ----
    sqoff, endian = find_squashfs(data, kernel_payload_end)
    if sqoff < 0:
        die("内核数据之后未找到 SquashFS 魔数 hsqs。\n"
            "       可能原因：① 该固件不是 squashfs 类型（如 ext4/jffs2 版）；"
            "② 内核长度字段被改写；③ 文件损坏。")

    if sqoff < kernel_payload_end:
        print(f"[警告] SquashFS 起点 0x{sqoff:X} 早于内核数据结束位置，布局异常。")

    pad = sqoff - kernel_payload_end
    print(f"[3/4] SquashFS 起点：0x{sqoff:X}（{endian}），内核与根文件系统间隔 {pad} 字节填充")

    # ---- SquashFS 超级块：bytes_used 在偏移 40，8 字节 LE ----
    sb = data[sqoff:sqoff + 96]
    if len(sb) < 96:
        die("SquashFS 超级块不完整，文件被截断。")
    block_size = struct.unpack("<I", sb[12:16])[0]
    s_major, s_minor = struct.unpack("<HH", sb[28:32])
    bytes_used = struct.unpack("<Q", sb[40:48])[0]

    if bytes_used == 0 or sqoff + bytes_used > len(data):
        die(f"SquashFS 声明的长度异常（bytes_used={bytes_used}），与文件大小不匹配。\n"
            "       文件可能下载不完整，请重新下载并校验 SHA256。")

    fs_end = sqoff + bytes_used
    tail_len = len(data) - fs_end
    print(f"      SquashFS 版本 {s_major}.{s_minor}，块大小 {block_size:,} 字节，"
          f"实际占用 {bytes_used:,} 字节")
    print(f"      根文件系统结束于：0x{fs_end:X}，尾部元数据 {tail_len} 字节")

    # 尾部 0x100 常见为 sysupgrade 元数据，打印可见字符串便于核对机型
    if 0 < tail_len <= 0x400:
        tail = data[fs_end:]
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in tail)
        print(f"      尾部内容预览：{text[:120]}")

    # ---- 4. 切分 ----
    kernel1 = data[uoff:sqoff]
    rootfs0 = data[sqoff:fs_end]

    ok = True
    if kernel1[:4] != UIMAGE_MAGIC:
        print("[校验] kernel1 魔数异常", file=sys.stderr)
        ok = False
    if rootfs0[:4] not in (SQUASHFS_MAGIC, SQUASHFS_MAGIC_BE):
        print("[校验] rootfs0 魔数异常", file=sys.stderr)
        ok = False
    if not ok:
        die("切分结果自检失败，未写出文件。")

    print(f"[4/4] 切分完成：")
    print(f"      kernel1.bin = {len(kernel1):,} 字节（0x{uoff:X} → 0x{sqoff:X}）")
    print(f"      rootfs0.bin = {len(rootfs0):,} 字节（0x{sqoff:X} → 0x{fs_end:X}）")

    if args.check:
        print("\n[--check] 仅分析，未写出任何文件。")
        return 0

    # 输出目录
    outdir = args.outdir or os.path.join(os.path.dirname(os.path.abspath(args.image)), "split")
    os.makedirs(outdir, exist_ok=True)

    prefix = args.prefix
    if not prefix:
        base = os.path.basename(args.image)
        for suffix in ("-squashfs-sysupgrade.bin", ".bin"):
            if base.endswith(suffix):
                base = base[: -len(suffix)]
                break
        prefix = base if len(base) <= 40 else base[:40]

    pad_to = 0
    if args.pad:
        try:
            pad_to = int(args.pad, 0)
        except ValueError:
            die(f"--pad 参数无法解析：{args.pad}", 2)
        if pad_to <= 1:
            die("--pad 必须大于 1", 2)

    def write_out(name, blob):
        if pad_to:
            rem = len(blob) % pad_to
            if rem:
                blob = blob + b"\x00" * (pad_to - rem)
        path = os.path.join(outdir, name)
        with open(path, "wb") as f:
            f.write(blob)
        return path, len(blob)

    try:
        p1, n1 = write_out(f"{prefix}-kernel1.bin", kernel1)
        p2, n2 = write_out(f"{prefix}-rootfs0.bin", rootfs0)
    except OSError as e:
        die(f"写入失败：{e}", 2)

    print("\n输出文件：")
    print(f"  {p1}  ({n1:,} 字节)")
    print(f"  {p2}  ({n2:,} 字节)")
    print("\n在 Breed 中分别写入：kernel1 → 内核分区，rootfs0 → 根文件系统分区。")
    print("注意：分开刷后首次启动可能因分区表不一致失败，优先尝试整包 sysupgrade。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
