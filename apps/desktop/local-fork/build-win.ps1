# Build the Windows desktop package with the right environment already applied.
#
#   .\build-win.ps1 -CheckOnly      # 只做配置与工具链体检（秒级，不下载）
#   .\build-win.ps1                 # 完整打包，出 NSIS 安装包
#   .\build-win.ps1 -DirMode        # 目录版，跳过 NSIS，调试用
#   .\build-win.ps1 -NoProxy        # 不自动启用系统代理
#   .\build-win.ps1 -Mirror         # 没有代理时：Electron 走 npmmirror 镜像
#   .\build-win.ps1 -SkipBuild      # 跳过源码编译（只适合「源码没动、只想重打」）
#
# 代理设置读的是 Windows 的 IE/WinINET 代理（Clash、v2ray 等本机客户端都写在这里），
# 因为 Node 的 fetch 不读系统代理，只认 HTTPS_PROXY + NODE_USE_ENV_PROXY。

[CmdletBinding()]
param(
  [switch]$CheckOnly,
  [switch]$DirMode,
  [switch]$NoProxy,
  [switch]$Mirror,
  [switch]$SkipBuild,
  [string]$CacheDir = ''
)

$ErrorActionPreference = 'Stop'

function Write-Step($Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok($Text) { Write-Host "    $Text" -ForegroundColor Green }
function Write-Warn2($Text) { Write-Host "    $Text" -ForegroundColor Yellow }

# --- 1. 定位仓库根目录（本脚本在 apps/desktop/local-fork 下）---------------------------------
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not (Test-Path (Join-Path $repoRoot 'pnpm-workspace.yaml'))) {
  throw "找不到 pnpm-workspace.yaml，$repoRoot 不是仓库根目录"
}
Set-Location $repoRoot
Write-Step "工作目录 $repoRoot"

# --- 2. 版本检查：Node >= 24.9，pnpm 必须存在 ------------------------------------------------
$nodeVersion = (& node -v).TrimStart('v')
$nodeParts = $nodeVersion.Split('.')
$nodeOk = ([int]$nodeParts[0] -gt 24) -or ([int]$nodeParts[0] -eq 24 -and [int]$nodeParts[1] -ge 9)
Write-Ok "node v$nodeVersion"
if (-not $nodeOk) {
  Write-Warn2 'Node 版本低于 24.9，pnpm install 与构建会失败；请让 PATH 指向 24.x 的 Node 后重试'
  Write-Warn2 "当前生效的 node：$((Get-Command node).Source)"
  exit 2
}

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  Write-Warn2 'PATH 里没有 pnpm。先用 corepack 装一个：'
  Write-Warn2 '  corepack enable --install-directory "$env:APPDATA\npm" pnpm'
  exit 2
}
Write-Ok "pnpm $((& pnpm -v).Trim())"

# --- 3. 代理：未显式设置时，尝试复用系统代理 ------------------------------------------------
function Get-SystemProxyUrl {
  try {
    $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if ($settings.ProxyEnable -ne 1 -or [string]::IsNullOrWhiteSpace($settings.ProxyServer)) { return $null }
    $server = [string]$settings.ProxyServer
    if ($server -match '=') {
      foreach ($part in $server.Split(';')) {
        $kv = $part.Split('=', 2)
        if ($kv.Count -eq 2 -and $kv[0].Trim() -in @('https', 'http')) {
          $value = $kv[1].Trim()
          if ($value -notmatch '^\w+://') { $value = "http://$value" }
          if ($kv[0].Trim() -eq 'https') { return $value }
        }
      }
      return $null
    }
    if ($server -notmatch '^\w+://') { $server = "http://$server" }
    return $server
  }
  catch { return $null }
}

function Test-ProxyWorks([string]$ProxyUrl) {
  if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return $false }
  $code = & curl.exe -q -s -o NUL -w '%{http_code}' --max-time 10 -x $ProxyUrl 'https://github.com' 2>$null
  return ($code -match '^[23]\d\d$')
}

if (-not $NoProxy -and [string]::IsNullOrWhiteSpace($env:HTTPS_PROXY)) {
  $systemProxy = Get-SystemProxyUrl
  if ($systemProxy) {
    if (Test-ProxyWorks $systemProxy) {
      $env:HTTP_PROXY = $systemProxy
      $env:HTTPS_PROXY = $systemProxy
      Write-Ok "使用系统代理 $systemProxy（已实测可访问 GitHub）"
    }
    else {
      Write-Warn2 "系统代理 $systemProxy 不可用（或访问 GitHub 失败），继续直连"
    }
  }
  else {
    Write-Warn2 '没有检测到系统代理'
  }
}
elseif ($env:HTTPS_PROXY) {
  Write-Ok "沿用已有代理 $env:HTTPS_PROXY"
}

if ($env:HTTPS_PROXY) {
  # 这两个开关缺一不可：Node fetch 与 @electron/get 都不读系统代理
  $env:NODE_USE_ENV_PROXY = '1'
  $env:ELECTRON_GET_USE_PROXY = '1'
  if ([string]::IsNullOrWhiteSpace($env:NO_PROXY)) {
    $env:NO_PROXY = 'localhost,127.0.0.1,::1'
  }
  Write-Ok 'NODE_USE_ENV_PROXY=1 / ELECTRON_GET_USE_PROXY=1 已设置'
}

# --- 4. 镜像（无代理可用时）：@electron/get 认这个变量 --------------------------------------
if ($Mirror) {
  $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
  Write-Ok 'ELECTRON_MIRROR 指向 npmmirror'
  Write-Warn2 '注意：CPython 仍取自 github.com，无代理时需要按 README 5.3.1 预置缓存'
}

# --- 5. 下载缓存（按内容哈希命名，可跨仓库跨机器复用）--------------------------------------
if ($CacheDir) {
  $env:DSH_DESKTOP_PACKAGE_CACHE_DIR = $CacheDir
}
if ($env:DSH_DESKTOP_PACKAGE_CACHE_DIR) {
  $cacheRoot = $env:DSH_DESKTOP_PACKAGE_CACHE_DIR
  foreach ($sub in @('downloads', 'pnpm-store')) {
    $path = Join-Path $cacheRoot $sub
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
  }
  Write-Ok "缓存目录 $cacheRoot"
}
else {
  Write-Warn2 '未设置 DSH_DESKTOP_PACKAGE_CACHE_DIR，缓存将落在 apps/desktop/.desktop-build'
}

# --- 5.5 编译工作区源码 ---------------------------------------------------------------------
# 打包链路（package-target.ts）只搬运各包已经编译好的 lib/，它自己从不编译源码。
# 所以改了 src/ 却直接打包，装出来的程序跑的还是旧 lib ——插件没生效、门控没生效都属于这一类。
if (-not $CheckOnly) {
  if ($SkipBuild) {
    Write-Warn2 '已跳过编译（-SkipBuild）：用现有 lib/ 打包，改了源码也不会生效'
  }
  else {
    # 外部环境（IDE / 沙箱 / 某些安全软件）注入的 NODE_OPTIONS 会带 require 钩子，
    # 干扰 tsdown 构建阶段的清理动作，报奇怪的删除失败。编译期间清掉。
    if (Test-Path Env:NODE_OPTIONS) { Remove-Item Env:NODE_OPTIONS }
    Write-Step '编译工作区（tsc + tsdown，几分钟）'
    & pnpm run build:artifacts
    if ($LASTEXITCODE -ne 0) {
      Write-Warn2 '编译失败，已中止打包：继续打会用旧 lib/，需要先修好编译错误'
      exit $LASTEXITCODE
    }
    Write-Ok '编译完成，各包 lib/ 已是最新'
  }
}

# --- 6. 执行 --------------------------------------------------------------------------------
if ($CheckOnly) {
  Write-Step '体检（不编译、不下载）'
  & pnpm run package:desktop:win:x64:unsigned --check
  exit $LASTEXITCODE
}

if ($DirMode) {
  Write-Step '打包目录版（跳过 NSIS）'
  & pnpm run package:desktop:win:x64:dir -- --unsigned
}
else {
  Write-Step '完整打包（首次 10~30 分钟）'
  & pnpm run package:desktop:win:x64:unsigned
}
$code = $LASTEXITCODE

if ($code -eq 0) {
  Write-Step '产物'
  $outDir = Join-Path $repoRoot 'apps/desktop/.desktop-build/targets/win-x64/unsigned-artifacts'
  if (Test-Path $outDir) { Get-ChildItem $outDir | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize }
}
else {
  $runs = Join-Path $repoRoot 'apps/desktop/.desktop-build/packaging-runs'
  $latest = Get-ChildItem $runs -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Write-Warn2 "失败，查看证据：$($latest.FullName)\result.json 与 events.jsonl"
}
exit $code
