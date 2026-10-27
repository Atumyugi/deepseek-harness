<#
.SYNOPSIS
  只重跑 electron-builder 这一步，复用已经准备好的 runtime / package-set / dsh 树。

.DESCRIPTION
  build-win.ps1 的完整链路是：
    build → prepare-runtime → pack → prepare-package-set → prepare:dsh → electron-builder
  前五步每次要跑十几分钟，但只要没改依赖、没改产品名，产物都还能用。

  这个脚本直接把前五步的产物当作输入，只调用 electron-builder 生成安装包。
  适用场景：打包在最后一两步失败（安装器窗口 DLL 编译、NSIS 压缩），重来一遍太浪费。

  注意：改了 apps/cli/package.json、productName、icons 之后，必须跑完整流程，
  因为这些改动要经过 prepare:dsh 才会进入 runtime / asar。

  注意：本脚本「不编译源码」（不跑 tsc/tsdown），也「不重跑 prepare:dsh」。
  改了 packages/**/src 或 apps/**/src 之后用它是无效的——dsh 树里还是旧 lib。
  那种情况请跑 build-win.ps1（它会先编译再打包）。

.PARAMETER CacheDir
  下载缓存目录，和 build-win.ps1 的 -CacheDir 保持一致。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\resume-pack.ps1
#>
[CmdletBinding()]
param(
  [string]$CacheDir = 'E:\dsh-cache'
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Ok([string]$text) { Write-Host "    $text" -ForegroundColor Green }
function Write-Bad([string]$text) { Write-Host "    $text" -ForegroundColor Red }

$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildRoot = Join-Path $appRoot '.desktop-build/targets/win-x64'

# --- 1. 前置检查：前五步的产物必须齐 ---------------------------------------------------------
Write-Step '检查上一步产物'
Write-Host '    本脚本不编译源码、不重跑 prepare:dsh：改了 src/ 请改用 build-win.ps1' -ForegroundColor Yellow
$required = @{
  'runtime（内置 Node/CPython）' = (Join-Path $buildRoot 'runtime')
  'package-set（workspace tarball）' = (Join-Path $buildRoot 'package-set')
  'dsh（dsh 安装树）' = (Join-Path $buildRoot 'dsh')
}
$missing = @()
foreach ($name in $required.Keys) {
  if (Test-Path $required[$name]) { Write-Ok "有 $name" }
  else { Write-Bad "缺 $name"; $missing += $name }
}
if ($missing.Count -gt 0) {
  Write-Bad '产物不全，改成跑完整流程：'
  Write-Host '    powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\build-win.ps1 -CacheDir E:\dsh-cache -Mirror' -ForegroundColor Yellow
  exit 1
}

# --- 2. 读 .env.windows（productName/appId/更新源等都在这）------------------------------------
$envFile = Join-Path $appRoot '.env.windows'
if (-not (Test-Path $envFile)) {
  Write-Bad "缺少 $envFile，先跑一次 apply-brand.mjs 或照 .env.windows.example 复制一份"
  exit 1
}
Write-Step "读取 $envFile"
$loaded = 0
foreach ($line in Get-Content -LiteralPath $envFile -Encoding UTF8) {
  $text = $line.Trim()
  if ($text -eq '' -or $text.StartsWith('#')) { continue }
  $split = $text.IndexOf('=')
  if ($split -lt 1) { continue }
  $key = $text.Substring(0, $split).Trim()
  $value = $text.Substring($split + 1).Trim()
  if ($value.Length -ge 2) {
    $first = $value[0]
    $last = $value[$value.Length - 1]
    if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
      $value = $value.Substring(1, $value.Length - 2)
    }
  }
  Set-Item -Path "Env:$key" -Value $value
  $loaded++
}
Write-Ok "$loaded 项"

# --- 3. 固定环境变量（等价于 package-target.ts 里 unsigned 分支）-------------------------------
$env:DSH_DESKTOP_UNSIGNED = '1'
$env:DSH_DESKTOP_TARGET_PLATFORM = 'win32'
$env:DSH_DESKTOP_TARGET_ARCH = 'x64'
$env:DSH_DESKTOP_MACOS_SKIP_NOTARIZATION = '0'
$env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'
$env:ELECTRON_BUILDER_7Z_FILTER = 'BCJ'
if (-not $env:ELECTRON_BUILDER_COMPRESSION_LEVEL -and $env:DSH_DESKTOP_WINDOWS_COMPRESSION_LEVEL) {
  $env:ELECTRON_BUILDER_COMPRESSION_LEVEL = $env:DSH_DESKTOP_WINDOWS_COMPRESSION_LEVEL
}
if ($CacheDir) { $env:DSH_DESKTOP_PACKAGE_CACHE_DIR = $CacheDir }
if (-not $env:ELECTRON_MIRROR) { $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/' }
if ($env:HTTPS_PROXY) {
  $env:NODE_USE_ENV_PROXY = '1'
  $env:ELECTRON_GET_USE_PROXY = '1'
  if ([string]::IsNullOrWhiteSpace($env:NO_PROXY)) { $env:NO_PROXY = 'localhost,127.0.0.1,::1' }
}
if (Test-Path Env:NODE_OPTIONS) { Remove-Item Env:NODE_OPTIONS }
Write-Ok "appId=$env:DSH_DESKTOP_APP_ID  unsigned=1"

# --- 4. 只跑 electron-builder ---------------------------------------------------------------
Write-Step '调用 electron-builder（复用已准备产物）'
Push-Location $appRoot
try {
  & pnpm exec electron-builder --config electron-builder.config.mjs --win --x64 --publish never
  $code = $LASTEXITCODE
}
finally {
  Pop-Location
}

if ($code -eq 0) {
  Write-Step '产物'
  Get-ChildItem (Join-Path $buildRoot 'unsigned-artifacts') |
    Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }, LastWriteTime |
    Format-Table -AutoSize
}
else {
  Write-Bad "失败（退出码 $code）"
  Write-Host '    常见原因：' -ForegroundColor Yellow
  Write-Host '    - Native installer helper compilation failed → vcvars 要调 reg.exe，被安全策略拦了' -ForegroundColor Yellow
  Write-Host '    - 需要允许 reg.exe，或在你自己的 PowerShell 窗口里跑（不经沙箱）' -ForegroundColor Yellow
}
exit $code
