#!/bin/sh
# =============================================================================
# 00-backup-nand.sh  —  小米 R3G (v1, 128MB NAND) 刷机前全量备份
# 用途：在 OpenWrt 上把整片 NAND 与各分区 dd 出来，先落到 /tmp（tmpfs），
#       再取回电脑保存。刷机前跑一遍，刷坏了还能用 Breed 把备份写回去。
# 运行环境：OpenWrt（busybox ash），需 root
# 用法：
#   sh 00-backup-nand.sh              # 默认：按分区备份到 /tmp/nand-backup
#   sh 00-backup-nand.sh --full       # 额外尝试整片 NAND 备份（需 /tmp 空间足够）
#   sh 00-backup-nand.sh --list       # 只列分区表，不做备份
# 作者备注：本脚本只读，不写任何 flash 分区，安全。
# =============================================================================

set -u

OUT_DIR="/tmp/nand-backup"
FULL=0
LIST_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --full) FULL=1 ;;
        --list) LIST_ONLY=1 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "[错误] 未知参数：$arg（可用：--full / --list / --help）" >&2
            exit 2
            ;;
    esac
done

# ---------- 前置检查 ----------
if [ "$(id -u)" != "0" ]; then
    echo "[错误] 需要 root 权限运行。请用 root 登录后执行。" >&2
    exit 1
fi

if [ ! -r /proc/mtd ]; then
    echo "[错误] 读不到 /proc/mtd，当前系统可能不是 OpenWrt，或内核未暴露 MTD 接口。" >&2
    echo "       请确认已进入 OpenWrt（含 initramfs 内存系统）后再执行。" >&2
    exit 1
fi

if ! command -v dd >/dev/null 2>&1; then
    echo "[错误] 找不到 dd 命令，无法备份。" >&2
    exit 1
fi

# ---------- 输出分区表 ----------
echo "==================== 当前 MTD 分区表 (/proc/mtd) ===================="
cat /proc/mtd
echo "===================================================================="

if [ "$LIST_ONLY" = "1" ]; then
    echo ""
    echo "[提示] 仅列出分区表，未执行备份（--list）。"
    echo "[提示] 刷机前请确认存在 'full' 或 'all'（整片）以及 'Bootloader'、'Factory'、'Kernel'、'rootfs' 分区。"
    exit 0
fi

mkdir -p "$OUT_DIR" || {
    echo "[错误] 无法创建输出目录 $OUT_DIR" >&2
    exit 1
}

# ---------- 空间检查 ----------
# /tmp 是 tmpfs，占的是内存（R3G 只有 128MB），塞不下 128MB 整片 NAND。
TMP_AVAIL_KB=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "${TMP_AVAIL_KB:-}" ] && TMP_AVAIL_KB=0
echo ""
echo "[信息] /tmp 可用空间：$((TMP_AVAIL_KB / 1024)) MB"
if [ "$TMP_AVAIL_KB" -lt 20480 ]; then
    echo "[警告] /tmp 可用空间不足 20MB，备份很可能中途失败。" >&2
    echo "       建议改用下面的『流式备份到电脑』方式（见脚本末尾提示）。" >&2
fi

# ---------- 逐分区备份 ----------
FAILED=0
OK=0
SUMMARY=""
SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' PART NAME EXPECTED ACTUAL RESULT)\n"

i=0
while read -r line; do
    # 形如：mtd0: 08000000 00020000 "all"
    DEV_NAME=$(echo "$line" | sed -n 's/^\(mtd[0-9]*\):.*"\(.*\)".*$/\1/p')
    PART_NAME=$(echo "$line" | sed -n 's/^mtd[0-9]*:.*"\(.*\)".*$/\1/p')
    SIZE_HEX=$(echo "$line" | awk '{print $2}')

    [ -z "$DEV_NAME" ] && continue

    # 跳过整片别名分区（用 --full 单独处理，避免 /tmp 被撑爆）
    case "$PART_NAME" in
        all|full)
            if [ "$FULL" != "1" ]; then
                SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' "$DEV_NAME" "$PART_NAME" "$SIZE_HEX" "-" "跳过(需 --full)")"
                continue
                ;;
            esac
            ;;
    esac

    # hex 大小 -> 字节
    EXPECTED=$((0x$SIZE_HEX))
    SAFE_NAME=$(echo "$PART_NAME" | tr -c 'A-Za-z0-9._-' '_')
    TARGET="$OUT_DIR/${DEV_NAME}-${SAFE_NAME}.bin"

    # 空间预判
    NEED_KB=$((EXPECTED / 1024 + 64))
    if [ "$TMP_AVAIL_KB" -lt "$NEED_KB" ]; then
        SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' "$DEV_NAME" "$PART_NAME" "$EXPECTED" "-" "失败(/tmp空间不足)")"
        FAILED=$((FAILED + 1))
        continue
    fi

    echo ""
    echo "[备份] $DEV_NAME \"$PART_NAME\"  期望 $EXPECTED 字节 -> $TARGET"

    # /dev/mtdblockX 读的是文件系统视图（不含 OOB），做分区取证/回写足够
    if dd if="/dev/mtdblock${DEV_NAME#mtd}" of="$TARGET" bs=64k 2>/dev/null; then
        ACTUAL=$(wc -c < "$TARGET" 2>/dev/null || echo 0)
        if [ "$ACTUAL" -eq "$EXPECTED" ]; then
            SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' "$DEV_NAME" "$PART_NAME" "$EXPECTED" "$ACTUAL" "成功")"
            OK=$((OK + 1))
        elif [ "$ACTUAL" -eq 0 ]; then
            SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' "$DEV_NAME" "$PART_NAME" "$EXPECTED" "$ACTUAL" "失败(读出0字节)")"
            FAILED=$((FAILED + 1))
        else
            # 大小不一致：不删文件，保留供人工判断（可能含坏块重映射）
            SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' "$DEV_NAME" "$PART_NAME" "$EXPECTED" "$ACTUAL" "警告(大小不一致)")"
            OK=$((OK + 1))
        fi
    else
        SUMMARY="${SUMMARY}$(printf '%-14s %-24s %12s %12s %s\n' "$DEV_NAME" "$PART_NAME" "$EXPECTED" "-" "失败(dd出错)")"
        FAILED=$((FAILED + 1))
    fi
    i=$((i + 1))
done < /proc/mtd

# ---------- 汇总 ----------
echo ""
echo "======================== 备份结果汇总 ========================"
printf "%b" "$SUMMARY"
echo "=============================================================="
echo "[统计] 成功/警告 $OK 个，失败 $FAILED 个，文件目录：$OUT_DIR"

# ---------- 生成校验清单 ----------
if ls "$OUT_DIR"/*.bin >/dev/null 2>&1; then
    ( cd "$OUT_DIR" && sha256sum ./*.bin > SHA256SUMS 2>/dev/null ) && \
        echo "[清单] 已生成 $OUT_DIR/SHA256SUMS" || \
        echo "[警告] SHA256SUMS 生成失败（可能缺少 sha256sum 命令）" >&2
fi

# ---------- 取回电脑 ----------
echo ""
echo "==================== 如何在电脑上取回备份 ===================="
echo "在电脑（Windows PowerShell / Linux 终端）执行："
echo ""
echo "  scp -O root@192.168.1.1:$OUT_DIR/*.bin ."
echo "  scp -O root@192.168.1.1:$OUT_DIR/SHA256SUMS ."
echo ""
echo "如果 scp 不可用（老版本 dropbear），改用 tar 流："
echo "  ssh root@192.168.1.1 'cd $OUT_DIR && tar czf - .' > r3g-nand-backup.tar.gz"
echo ""
echo "取回后再校验："
echo "  sha256sum -c SHA256SUMS"
echo "=============================================================="

if [ "$TMP_AVAIL_KB" -lt 20480 ]; then
    echo ""
    echo "!!! 重要 !!! 本次 /tmp 空间偏小，若上面出现失败项，请改用【流式备份】，"
    echo "内存里不落盘、直接写到电脑："
    echo ""
    echo "  # 逐分区流式备份（在电脑上执行，把 mtd1 换成你要的分区号）"
    echo "  ssh root@192.168.1.1 'dd if=/dev/mtdblock1 bs=64k' > mtd1-backup.bin"
    echo ""
fi

if [ "$FAILED" -gt 0 ]; then
    echo "[结论] 存在失败项，备份不完整，请勿在这一步之后直接刷机。" >&2
    exit 3
fi

echo "[结论] 备份完成，可以继续刷机流程。刷完若异常，可用 Breed 把对应分区文件写回。"
exit 0
