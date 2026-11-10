#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""04-check-upstream.py —— 巡检 SOURCES.md 中登记的上游固件是否仍然可用、是否被替换。

上游固件站的老版本目录会被归档或下架，URL 静默失效后，照文档操作的人会卡在第一步
下载上。本脚本用于定期确认「文档里写的 URL 现在还能下、下到的还是不是当初那个文件」。

两种模式：
    head    只发 HEAD 请求，比对 Content-Length 与清单记录的字节数。快，不下载。
    deep    完整下载到临时目录，计算 SHA256 与清单比对。慢，但能发现「体积相同内容被换」。

用法：
    python 04-check-upstream.py                      # 默认 head 模式，检查全部条目
    python 04-check-upstream.py --mode deep          # 全量下载校验
    python 04-check-upstream.py --only required      # 只查已入库的 7 个，跳过可选文件
    python 04-check-upstream.py --report out.md      # 同时把 Markdown 报告写入文件

退出码：
    0  全部正常
    1  存在不可达 / 体积不符 / 哈希不符的条目
    2  清单解析失败等环境错误
"""

import argparse
import hashlib
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional

UA = "r3g-handbook-firmware-checker/1.0 (+https://github.com/angryawei/xiaomi-r3g-breed-openwrt)"
CHUNK = 256 * 1024


@dataclass
class Entry:
    name: str
    url: str
    sha256: str
    size_bytes: Optional[int]
    optional: bool = False
    # 巡检结果
    status_code: Optional[int] = None
    remote_size: Optional[int] = None
    remote_sha256: Optional[str] = None
    verdict: str = "未检查"          # 正常 / 不可达 / 体积不符 / 哈希不符 / 体积未知 / 错误
    detail: str = ""


def parse_sources(path: str) -> List[Entry]:
    """从 SOURCES.md 解析表格。只认「一、」「二、」两节下的文件行。"""
    entries: List[Entry] = []
    section = "skip"

    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n").strip()

            # 任何 Markdown 标题都会切换「当前节」。
            # 一、= 已入库（必查）；二、= 可选文件；其余一律 skip——
            # 特别是 "### 1.1 各文件许可状态" 这类子标题下的许可表，
            # 虽然也带文件名但没有 URL，必须排除，否则会污染巡检结果。
            if re.match(r"^#{1,6}\s", line):
                if re.match(r"^#{1,6}\s*一、", line):
                    section = "required"
                elif re.match(r"^#{1,6}\s*二、", line):
                    section = "optional"
                else:
                    section = "skip"
                continue

            if section == "skip" or not line.startswith("|"):
                continue
            if re.match(r"^[\|\s\-:]+$", line):        # 表格分隔行
                continue
            if "文件名" in line and "SHA256" in line:   # 表头
                continue

            name_m = re.match(r"^\|\s*`([^`]+?\.bin)`", line)
            if not name_m:
                continue

            url_m = re.search(r"https?://[^\s|()（）<>]+", line)
            hash_m = re.search(r"\b([0-9a-fA-F]{64})\b", line)
            size_m = re.search(r"\((\d[\d,]*)\s*B\)", line)

            if not url_m or not hash_m:
                entries.append(Entry(
                    name=name_m.group(1), url=url_m.group(0) if url_m else "",
                    sha256=hash_m.group(1).lower() if hash_m else "",
                    size_bytes=None, optional=(section == "optional"),
                    verdict="错误", detail="清单缺少 URL 或 SHA256，无法检查"))
                continue

            size_bytes = int(size_m.group(1).replace(",", "")) if size_m else None
            entries.append(Entry(
                name=name_m.group(1),
                url=url_m.group(0),
                sha256=hash_m.group(1).lower(),
                size_bytes=size_bytes,
                optional=(section == "optional"),
            ))

    return entries


def http_probe(url: str, timeout: int) -> tuple:
    """HEAD 请求，返回 (状态码, Content-Length 或 None)。跟随重定向。"""
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        cl = resp.headers.get("Content-Length")
        return resp.status, (int(cl) if cl and cl.isdigit() else None)


def download_and_hash(url: str, timeout: int, workdir: str) -> tuple:
    """下载到临时目录并计算 SHA256，返回 (状态码, 字节数, sha256)。"""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    h = hashlib.sha256()
    total = 0
    tmp_path = os.path.join(workdir, "download.part")
    with urllib.request.urlopen(req, timeout=timeout) as resp, open(tmp_path, "wb") as out:
        status = resp.status
        while True:
            block = resp.read(CHUNK)
            if not block:
                break
            out.write(block)
            h.update(block)
            total += len(block)
    try:
        os.remove(tmp_path)
    except OSError:
        pass
    return status, total, h.hexdigest()


def check_head(entry: Entry, timeout: int) -> None:
    try:
        code, cl = http_probe(entry.url, timeout)
        entry.status_code = code
        entry.remote_size = cl
        if code != 200:
            entry.verdict = "不可达"
            entry.detail = "HTTP %s" % code
        elif cl is None:
            entry.verdict = "体积未知"
            entry.detail = "服务端未返回 Content-Length"
        elif entry.size_bytes is None:
            entry.verdict = "体积未知"
            entry.detail = "清单未记录字节数"
        elif cl != entry.size_bytes:
            entry.verdict = "体积不符"
            entry.detail = "清单 %d B，上游 %d B" % (entry.size_bytes, cl)
        else:
            entry.verdict = "正常"
            entry.detail = "体积一致"
    except urllib.error.HTTPError as exc:
        entry.status_code = exc.code
        entry.verdict = "不可达"
        entry.detail = "HTTP %s" % exc.code
    except Exception as exc:                                  # noqa: BLE001
        entry.verdict = "错误"
        entry.detail = "%s: %s" % (type(exc).__name__, exc)


def check_deep(entry: Entry, timeout: int, workdir: str) -> None:
    try:
        code, size, digest = download_and_hash(entry.url, timeout, workdir)
        entry.status_code = code
        entry.remote_size = size
        entry.remote_sha256 = digest
        if code != 200:
            entry.verdict = "不可达"
            entry.detail = "HTTP %s" % code
        elif digest != entry.sha256:
            entry.verdict = "哈希不符"
            entry.detail = "上游内容已变更"
        else:
            entry.verdict = "正常"
            entry.detail = "哈希一致"
    except urllib.error.HTTPError as exc:
        entry.status_code = exc.code
        entry.verdict = "不可达"
        entry.detail = "HTTP %s" % exc.code
    except Exception as exc:                                  # noqa: BLE001
        entry.verdict = "错误"
        entry.detail = "%s: %s" % (type(exc).__name__, exc)


def human(n: Optional[int]) -> str:
    if n is None:
        return "—"
    if n >= 1024 * 1024:
        return "%.2f MB" % (n / 1048576)
    if n >= 1024:
        return "%.0f KB" % (n / 1024)
    return "%d B" % n


def main() -> int:
    ap = argparse.ArgumentParser(description="巡检 SOURCES.md 中上游固件的可用性与一致性")
    ap.add_argument("--sources", default=None, help="SOURCES.md 路径，默认脚本同级的 ../firmware/SOURCES.md")
    ap.add_argument("--mode", choices=["head", "deep"], default="head", help="head 只比体积；deep 下载算哈希")
    ap.add_argument("--only", choices=["all", "required", "optional"], default="all",
                    help="all 全部；required 只查已入库；optional 只查可选文件")
    ap.add_argument("--timeout", type=int, default=120, help="单个请求超时秒数")
    ap.add_argument("--report", default=None, help="把 Markdown 报告写入该文件")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    sources = args.sources or os.path.join(here, "..", "firmware", "SOURCES.md")
    if not os.path.isfile(sources):
        print("[错误] 找不到清单：%s" % sources, file=sys.stderr)
        return 2

    entries = parse_sources(sources)
    if args.only == "required":
        entries = [e for e in entries if not e.optional]
    elif args.only == "optional":
        entries = [e for e in entries if e.optional]
    if not entries:
        print("[错误] 未从清单解析出任何条目：%s" % sources, file=sys.stderr)
        return 2

    workdir = tempfile.mkdtemp(prefix="r3g-check-")
    try:
        for idx, entry in enumerate(entries, 1):
            label = "[%d/%d] %s" % (idx, len(entries), entry.name)
            print(label, end=" ... ", flush=True)
            if args.mode == "deep":
                check_deep(entry, args.timeout, workdir)
            else:
                check_head(entry, args.timeout)
            print("%s（%s）" % (entry.verdict, entry.detail), flush=True)
            time.sleep(1)          # 温和限速，避免上游 CDN 判定为爬虫
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    abnormal = [e for e in entries if e.verdict != "正常"]
    now = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %z")

    lines = []
    lines.append("## 上游固件状态巡检")
    lines.append("")
    lines.append("| 项目 | 值 |")
    lines.append("|---|---|")
    lines.append("| 检查时间 | %s |" % now)
    lines.append("| 模式 | `%s` |" % args.mode)
    lines.append("| 清单 | `%s` |" % os.path.relpath(sources))
    lines.append("| 条目 | %d 个，异常 %d 个 |" % (len(entries), len(abnormal)))
    lines.append("")
    lines.append("| 文件 | 状态 | 说明 | HTTP | 上游体积 |")
    lines.append("|---|---|---|---|---|")
    for e in entries:
        lines.append("| `%s` | %s | %s | %s | %s |" % (
            e.name, e.verdict, e.detail,
            e.status_code if e.status_code is not None else "—",
            human(e.remote_size)))
    lines.append("")

    report = "\n".join(lines)
    print()
    print(report)

    if args.report:
        with open(args.report, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(report + "\n")
        print("报告已写入：%s" % args.report)

    if abnormal:
        print("共 %d 个条目异常，详见上表。" % len(abnormal), file=sys.stderr)
        return 1
    print("全部条目正常。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
