<#
.SYNOPSIS
    Everything Command-line Interface (es.exe) を voidtools の公式 GitHub release から取得する。

.DESCRIPTION
    固定バージョンの ES CLI zip を GitHub から取得し、SHA256 で検証してから展開、
    指定ディレクトリに es.exe を配置する。
    Plugins/PowerPoint/ppt_scan_gui.ps1 の Find-EverythingExe は次の順で es.exe を探す:
      1. C:\Program Files\Everything\es.exe
      2. C:\Program Files (x86)\Everything\es.exe
      3. %LOCALAPPDATA%\AutoHotkey\es\es.exe
      4. $env:PATH 上

.PARAMETER InstallDir
    es.exe の配置先。既定は 'C:\Program Files\Everything'。
    LOCALAPPDATA 配下にしたい場合は -InstallDir "$env:LOCALAPPDATA\AutoHotkey\es" を指定する。

.PARAMETER Force
    既存の es.exe を上書きする。未指定時は既存ファイルがあれば中断する。

.EXAMPLE
    # Program Files 配置 (要 admin)
    powershell -NoProfile -ExecutionPolicy Bypass -File Plugins\PowerPoint\install_everything_cli.ps1

.EXAMPLE
    # LOCALAPPDATA 配置 (admin 不要)
    powershell -NoProfile -ExecutionPolicy Bypass -File Plugins\PowerPoint\install_everything_cli.ps1 -InstallDir "$env:LOCALAPPDATA\AutoHotkey\es"
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Program Files\Everything',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# 固定版リリース情報 (voidtools/ES GitHub release)
$release = @{
    Version = '1.1.0.37'
    Url     = 'https://github.com/voidtools/ES/releases/download/1.1.0.37/ES-1.1.0.37.x64.zip'
    Sha256  = '7A57670D9152068D05876C58858C82FE6D3915A9DF2C819F4DE8801E2929D3A7'
    ZipName = 'ES-1.1.0.37.x64.zip'
}

function Write-Info { param([string]$Message) Write-Host "[install_es] $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "[install_es] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[install_es] $Message" -ForegroundColor Yellow }

Write-Info ('ES CLI version: {0}' -f $release.Version)

# Everything 本体 (Everything.exe) の存在確認。本体が無ければ es.exe 単体では機能しない。
$everythingBodyPaths = @(
    'C:\Program Files\Everything\Everything.exe',
    'C:\Program Files (x86)\Everything\Everything.exe'
)
$everythingFound = $everythingBodyPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $everythingFound) {
    Write-Warn 'Everything 本体 (Everything.exe) が未インストールです。'
    Write-Warn '次のいずれかで先にインストールしてください:'
    Write-Warn '  winget install voidtools.Everything'
    Write-Warn '  https://www.voidtools.com/downloads/'
    Write-Warn '本スクリプトは es.exe (CLI) のみ配置します。Everything 本体がないと'
    Write-Warn 'es.exe は IPC 接続に失敗し、PowerPoint source manager は WDS/Directory fallback になります。'
    if (-not $Force) {
        Write-Warn '承知の上で続行するには -Force を指定してください。'
        exit 1
    }
    Write-Warn '-Force 指定のため続行します。'
} else {
    Write-Info ('Everything body found: {0}' -f $everythingFound)
}

$destExe = Join-Path $InstallDir 'es.exe'
if ((Test-Path -LiteralPath $destExe -PathType Leaf) -and -not $Force) {
    Write-Warn ('es.exe already exists: {0}' -f $destExe)
    Write-Warn '上書きする場合は -Force を指定してください。'
    exit 0
}

# PS 5.1 用 TLS 1.2 明示 (既存設定を保持)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {
    Write-Warn ('TLS 1.2 の明示に失敗 (継続): {0}' -f $_.Exception.Message)
}

$workRoot = Join-Path $env:TEMP ('fetch_es_{0}' -f ([System.Guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$zipPath = Join-Path $workRoot $release.ZipName
$extractDir = Join-Path $workRoot 'extract'

try {
    Write-Info ('Downloading: {0}' -f $release.Url)
    Invoke-WebRequest -Uri $release.Url -OutFile $zipPath -UseBasicParsing
    Write-Ok ('Downloaded -> {0}' -f $zipPath)

    Write-Info 'Verifying SHA256...'
    $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    if ($actual -ne $release.Sha256) {
        throw ("SHA256 mismatch.`n  expected: {0}`n  actual:   {1}" -f $release.Sha256, $actual)
    }
    Write-Ok 'SHA256 OK'

    Write-Info 'Extracting...'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $sourceExe = Join-Path $extractDir 'es.exe'
    if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
        throw ('zip 内に es.exe が見つかりません: {0}' -f $extractDir)
    }

    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
        Write-Info ('Creating install dir: {0}' -f $InstallDir)
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Write-Info ('Installing -> {0}' -f $destExe)
    try {
        Copy-Item -LiteralPath $sourceExe -Destination $destExe -Force
    } catch {
        throw ("es.exe のコピーに失敗しました。`n  path: {0}`n  reason: {1}`n" -f $destExe, $_.Exception.Message) + `
              'Program Files 配下に書き込む場合は管理者 PowerShell で実行してください。'
    }

    Write-Info 'Running: es.exe --version'
    $versionOutput = & $destExe '--version' 2>&1
    Write-Ok ('es.exe --version -> {0}' -f ($versionOutput -join ' '))

    Write-Ok ('Installed successfully: {0}' -f $destExe)
} finally {
    try { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
