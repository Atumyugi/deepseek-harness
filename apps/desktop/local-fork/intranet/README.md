# 内网模型接入（vLLM / Ollama）

先说清楚一件事：**首屏那个「登录 / 添加 API Key」不是产品登录页**，是 Electron 主进程自己弹的
独立欢迎窗（`apps/desktop/renderer/welcome.html`），判据只有一行
（`apps/desktop/src/welcome-api.ts:73`）：

```ts
needsWelcome = !loggedIn && !hasApiKey
```

它只提供两条路：登录 DeepSeek 账号，或填 DeepSeek 官方 key。内网两样都没有。

所以只有两个选择：**让它不弹**（用户自己配），或**替用户配好**（弹之前就不满足条件）。

---

## 0. 选一个

| | 做法 | 用户体验 | 要不要重新打包 |
|---|---|---|---|
| **A（推荐）** | 欢迎窗不弹，用户自己在设置页填地址 | 打开就是主界面，自己去「设置 → 模型」填 | **要** |
| **B** | `seed.ps1` 预置配置和凭据 | 装完即用，一步不用点 | 不用，装完跑脚本 |

A 和 B 不冲突：A 是默认行为，B 可以给不想自己填的机器补一份预置。A 已经改好了。

---

## 一、方案 A：跳过欢迎窗，用户自己填（已实现）

### 改了什么

新增 `apps/desktop/src/welcome-policy.ts`：

```ts
export function welcomeEntryEnabled(env = process.env): boolean {
  return env.DSH_DESKTOP_WELCOME === '1'
}
```

`apps/desktop/src/main.ts` 里 4 处调用欢迎窗的地方都加了这道判断
（启动 `openInitialWindow`、退出登录后、会话过期、取消退出时恢复）。默认返回 `false`，
所以内网构建永远直接进主界面。

想临时看回原来的欢迎窗：设 `DSH_DESKTOP_WELCOME=1` 再启动。

### 试之前

```powershell
cd E:\yoyiCode\deepseek-harness
pnpm run dev:desktop        # 未打包的真实窗口，1~2 分钟
```

确认打开后**直接进主界面、没有欢迎窗**，再做打包。

### 打包

```powershell
powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\build-win.ps1 -CacheDir E:\dsh-cache -Mirror
```

### 用户怎么配（这段可以直接给最终用户）

1. 打开应用，左下角 **设置** → **模型**
2. 点 **添加模型提供商** → 选 **自定义模型 API**
3. 填四个字段：

| 字段 | vLLM 填什么 | Ollama 填什么 |
|---|---|---|
| **Provider ID** | 小写字母开头，如 `intranet` | 同左，如 `ollama` |
| **API 协议** | `OpenAI Chat Completions` | `OpenAI Chat Completions` |
| **API 地址** | `http://10.0.0.12:8000/v1` | `http://127.0.0.1:11434/v1` |
| **模型目录** | 点 **获取可用模型** 自动拉列表；拉不到就手填模型 ID | 同左 |

   API 密钥：vLLM 启动时加过 `--api-key` 就填那个值，没加随便填（如 `dsh`）；
   Ollama 填 `ollama`。**不能留空**，协议层要求有这个头。

4. **保存**
5. 回到对话输入框，点左下角的模型选择器，选中刚加的模型（选一次就成为默认）

### 两个提醒

- **API 地址必须带 `/v1`**。少写会 404，症状是「获取可用模型」一直转圈。
- 用户没选模型之前，输入框会提示「请选择模型」并禁止发送。这是正常的，选一次就好。

---

## 二、方案 B：预置（`seed.ps1`）

适合装机流程可控、不想让用户碰配置的场景。**不需要重新打包**，装完跑一次即可。

```powershell
cd apps\desktop\local-fork\intranet

# vLLM
.\seed.ps1 -Kind vllm -BaseUrl http://10.0.0.12:8000/v1 -Model Qwen2.5-72B-Instruct -ApiKey sk-xxx

# Ollama（不传 -ApiKey 时默认写 ollama）
.\seed.ps1 -Kind ollama -BaseUrl http://127.0.0.1:11434/v1 -Model qwen2.5:32b
```

| 开关 | 作用 |
|---|---|
| `-DryRun` | 只打印要写什么，不落盘 |
| `-ContextWindow 32768` / `-MaxTokens 8192` | 模型容量 |
| `-DisplayName "内网 Qwen"` | 选择器里显示的名字 |
| `-ProfileScope` | 写 UI 用的那个 patch（界面里还能继续改）；默认写 home 级（优先级最高、锁死） |
| `-Force` | 目标文件已存在且不是本脚本生成的，允许覆盖（会先备份） |
| `-Uninstall` | 移除本脚本写入的内容 |

它写两个文件，原文件自动备份成 `*.bak.<时间戳>`：

```
%USERPROFILE%\.dsh\cordis.patch.yml         → 挂 llm-pi-ai 的 OpenAI 兼容路由 + 设为默认模型
%USERPROFILE%\.dsh\.credentials.yaml         → version: 1 / refs: 下的 DSH_INTRANET_API_KEY
```

### 为什么必须有凭据

`needsWelcome` 里的 `hasApiKey` 是这么算的（`apps/desktop/src/welcome-backend.ts:90-121`）：
收集所有已声明 provider 的 `apiKeyEnv`，逐个问 `credentials.describe(ref)`，
**只要有一个 `configured === true`** 就算满足。所以预置 provider 还不够，凭据必须落地。

`agent-default-model` 也要改，否则内网会一直提示「请选择模型」。

### 关键格式坑

`.credentials.yaml` **不是**平铺的 `KEY: value`，必须是：

```yaml
version: 1
refs:
  DSH_INTRANET_API_KEY: sk-your-key
```

平铺格式会被直接拒绝（`DOCUMENT_VERSION = 1`，
`packages/credentials/credentials-local/src/index.ts:189-226`）。`seed.ps1` 已经处理好了。

---

## 三、排错

| 现象 | 原因 / 处理 |
|---|---|
| 还是弹欢迎窗 | 没重新打包（方案 A），或环境里设了 `DSH_DESKTOP_WELCOME=1` |
| 设置里没有「模型」页 | 打包时漏了 `ui-settings-models`；检查 `packages/bundle/web-app/cordis.patch.yml:304` |
| 「获取可用模型」转圈 / 404 | API 地址少了 `/v1`，或内网防火墙拦了 |
| 401 / 403 | API 密钥与 vLLM 的 `--api-key` 不一致 |
| `model not found` | 模型 ID 与服务端 `--served-model-name` / `ollama list` 不一致 |
| 提示「请选择模型」 | 还没在模型选择器里选过一次；或方案 B 的 `agent-default-model` 没生效 |
| 回复被截断 | 上下文窗口填小了 |
| 想恢复弹欢迎窗 | 去掉 `DSH_DESKTOP_WELCOME` 之外，把 `welcome-policy.ts` 改成 `return true` 重新打包 |

### 只想确认配置被接受（不连模型）

```powershell
$env:DSH_INTRANET_API_KEY = 'sk-your-key'   # headless 不读凭据文件，只能用环境变量
pnpm run dsh -- --profile headless 'hi'
```

- `TRANSPORT: Connection error` → 配置和凭据都对，只是端点没连上
- `no credential for provider route "intranet"` → 环境变量没生效
- 什么都不报直接跑完 → 端点真的通了

> headless profile 会把 `credentials` / `authorization` / `deepseek-account` 整体禁用
> （`packages/bundle/headless/cordis.patch.yml:38-50`），所以它永远读不到
> `.credentials.yaml`，别把它的 `MISSING_CREDENTIAL` 当成配置写错。
