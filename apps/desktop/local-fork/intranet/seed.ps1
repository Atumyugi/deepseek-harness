# 内网模型接入：把 vLLM / Ollama 变成开箱即用的 provider
#
# 为什么需要这个：桌面端首屏那个「欢迎使用 / 登录 / 添加 API Key」是 Electron 主进程的
# 独立欢迎窗（apps/desktop/renderer/welcome.html），判据只有一句：
#
#     needsWelcome = !loggedIn && !hasApiKey      （apps/desktop/src/welcome-api.ts:73）
#
# 也就是说：只要存在"某个已配置的 provider 凭据"，欢迎窗就不会出现，直接进主界面。
# 所以内网接入不需要改界面、不需要改登录逻辑 —— 预置一份 provider 配置 + 一个凭据即可。
#
# 本脚本做的事（幂等，可重复执行）：
#   1. 写 %USERPROFILE%\.dsh\cordis.patch.yml          → 挂上内网 provider + 设为默认模型
#   2. 写 %USERPROFILE%\.dsh\.credentials.yaml          → 只增/改本脚本自己那个 key
# 原文件会先备份成 *.bak.<时间戳>。
#
# 用法（PowerShell）：
#   .\seed.ps1 -Kind vllm  -BaseUrl http://10.0.0.12:8000/v1 -Model Qwen2.5-72B-Instruct -ApiKey sk-xxx
#   .\seed.ps1 -Kind ollama -BaseUrl http://127.0.0.1:11434/v1 -Model qwen2.5:32b
#   .\seed.ps1 ... -DryRun     只看会写什么，不落盘
#   .\seed.ps1 ... -Uninstall  移除本脚本写入的内容
#
# 写完直接重启应用即可，**不需要重新打包**。

[CmdletBinding()]
param(
  [ValidateSet('vllm', 'ollama')]
  [string]$Kind = 'vllm',

  # OpenAI 兼容端点。vLLM 默认 8000，Ollama 默认 11434，都要带 /v1
  [string]$BaseUrl = '',

  # 服务端实际的模型 id：vLLM 用 --served-model-name 的名字，Ollama 用 ollama list 里的名字
  [string]$Model = '',

  # 内网服务通常也校验一个 key；Ollama 随便填。留空则用占位值
  [string]$ApiKey = '',

  # 显示在模型选择器里的名字
  [string]$DisplayName = '',

  # 上下文窗口 / 单次输出上限，写错只会影响能力探测，不影响能否调用
  [int]$ContextWindow = 32768,
  [int]$MaxTokens = 8192,

  # 写到 profiles\desktop\cordis.patch.yml 而不是 home 级（home 级优先级最高）
  [switch]$ProfileScope,

  # 目标文件已存在且内容不是本脚本生成的，必须加这个才会覆盖
  [switch]$Force,

  [switch]$DryRun,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# 本脚本独占的凭据引用名，卸载时按它精确删除，不碰其他 key
$CredRef = 'DSH_INTRANET_API_KEY'
$RouteId = 'intranet'
$Marker = '# generated-by: dsh-intranet-seed'

function Write-Step($Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok($Text) { Write-Host "    $Text" -ForegroundColor Green }
function Write-Warn2($Text) { Write-Host "    $Text" -ForegroundColor Yellow }

# --- 1. 定位 DSH home（尊重 $env:DSH_HOME，方便演练与测试）----------------------------------
$dshHome = if ([string]::IsNullOrWhiteSpace($env:DSH_HOME)) {
  Join-Path $env:USERPROFILE '.dsh'
} else {
  $env:DSH_HOME
}
$patchPath = if ($ProfileScope) {
  Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'
} else {
  Join-Path $dshHome 'cordis.patch.yml'
}
$credPath = Join-Path $dshHome '.credentials.yaml'

Write-Step "DSH home   $dshHome"
Write-Ok "patch      $patchPath"
Write-Ok "credentials $credPath"

# --- 2. 卸载（必须在参数校验之前，卸载不需要 -Model）-----------------------------------------
function Remove-OurPatch([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ($text -notmatch [regex]::Escape($Marker)) {
    Write-Warn2 "$Path 不是本脚本生成的，跳过（需要手工清理 $RouteId 与 agent-default-model）"
    return $false
  }
  [IO.File]::Delete($Path)
  return $true
}

function Remove-OurCredential([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
  $kept = @($lines | Where-Object { $_ -notmatch "^\s*$([regex]::Escape($CredRef))\s*:" })
  if ($kept.Count -eq $lines.Count) { return $false }
  Set-Content -LiteralPath $Path -Value $kept -Encoding UTF8
  return $true
}

if ($Uninstall) {
  Write-Step '卸载'
  if ($DryRun) {
    Write-Ok "会删除 $patchPath （仅当含 $Marker 标记）"
    Write-Ok "会从 $credPath 删除 $CredRef 一行"
    return
  }
  foreach ($p in @($patchPath, (Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'))) {
    if (Remove-OurPatch $p) { Write-Ok "已删除 $p" }
  }
  if (Remove-OurCredential $credPath) { Write-Ok "已从 $credPath 移除 $CredRef" }
  Write-Host "`n完成。下次启动会重新出现欢迎窗（因为不再有任何已配置的 provider 凭据）。" -ForegroundColor Green
  return
}

# --- 3. 参数默认值 ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = if ($Kind -eq 'ollama') { 'http://127.0.0.1:11434/v1' } else { 'http://127.0.0.1:8000/v1' }
}
if ([string]::IsNullOrWhiteSpace($Model)) {
  throw '必须用 -Model 指定服务端实际提供的模型 id：vLLM 看 curl <baseURL>/models 的 data[].id，Ollama 看 ollama list。'
}
if ([string]::IsNullOrWhiteSpace($DisplayName)) {
  $DisplayName = if ($Kind -eq 'ollama') { '内网 Ollama' } else { '内网 vLLM' }
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  # vLLM 未加 --api-key 时必须给 Authorization 头，占位值即可；Ollama 惯例用字面量 ollama
  $ApiKey = if ($Kind -eq 'ollama') { 'ollama' } else { 'dsh-intranet' }
}
if ($BaseUrl -notmatch '^https?://') { throw "-BaseUrl 必须以 http:// 或 https:// 开头，当前：$BaseUrl" }
if ($BaseUrl -notmatch '/v1/?$') {
  Write-Warn2 "端点不以 /v1 结尾，OpenAI 兼容协议通常是 $BaseUrl/v1 —— 确认一下这是不是你要的"
}
if ($ApiKey -notmatch '^[\x21-\x7e]+$') { throw '-ApiKey 只允许可打印 ASCII（不能有空格/中文）' }

Write-Step "接入参数"
Write-Ok "provider  $RouteId  ($DisplayName)"
Write-Ok "protocol  openai-completions"
Write-Ok "baseURL   $BaseUrl"
Write-Ok "model     $Model  (context $ContextWindow / maxTokens $MaxTokens)"
Write-Ok "credential $CredRef = $($ApiKey.Substring(0, [Math]::Min(4, $ApiKey.Length)))***"

# --- 4. 生成 patch 内容 ----------------------------------------------------------------------
$yaml = @"
$Marker
# 内网模型接入：挂上 OpenAI 兼容 provider 并设为默认模型。
# 重新生成请跑 local-fork/intranet/seed.ps1，卸载请跑 seed.ps1 -Uninstall。
# 删掉这两行里任何一行都会让首屏退回欢迎窗 / 输入框提示"请选择模型"。

- id: llm-pi-ai
  config:
    providers:
      ${RouteId}:
        displayName: $DisplayName
        apiKeyEnv: $CredRef
        api: openai-completions
        baseURL: $BaseUrl
        defaultContextWindow: $ContextWindow
        defaultMaxTokens: $MaxTokens
        models:
          - id: $Model
            name: $Model
            contextWindow: $ContextWindow
            maxTokens: $MaxTokens

- id: agent-default-model
  config:
    provider: $RouteId
    model: $Model
"@

# --- 5. 写 patch（存在且非本脚本生成时需 -Force）--------------------------------------------
$patchExists = Test-Path $patchPath
$ownedByUs = $false
if ($patchExists) {
  $ownedByUs = (Get-Content -LiteralPath $patchPath -Raw -Encoding UTF8) -match [regex]::Escape($Marker)
}
if ($patchExists -and -not $ownedByUs -and -not $Force) {
  throw "$patchPath 已存在且不是本脚本生成的。先备份并手工合并，或加 -Force 覆盖（会先备份）。"
}

# --- 6. 构造凭据文档（必须是 version 1 的 refs: 嵌套布局，平铺格式会被拒绝）-----------------
$credEntry = "  $CredRef`: $ApiKey"
$credExisting = @()
if (Test-Path $credPath) { $credExisting = @(Get-Content -LiteralPath $credPath -Encoding UTF8) }

if ($credExisting.Count -eq 0) {
  $credDoc = @('version: 1', 'refs:', $credEntry)
} else {
  $hasVersion = @($credExisting | Where-Object { $_ -match '^version\s*:' }).Count -gt 0
  if (-not $hasVersion) {
    throw "$credPath 是旧版平铺格式（缺 version: 1）。请先把它里面的条目缩进两格移到 refs: 下并在首行加 version: 1，再重跑本脚本（原文件已保留）。"
  }
  $kept = New-Object System.Collections.Generic.List[string]
  $inserted = $false
  foreach ($line in $credExisting) {
    if ($line -match "^\s+$([regex]::Escape($CredRef))\s*:") { continue }
    $kept.Add($line)
    if (-not $inserted -and $line -match '^refs\s*:\s*$') {
      $kept.Add($credEntry)
      $inserted = $true
    }
  }
  if (-not $inserted) {
    $kept.Add('refs:')
    $kept.Add($credEntry)
  }
  $credDoc = @($kept)
}

if ($DryRun) {
  Write-Step 'DryRun：以下内容会被写入，未落盘'
  Write-Host "`n----- $patchPath -----" -ForegroundColor DarkGray
  Write-Host $yaml
  Write-Host "`n----- $credPath -----" -ForegroundColor DarkGray
  Write-Host ($credDoc -join [Environment]::NewLine)
  return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $patchPath) | Out-Null
foreach ($target in @($patchPath, $credPath)) {
  if (Test-Path $target) {
    Copy-Item -LiteralPath $target -Destination "$target.bak.$stamp" -Force
    Write-Ok "已备份 $target.bak.$stamp"
  }
}

Set-Content -LiteralPath $patchPath -Value $yaml -Encoding UTF8
Set-Content -LiteralPath $credPath -Value $credDoc -Encoding UTF8
Write-Ok "已写入 $patchPath"
Write-Ok "已写入 $credPath"

Write-Host "`n完成。接着做：" -ForegroundColor Green
Write-Host '  1. 完全退出应用（含托盘图标），重新打开 —— 应该直接进主界面，不再出现欢迎窗'
Write-Host "  2. 输入框左下角模型选择器里应能看到「$DisplayName / $Model」"
Write-Host '  3. 随便问一句，能回话即通'
Write-Host ''
Write-Host '如果仍弹欢迎窗 / 仍连不上，看同目录 README.md 的「排错」一节。' -ForegroundColor Yellow
