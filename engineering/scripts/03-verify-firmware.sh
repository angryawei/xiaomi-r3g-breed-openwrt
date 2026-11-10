#!/bin/sh
# 03-verify-firmware.sh —— 按 SHA256SUMS 校验本地固件，全程不联网。
#
# 与 01-fetch-firmware.ps1 的分工：
#   01 负责「下载 + 校验」，需要联网；
#   本脚本只负责「校验已存在的文件」，不下载、不改名、不删文件。
#
# 兼容性：GNU coreutils / BSD(macOS) / BusyBox 三种环境，可直接在 OpenWrt 设备上运行。
# 用法：
#   ./03-verify-firmware.sh                        # 校验脚本同级的 ../firmware 目录
#   ./03-verify-firmware.sh -d /tmp                # 校验指定目录
#   ./03-verify-firmware.sh -d /tmp -m             # 只校验手头文件，缺失不报错
# 退出码：0 全部通过；1 存在不通过项；2 环境或清单错误。

set -u

DIR=""
SUMS=""
ALLOW_MISSING=0

usage() {
    cat <<'EOF'
用法: 03-verify-firmware.sh [-d 固件目录] [-s SHA256SUMS 路径] [-m]

  -d  待校验目录，默认为脚本所在目录的上一级 /firmware
  -s  校验清单路径，默认为 <目录>/SHA256SUMS
  -m  文件缺失只警告，不算失败（只校验手头部分文件时使用）
  -h  显示本帮助

退出码: 0 全部通过; 1 存在不通过项; 2 环境或清单错误
EOF
}

while getopts "d:s:mh" opt 2>/dev/null; do
    case "$opt" in
        d) DIR="$OPTARG" ;;
        s) SUMS="$OPTARG" ;;
        m) ALLOW_MISSING=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

# ---------- 推导路径 ----------
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
if [ -z "$DIR" ]; then
    DIR="$SELF_DIR/../firmware"
fi
if [ ! -d "$DIR" ]; then
    printf '[错误] 目录不存在：%s\n' "$DIR" >&2
    exit 2
fi
DIR=$(CDPATH= cd -- "$DIR" && pwd)

if [ -z "$SUMS" ]; then
    SUMS="$DIR/SHA256SUMS"
fi
if [ ! -f "$SUMS" ]; then
    printf '[错误] 找不到校验清单：%s\n' "$SUMS" >&2
    printf '       清单格式为每行：<64位SHA256>  <文件名>\n' >&2
    exit 2
fi

# ---------- 选择哈希实现 ----------
# GNU: sha256sum | macOS: shasum -a 256 | BusyBox: sha256sum
HASH_CMD=""
if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD="shasum"
else
    printf '[错误] 本机既无 sha256sum 也无 shasum，无法计算哈希。\n' >&2
    printf '       OpenWrt 请先安装：opkg update && opkg install coreutils-sha256sum\n' >&2
    exit 2
fi

hash_of() {
    if [ "$HASH_CMD" = "shasum" ]; then
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
    else
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    fi
}

human_size() {
    awk -v b="$1" 'BEGIN{
        if (b >= 1048576) printf "%.2f MB", b/1048576;
        else if (b >= 1024) printf "%.0f KB", b/1024;
        else printf "%d B", b;
    }'
}

# ---------- 统计 ----------
TOTAL=0; PASS=0
MISMATCH_LIST=""
MISSING_LIST=""

printf '校验目录：%s\n' "$DIR"
printf '清单文件：%s\n' "$SUMS"
printf '哈希实现：%s\n' "$HASH_CMD"

# 先数条目总数（跳过空行与注释）
TOTAL=$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$SUMS" | grep -c -E '^[0-9a-fA-F]{64}[[:space:]]' 2>/dev/null)
[ -z "$TOTAL" ] && TOTAL=0
if [ "$TOTAL" -eq 0 ]; then
    printf '[错误] 清单中没有任何可校验条目：%s\n' "$SUMS" >&2
    exit 2
fi
printf '条目 %s 个\n' "$TOTAL"
printf -- '------------------------------------------------------------------------------\n'

IDX=0
# 逐行读取，保留文件名里的空格
while IFS= read -r line || [ -n "$line" ]; do
    # 去掉行尾 CR（清单若在 Windows 下编辑过）
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in
        ''|'#'*) continue ;;
    esac

    # 取前 64 位十六进制为期望值，其余为文件名（去前导空格与可选的 * 二进制标记）
    expect=$(printf '%s' "$line" | cut -c1-64)
    case "$expect" in
        *[!0-9a-fA-F]*) continue ;;
    esac
    name=$(printf '%s' "$line" | cut -c65- | sed -e 's/^[[:space:]]*//' -e 's/^\*//')
    [ -z "$name" ] && continue

    IDX=$((IDX + 1))
    tag="[$IDX/$TOTAL]"
    path="$DIR/$name"

    if [ ! -f "$path" ]; then
        printf '%s 缺失      %s\n' "$tag" "$name"
        MISSING_LIST="$MISSING_LIST$name
"
        continue
    fi

    size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
    size_txt=$(human_size "${size:-0}")
    actual=$(hash_of "$path")

    # 统一小写比较
    expect_lc=$(printf '%s' "$expect" | tr 'A-F' 'a-f')
    actual_lc=$(printf '%s' "$actual" | tr 'A-F' 'a-f')

    if [ -n "$actual_lc" ] && [ "$actual_lc" = "$expect_lc" ]; then
        printf '%s 通过      %s  (%s)\n' "$tag" "$name" "$size_txt"
        PASS=$((PASS + 1))
    else
        printf '%s 校验失败  %s\n' "$tag" "$name"
        printf '        期望 %s\n' "$expect_lc"
        printf '        实际 %s\n' "${actual_lc:-读取失败}"
        MISMATCH_LIST="$MISMATCH_LIST$name
"
    fi
done < "$SUMS"

# ---------- 汇总 ----------
printf -- '------------------------------------------------------------------------------\n'
printf '通过 %s / 共 %s\n' "$PASS" "$TOTAL"

FAILED=0

if [ -n "$MISMATCH_LIST" ]; then
    failed_n=$(printf '%s' "$MISMATCH_LIST" | grep -c . )
    printf '不通过 %s 个：\n' "$failed_n"
    printf '%s' "$MISMATCH_LIST" | while IFS= read -r n; do
        [ -n "$n" ] && printf '        %s\n' "$n"
    done
    FAILED=1
fi

if [ -n "$MISSING_LIST" ]; then
    missing_n=$(printf '%s' "$MISSING_LIST" | grep -c . )
    if [ "$ALLOW_MISSING" -eq 1 ]; then
        printf '缺失 %s 个（-m 已放行）：\n' "$missing_n"
        printf '%s' "$MISSING_LIST" | while IFS= read -r n; do
            [ -n "$n" ] && printf '        %s\n' "$n"
        done
    else
        printf '缺失 %s 个：\n' "$missing_n"
        printf '%s' "$MISSING_LIST" | while IFS= read -r n; do
            [ -n "$n" ] && printf '        %s\n' "$n"
        done
        printf '        如需只校验手头文件，加 -m 重跑。\n'
        FAILED=1
    fi
fi

if [ "$FAILED" -eq 1 ]; then
    if [ -n "$MISMATCH_LIST" ]; then
        printf '\n严禁刷入校验失败的文件。\n'
        printf '可能原因：下载中断、存储介质损坏、被第三方修改、或清单本身被改动。\n'
        printf '处理方式：删除该文件，重新获取后再次校验。\n'
    fi
    exit 1
fi

printf '全部校验通过。\n'
exit 0
