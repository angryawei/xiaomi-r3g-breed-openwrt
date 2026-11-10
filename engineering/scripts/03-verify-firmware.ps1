<#
.SYNOPSIS
    03-verify-firmware.ps1 —— 按 SHA256SUMS 校验本地固件，全程不联网。

.DESCRIPTION
    读取固件目录下的 SHA256SUMS（标准 sha256sum 格式，与 Linux `sha256sum -c` 兼容），
    逐个计算本地文件的 SHA256 并比对，给出逐文件结论与汇总。

    与 01-fetch-firmware.ps1 的分工：
        01 负责「下载 + 校验」，需要联网；
        本脚本只负责「校验已存在的文件」，不下载、不改名、不删文件。

    典型用途：从 U 盘、网盘、别人手里拿到固件包后，刷机前先验一遍。

.PARAMETER Dir
    待校验目录。默认 <仓库根>\engineering\firmware。

.PARAMETER SumsFile
    SHA256SUMS 路径。默认 <Dir>\SHA256SUMS。

.PARAMETER AllowMissing
    文件缺失只记为「跳过」，不算失败。只校验手头部分文件时使用。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\03-verify-firmware.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\03-verify-firmware.ps1 -Dir D:\firmware

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\03-verify-firmware.ps1 -Dir D:\firmware -AllowMissing

.NOTES
    退出码：0 全部通过；1 存在不通过项；2 环境或清单错误。
    本脚本只读，不会修改任何文件。
#>

[CmdletBinding()]
param(
    [string]$Dir,
    [string]$SumsFile,
    [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'

# ---------- 推导默认路径 ----------
if (-not $Dir) {
    $Dir = Join-Path (Split-Path -Parent $PSScriptRoot) 'firmware'
}
if (-not (Test-Path -LiteralPath $Dir)) {
    Write-Host "[错误] 目录不存在：$Dir" -ForegroundColor Red
    exit 2
}
$Dir = (Resolve-Path -LiteralPath $Dir).Path

if (-not $SumsFile) { $SumsFile = Join-Path $Dir 'SHA256SUMS' }
if (-not (Test-Path -LiteralPath $SumsFile)) {
    Write-Host "[错误] 找不到校验清单：$SumsFile" -ForegroundColor Red
    Write-Host "       清单格式为每行：<64位SHA256>  <文件名>" -ForegroundColor Red
    exit 2
}

# ---------- 解析清单 ----------
$items = @()
foreach ($line in (Get-Content -LiteralPath $SumsFile -Encoding UTF8)) {
    $t = $line.Trim()
    if (-not $t) { continue }
    if ($t.StartsWith('#')) { continue }

    # 兼容 sha256sum 的两种格式：
    #   <hash>  <name>     二进制模式
    #   <hash> *<name>     文本模式（星号前缀）
    $m = [regex]::Match($t, '^([0-9a-fA-F]{64})\s+\*?(.+)$')
    if (-not $m.Success) {
        Write-Host "[警告] 清单行无法解析，已跳过：$t" -ForegroundColor Yellow
        continue
    }
    $items += [pscustomobject]@{
        Sha256 = $m.Groups[1].Value.ToLower()
        Name   = $m.Groups[2].Value.Trim()
    }
}

if ($items.Count -eq 0) {
    Write-Host "[错误] 清单中没有任何可校验条目：$SumsFile" -ForegroundColor Red
    exit 2
}

# ---------- 逐文件校验 ----------
Write-Host "校验目录：$Dir"
Write-Host "清单文件：$SumsFile"
Write-Host ("条目 {0} 个" -f $items.Count)
Write-Host ("-" * 78)

$pass = 0; $skip = 0
$mismatch = New-Object System.Collections.ArrayList
$missing  = New-Object System.Collections.ArrayList

$i = 0
foreach ($it in $items) {
    $i++
    $path = Join-Path $Dir $it.Name
    $tag  = "[{0}/{1}]" -f $i, $items.Count

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host ("{0} 缺失      {1}" -f $tag, $it.Name) -ForegroundColor DarkYellow
        [void]$missing.Add($it.Name)
        continue
    }

    $fi   = Get-Item -LiteralPath $path
    $size = $fi.Length
    $sizeText = if ($size -ge 1MB) { "{0:N2} MB" -f ($size / 1MB) } else { "{0:N0} KB" -f ($size / 1KB) }

    try {
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    }
    catch {
        Write-Host ("{0} 读取失败  {1} —— {2}" -f $tag, $it.Name, $_.Exception.Message) -ForegroundColor Red
        [void]$mismatch.Add([pscustomobject]@{ Name = $it.Name; Expect = $it.Sha256; Actual = '读取失败' })
        continue
    }

    if ($actual -eq $it.Sha256) {
        Write-Host ("{0} 通过      {1}  ({2})" -f $tag, $it.Name, $sizeText) -ForegroundColor Green
        $pass++
    }
    else {
        Write-Host ("{0} 校验失败  {1}" -f $tag, $it.Name) -ForegroundColor Red
        Write-Host ("        期望 {0}" -f $it.Sha256) -ForegroundColor Red
        Write-Host ("        实际 {0}" -f $actual) -ForegroundColor Red
        [void]$mismatch.Add([pscustomobject]@{ Name = $it.Name; Expect = $it.Sha256; Actual = $actual })
    }
}

# ---------- 汇总 ----------
Write-Host ("-" * 78)
Write-Host ("通过 {0} / 共 {1}" -f $pass, $items.Count)

if ($missing.Count -gt 0) {
    if ($AllowMissing) {
        $skip = $missing.Count
        Write-Host ("缺失 {0} 个（-AllowMissing 已放行）：" -f $skip) -ForegroundColor Yellow
        foreach ($n in $missing) { Write-Host "        $n" -ForegroundColor Yellow }
    }
    else {
        Write-Host ("缺失 {0} 个：" -f $missing.Count) -ForegroundColor Red
        foreach ($n in $missing) { Write-Host "        $n" -ForegroundColor Red }
        Write-Host "        如需只校验手头文件，加 -AllowMissing 重跑。" -ForegroundColor Yellow
    }
}

if ($mismatch.Count -gt 0) {
    Write-Host ("不通过 {0} 个：" -f $mismatch.Count) -ForegroundColor Red
    foreach ($x in $mismatch) { Write-Host ("        {0}" -f $x.Name) -ForegroundColor Red }
    Write-Host ""
    Write-Host "严禁刷入校验失败的文件。" -ForegroundColor Red
    Write-Host "可能原因：下载中断、存储介质损坏、被第三方修改、或清单本身被改动。" -ForegroundColor Yellow
    Write-Host "处理方式：删除该文件，用 01-fetch-firmware.ps1 重新获取后再次校验。" -ForegroundColor Yellow
    exit 1
}

if ($missing.Count -gt 0 -and -not $AllowMissing) {
    exit 1
}

Write-Host "全部校验通过。" -ForegroundColor Green
exit 0
