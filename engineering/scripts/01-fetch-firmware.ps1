<#
.SYNOPSIS
    01-fetch-firmware.ps1 —— 按 SOURCES.md 下载小米 R3G 固件，并强制 SHA256 校验。

.DESCRIPTION
    从 engineering\firmware\SOURCES.md 解析出「文件名 + 官方 URL + SHA256」，
    逐个下载到目标目录。任何一个文件哈希不匹配立即中止（不再继续后面的下载），
    并把已下坏的临时文件改成 .bad 后缀保留现场，方便人工排查。

.PARAMETER TargetDir
    固件存放目录，默认 <仓库根>\engineering\firmware。

.PARAMETER SourcesFile
    SOURCES.md 路径，默认 <TargetDir>\SOURCES.md。

.PARAMETER IncludeOptional
    同时下载 SOURCES.md 中「可选文件（未入库）」一节的固件（如 24.10.4 initramfs）。

.PARAMETER Force
    即使本地已存在且哈希正确，也重新下载。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\01-fetch-firmware.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\01-fetch-firmware.ps1 -IncludeOptional -Force

.NOTES
    退出码：0 全部成功；1 校验失败；2 环境/解析错误；3 下载失败。
#>

[CmdletBinding()]
param(
    [string]$TargetDir,
    [string]$SourcesFile,
    [switch]$IncludeOptional,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ---------- 推导默认路径 ----------
if (-not $TargetDir) {
    # 脚本位于 engineering\scripts\，固件目录是同级上级的 firmware\
    $TargetDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'firmware'
}
if (-not (Test-Path $TargetDir)) {
    Write-Host "[错误] 目标目录不存在：$TargetDir" -ForegroundColor Red
    Write-Host "       请先在仓库根目录下确认 engineering\firmware 存在。" -ForegroundColor Red
    exit 2
}
$TargetDir = (Resolve-Path $TargetDir).Path

if (-not $SourcesFile) { $SourcesFile = Join-Path $TargetDir 'SOURCES.md' }
if (-not (Test-Path $SourcesFile)) {
    Write-Host "[错误] 找不到清单文件：$SourcesFile" -ForegroundColor Red
    Write-Host "       清单格式为 Markdown 表格：| 文件名 | 体积 | 用途 | URL | SHA256 |" -ForegroundColor Red
    exit 2
}

# ---------- 解析 SOURCES.md ----------
$lines = Get-Content -LiteralPath $SourcesFile -Encoding UTF8
$items = @()
$section = 'required'
$currentVer = $null

foreach ($line in $lines) {
    $trim = $line.Trim()

    # 版本标注行，如 "## 一、已入库文件（7 个）"
    if ($trim -match '^#{2,3}\s*一、') { $section = 'required'; continue }
    if ($trim -match '^#{2,3}\s*二、') { $section = 'optional'; continue }
    if ($trim -match '^#{2,3}\s*(三|四|五)、') { $section = 'skip'; continue }

    if ($trim -notmatch '^\|') { continue }
    if ($trim -match '^[\|\s\-:]+$') { continue }          # 表格分隔行
    if ($trim -match '文件名' -and $trim -match 'SHA256') { continue }  # 表头

    # 第一列 `文件名`
    $nameMatch = [regex]::Match($trim, '^\|\s*`([^`]+?\.bin)`')
    if (-not $nameMatch.Success) { continue }

    $urlMatch  = [regex]::Match($trim, 'https?://[^\s\|\)）]+')
    $hashMatch = [regex]::Match($trim, '\b([0-9a-fA-F]{64})\b')

    if (-not $urlMatch.Success) {
        Write-Host "[警告] 该行没有可用下载 URL，跳过：$($nameMatch.Groups[1].Value)" -ForegroundColor Yellow
        continue
    }
    if (-not $hashMatch.Success) {
        Write-Host "[警告] 该行没有 SHA256，无法校验，跳过：$($nameMatch.Groups[1].Value)" -ForegroundColor Yellow
        Write-Host "       不允许下载未提供哈希的文件（防篡改）。" -ForegroundColor Yellow
        continue
    }

    $items += [pscustomobject]@{
        Name     = $nameMatch.Groups[1].Value
        Url      = $urlMatch.Value
        Sha256   = $hashMatch.Groups[1].Value.ToLower()
        Optional = ($section -eq 'optional')
    }
}

if ($items.Count -eq 0) {
    Write-Host "[错误] 未能从 SOURCES.md 解析出任何固件条目。" -ForegroundColor Red
    Write-Host "       请检查表格是否被改动（每个文件一行，含 URL 与 64 位 SHA256）。" -ForegroundColor Red
    exit 2
}

if (-not $IncludeOptional) { $items = $items | Where-Object { -not $_.Optional } }

Write-Host "目标目录：$TargetDir"
Write-Host ("待处理 {0} 个文件（含可选：{1}）" -f $items.Count, [bool]$IncludeOptional)
Write-Host ("-" * 78)

# ---------- 逐个下载 + 校验 ----------
$okList = @(); $skipList = @(); $failList = @()
$index = 0

foreach ($it in $items) {
    $index++
    $dest = Join-Path $TargetDir $it.Name
    Write-Host ("[{0}/{1}] {2}" -f $index, $items.Count, $it.Name) -ForegroundColor Cyan

    # 已存在且哈希正确则跳过
    if ((Test-Path $dest) -and (-not $Force)) {
        $existHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower()
        if ($existHash -eq $it.Sha256) {
            Write-Host "        已存在且哈希正确，跳过。" -ForegroundColor Green
            $skipList += $it.Name
            continue
        }
        Write-Host "        已存在但哈希不符，重新下载。" -ForegroundColor Yellow
    }

    $tmp = "$dest.part"
    if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    try {
        Write-Host "        下载中：$($it.Url)" -ForegroundColor Gray
        Invoke-WebRequest -Uri $it.Url -OutFile $tmp -UseBasicParsing -TimeoutSec 1200
    }
    catch {
        Write-Host "        [失败] 下载出错：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host "        可能原因：网络不通 / 域名被拦 / 官方已下架该版本。" -ForegroundColor Red
        Write-Host "        手工处理：浏览器打开上面的 URL 另存为 $($it.Name)，然后重跑本脚本校验。" -ForegroundColor Red
        if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        $failList += "$($it.Name)（下载失败）"
        exit 3
    }

    $size = (Get-Item -LiteralPath $tmp).Length
    if ($size -lt 1024) {
        Write-Host "        [失败] 下载体积异常（$size 字节），像是错误页面而不是固件。" -ForegroundColor Red
        Move-Item -LiteralPath $tmp -Destination "$dest.bad" -Force -ErrorAction SilentlyContinue
        $failList += "$($it.Name)（体积异常）"
        exit 3
    }

    $actual = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $it.Sha256) {
        Write-Host "        [校验失败][中止] 哈希不匹配，已停止后续下载。" -ForegroundColor Red
        Write-Host "        期望：$($it.Sha256)" -ForegroundColor Red
        Write-Host "        实际：$actual" -ForegroundColor Red
        Write-Host "        文件已改名保留现场：$dest.bad" -ForegroundColor Red
        Write-Host "        严禁使用该文件刷机！请换网络/换镜像源重下，或核对 SOURCES.md 是否被改动。" -ForegroundColor Red
        Move-Item -LiteralPath $tmp -Destination "$dest.bad" -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Move-Item -LiteralPath $tmp -Destination $dest -Force
    Write-Host ("        校验通过（{0:N2} MB）" -f ($size / 1MB)) -ForegroundColor Green
    $okList += $it.Name
}

# ---------- 汇总 ----------
Write-Host ("-" * 78)
Write-Host "完成：新下载 $($okList.Count)，已存在跳过 $($skipList.Count)，失败 $($failList.Count)"
if ($okList.Count -gt 0)  { Write-Host "  新下载：$($okList -join ', ')" }
if ($skipList.Count -gt 0){ Write-Host "  已跳过：$($skipList -join ', ')" }
if ($failList.Count -gt 0){ Write-Host "  失败项：$($failList -join ', ')" -ForegroundColor Red; exit 3 }

Write-Host "全部固件就绪，可继续刷机流程。" -ForegroundColor Green
exit 0
