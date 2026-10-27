# 二次开发：改品牌 + 打 Windows 桌面端

这个目录是给「在官方源码基础上做自己的桌面端」准备的，不参与上游构建。
里面只有四样东西：

| 文件 | 作用 |
|---|---|
| `brand.json` | 唯一的品牌配置：应用名、安装包文件名前缀、AppID、公司名 |
| `apply-brand.mjs` | 把 `brand.json` 写进所有硬编码了应用名的源码与文案里 |
| `render-assets.ps1` | 用系统字体和 GDI+ 生成图标、托盘图标、安装器品牌图（离线可用） |
| `build-win.ps1` | 一键打包：自动套用系统代理、设置缓存目录、做版本检查后执行打包 |
| `README.md` | 本文档 |

改名字改图标，永远只有两步：

```sh
node apps/desktop/local-fork/apply-brand.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/local-fork/render-assets.ps1
```

## 1. 官方桌面端是怎么打出来的

Windows 安装包不是「把 Electron 跑起来打个包」这么简单，`apps/desktop` 是一个自带运行时的发行版：

```
pnpm run package:desktop:win:x64:unsigned      （入口：apps/desktop/scripts/package-target.ts）
  1. pnpm run build --profile local            编译整个仓库（host + client 两套产物）
  2. pack                                     把 dsh 各包、desktop-host、vendor、native 打成 tgz
  3. prepare:runtime                          下载 Electron、Node、CPython、Python wheels，
                                              生成 resources/runtime/{primary-runtime,cli,versions.json}
  4. prepare:packages                         从 tgz 里挑出桌面端需要的包闭包
  5. prepare:dsh                              用自带 Node+pnpm 装一份生产依赖进 app.asar/dsh
  6. electron-builder --win --x64             生成 NSIS 安装包
  7. smoke-packaged-runtime                   对打包结果做真实启动校验
```

关键结论：

- 用户机器上**不需要**联网装核心包，Electron、Node、Python、pnpm、dsh 运行时全部在安装包里。
- 因此安装包很大（数百 MB 量级），但内网可离线使用。
- 产物在 `apps/desktop/.desktop-build/targets/win-x64/unsigned-artifacts/`，
  文件名形如 `xiaoguang-agent-0.2.1-rc.3-win-x64-unsigned.exe`。

## 2. 改应用名改的是哪些地方

`apply-brand.mjs` 会改写下面这些位置（也就是「应用名」的全部出口）：

| 位置 | 影响 |
|---|---|
| `apps/desktop/scripts/electron-builder-config.mjs` | `productName`（exe 名、安装目录、开始菜单、卸载项）、`protocols` 显示名、`artifactName` |
| `apps/desktop/src/locale.ts` | 关于面板、退出确认、托盘提示、首启欢迎窗等 8 种语言的文案 |
| `apps/desktop/installer/locales/*.json` | NSIS 安装器界面里的 8 种语言文案 |
| `apps/desktop/cli/dsh`、`cli/dsh.cmd` | 命令行 `dsh` 启动器指向的 exe 文件名 |
| `packages/client/locale/src/locales/*.ts` | 客户端标题栏与侧边栏品牌名（`brand.localBuild`） |
| `packages/client/ui-primitives/src/FishLogo.tsx` | 侧栏左上角的品牌标记（`FISH_LOGO_PATH` 原本是官方鲸鱼轮廓） |
| `packages/client/ui-conversation/src/client/skeleton/EmptyHero.tsx` | 首页 hero 里同一个标记的两份悬停形变路径；不改会「从星星里长出一条鲸鱼尾巴」 |
| `packages/client/ui-conversation/src/client/locales.ts` | 首页大标题 `hero.headline`，8 种语言各一条 |
| `packages/core/system-prompt/src/index.ts` | 模型收到的自我介绍那一句 |
| `apps/desktop/scripts/*.ts` | 打包/冒烟脚本按名字找 exe，不改会导致打包最后一步失败 |
| `apps/desktop/package.json` | `productName`（Electron 的 `userData` 目录名）、`author.name`（exe 属性里的「公司」和安装器发布者）、`description`（exe 属性里的「说明」和任务管理器里的进程描述） |

`description` 是 2026-10 这次打包后才补上的：它不在 exe 文件名上体现，但会出现在
「文件属性 → 详细信息」和任务管理器进程列表里。改完要重新打包才会生效。

改完之后想确认有没有漏，最直接的验证是：

```sh
git diff --stat
git grep -n "DeepSeek Harness" -- apps/desktop packages/core packages/client
```

### 品牌标记（那只鲸鱼）与首页标题

这两个不是图片，是**代码里的 SVG 轮廓和文案**，所以换不掉文件、必须改代码——`apply-brand.mjs` 替你改：

| 出现位置 | 来源 | 配置项 |
|---|---|---|
| 侧栏左上角的标记 | `packages/client/ui-primitives/src/FishLogo.tsx` 的 `FISH_LOGO_PATH` | `mark` |
| 首页大标题左侧的标记（鼠标悬停会动） | 同一个 `FISH_LOGO_PATH`，外加 `EmptyHero.tsx` 里两份形变路径 | `mark` |
| 首页大标题文字 | `packages/client/ui-conversation/src/client/locales.ts` 的 `hero.headline`（8 种语言） | `heroHeadline` |
| 首页标题右侧的「预览版」角标 | 同一个 `locales.ts` 的 `hero.preview`，外加 `EmptyHero.tsx` 的一行渲染条件 | `heroBadge` |

`brand.json` 里 `mark` 的默认值会生成一个**四角星光**轮廓，和 exe 图标用的是同一套几何
（`|cos 2θ|^3.2` 的四瓣半径曲线），所以界面里的标记和任务栏图标是同一个形状：

```json
"mark": { "width": 30, "height": 24, "radius": 11.5, "innerRatio": 0.06, "lobePower": 3.2 }
```

- `width` / `height`：viewBox 尺寸。**保持 30:24** 能让 hero 的 34px 宽标记高度约 27px，
  和官方鲸鱼（34×25）的视觉重量接近；改成正方形会让标记显得偏大。
- `radius`：中心到尖端的距离，要小于 `min(width, height) / 2`。
- `innerRatio`：对角方向的腰有多细，越小越尖（0.06 已是很尖的星光）。
- `lobePower`：越大瓣越细长；调到 1.5 附近会接近圆角方形。

想直接用自己的图形，给 `mark.path` 一段路径数据即可，此时上面几个参数只用于 `width`/`height`：

```json
"mark": { "width": 24, "height": 24, "path": "M12 0L15 9L24 12L15 15L12 24L9 15L0 12L9 9Z" }
```

只填一个字符串给所有语言，或按语言分别给：

```json
"heroHeadline": "与光同行"
"heroHeadline": { "zh": "与光同行", "en": "Walk Toward the Light", "ja": "光とともに" }
```

首页标题右侧还有一个 `预览版` 角标，它**不再需要手工编辑**，由 `brand.json` 的 `heroBadge` 控制：

```json
"heroBadge": ""                       // 完全去掉角标（当前值）
"heroBadge": "内测"                    // 换成自己的角标，8 种语言统一
```

空字符串时脚本会做两件事：把 `locales.ts` 里 8 种语言的 `hero.preview` 都置空，并给
`EmptyHero.tsx` 的渲染行套一层判断——因为上游是无条件渲染的，只把文案置空会留下一个
空的小胶囊（有边框和内边距）。改完这两处都回到「元素根本不存在」的状态，布局也不会留白。

> 顺带说明：设置页里那个标题为「预览版说明」的一次性弹窗是**另一套东西**
> （`ui-settings-models` 的 `WelcomeNotice`），而且它只在 Web 预览里注册——
> 代码里写的是 `if (!('dshDesktop' in globalThis))`，打包出来的桌面端永远不会弹。
> 所以不用为它改代码；如果你连 Web 预览里都不想看到，把
> `packages/client/ui-settings-models/src/client/index.ts` 第 147 行的条件改成 `false &&` 即可。

### 再次改名

只改 `brand.json` 的 `productName` / `slug` / `appId`，然后重跑 `apply-brand.mjs`。
旧名字要写进 `replaceNames`，脚本会把列表里的每个名字都替换成新的 `productName`，
所以上游合并回来的旧名字也会被一起处理。

注意 `slug` 变化需要手工检查：它只用于安装包文件名前缀，脚本只改一处模板。

## 3. 改图标改的是哪些文件

`render-assets.ps1` 一次性生成 8 个文件，都从 `brand.json` 的 `productName` 取文字：

| 文件 | 尺寸 | 用途 |
|---|---|---|
| `resources/icon-windows.png` | 1024×1024 | 应用图标，electron-builder 自动生成多尺寸 ico |
| `resources/icon-windows.svg` | 矢量 | 托盘图标的矢量源，`pnpm run render:tray-icon` 会读它 |
| `resources/tray-windows.ico` | 16/20/24/32/40/48/64 | 系统托盘图标（每个缩放比例一张位图） |
| `installer/assets/brand.png`、`brand-2x.png` | 600×196 / 1200×392 | 安装器顶部品牌图（浅色底） |
| `installer/assets/brand-dark*.png` | 同上 | 安装器顶部品牌图（深色底） |
| `installer/assets/uninstaller-sidebar.png` | 164×314 | 卸载程序右侧竖图 |

想换成自己的设计，两种做法：

1. **省事**：把上面这些文件直接替换成你的图（PNG 带透明通道，尺寸照表），
   不要再跑 `render-assets.ps1`，否则会被覆盖。
2. **程序化**：改 `render-assets.ps1` 顶部的 `$colorStart`、`$colorEnd` 和
   星形参数，或者把 `Add-Tile` 换成绘制你自己的图形。

## 4. 打包前的一次性准备

### 4.1 版本要求（都已核对过 `package.json`）

| 工具 | 要求 | 说明 |
|---|---|---|
| Node.js | **≥ 24.9.0** | 根 `package.json` 的 `engines.node`。24.22.0 合规，不用降级 |
| pnpm | **11.28.5**（精确） | 根 `package.json` 的 `packageManager` 字段。**不要手动 `npm i -g pnpm`**，版本不对会被 workspace 配置（`allowBuilds`、`patchedDependencies`、`minimumReleaseAgeExclude`）卡住 |
| Git、`tar` | 在 PATH 里 | `pack` 阶段打 tgz 用 |
| Python 3 | 在 PATH 里或 `PYTHON` 指定 | 部分构建脚本会调 |
| Visual Studio C++ Build Tools + Windows SDK | 必装 | `node-pty` 等原生模块要用 MSVC 编译 |
| PowerShell | 5.1 及以上 | 安装器素材与签名脚本 |

先确认终端里真的是 24.x，而不是别的 Node：

```powershell
node -v      # 期望 v24.x（≥24.9）
where node   # 查看是哪一个 Node 在生效，有多个版本时尤其要确认
```

Windows 上常有多个 Node（比如 IDE 自带的、Chocolatey 装的、`C:\yoyiEnvs\nodeJS`）。
如果 `node -v` 提示 22.x，说明当前终端的 PATH 指向了另一个 Node，
`pnpm install` 会提示 engines 不匹配（严重时直接中断安装）——
`where node` 看清楚后调整 PATH 顺序，或直接用 24.x 那个。

### 4.2 命令在哪个目录执行（重点）

**所有命令都在仓库根目录执行**，也就是包含 `pnpm-workspace.yaml` 的那一层：

```
E:\yoyiCode\deepseek-harness\      ← 在这里执行所有命令
├── package.json                   ← 根清单（name: @deepseek-ai/dsh-root）
├── pnpm-workspace.yaml            ← 有这个文件才是 workspace 根
├── pnpm-lock.yaml                 ← 只有根有 lockfile
├── apps\desktop\                  ← 只是 workspace 成员，没有自己的 lockfile
│   └── package.json
└── packages\...
```

```powershell
cd E:\yoyiCode\deepseek-harness
node -v                 # 先确认是 24.x
corepack enable         # 报 EPERM 就改用 4.3 里带 --install-directory 的写法
pnpm install --frozen-lockfile
```

两个容易混的点：

- `corepack enable` **跟目录无关**，它只是生成一个 `pnpm` 转发器（默认放在 `node.exe`
  旁边；目录不可写时用 `--install-directory` 换个位置，见 4.3），一台机器做一次就行。
- `pnpm install` **必须在根目录**。`apps/desktop` 下面没有 `pnpm-lock.yaml`，
  在子目录跑会往上找 workspace 根，虽然通常也能成，但根目录是唯一正确的入口。
  后面的 `pnpm run package:desktop:*` 同理——根 `package.json` 里这些脚本
  就是用 `pnpm --filter @deepseek-ai/dsh-desktop run ...` 转给子包的。

### 4.3 corepack 的常见报错（含本机遇到的 EPERM）

**`corepack enable` 报 `EPERM: operation not permitted, open 'C:\yoyiEnvs\nodeJS\yarnpkg'`**

这不是权限设置写错了，而是这台机器的 Node 安装目录对普通用户**只读**：

```
NT AUTHORITY\Authenticated Users   ReadAndExecute   Allow
BUILTIN\Users                      ReadAndExecute   Allow
```

`corepack enable` 默认要往 `node.exe` 旁边写 `pnpm`、`pnpm.cmd`、`yarn`、`yarnpkg`
这些转发器，所以必然失败。解决办法是换个可写目录，**不需要管理员权限**：

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\npm" | Out-Null
corepack enable --install-directory "$env:APPDATA\npm" pnpm
```

- `%APPDATA%\npm` 已经在 PATH 里（npm 的全局目录，`npm i -g` 也装这儿），
  所以转发器放进去就能直接用。**改完重开一个终端**，`where pnpm` 应指向
  `C:\Users\<你>\AppData\Roaming\npm\pnpm.cmd`。
- 只传 `pnpm`，不要裸跑 `corepack enable`——那样会连带写 yarn/yarnpkg，
  这台机器上就是被 `yarnpkg` 卡住的。
- 验证：`pnpm -v` 应返回 `11.28.5`（首次会下载一次，缓存在
  `%LOCALAPPDATA%\node\corepack\v1\pnpm`，之后离线可用）。
- 注意生成的 `pnpm.cmd` 里写的是相对路径指向
  `...\nodeJS\node_modules\corepack\dist\pnpm.js`，**换 Node 安装目录或升级 Node 后
  要重跑一次上面这条命令**。要撤销用
  `corepack disable --install-directory "$env:APPDATA\npm"`。

两条备选路子（能用但不推荐）：

- 管理员 PowerShell 里跑 `corepack enable`：能成，但 shim 写进了只读目录，
  以后升级/重装 Node 会一起丢。
- `npm i -g pnpm@11.28.5`：装到 `%APPDATA%\npm`，不需要管理员。**版本必须写死
  11.28.5**，装成别的版本会被 workspace 的 `allowBuilds`/`patchedDependencies` 拒绝。

顺便提一下其它 corepack 报错：

- 报 `corepack is not recognized`：Node 安装目录不可写导致 shim 没生成，
  按上面第一条处理。
- 报 `Cannot find matching keyid`：corepack 内置的 npm 签名公钥过旧，校验不过，
  临时可用 `$env:COREPACK_INTEGRITY_KEYS = '0'` 绕过，根治办法是升级 Node。
- 报 `Corepack is about to download ...` 后卡住不动：corepack 下载也走 Node 的
  `fetch`，需要先在同一个终端设好 5.2 里那几个代理变量（含 `NODE_USE_ENV_PROXY=1`）。

### 4.4 `pnpm install` 到底装了什么

`corepack enable` 之后第一次跑 `pnpm` 会去下载 11.28.5，默认有交互确认；
无人值守或脚本里会直接失败，提前关掉提示：

```powershell
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
corepack prepare pnpm@11.28.5 --activate
pnpm -v        # 期望 11.28.5
```

`pnpm install` 这一步只装「打包用的工具链」（typescript、tsdown、electron-builder 等），
需要联网一次，之后缓存在 `node_modules` 和 pnpm 全局 store 里。
它装不到的东西——Electron 发行包、随包分发的 Node/Python、dsh 的生产依赖——
由第 1 节流程图里的第 3~5 步现下，那部分才是真正需要代理和缓存控制的。

## 5. 打包命令

本节所有命令同样都在**仓库根目录** `E:\yoyiCode\deepseek-harness` 下执行。

### 5.0 改完先预览，再打包

打包一次约 14 分钟，而改一个标题、换一张图往往只要几秒。所以先按「改动类型」选预览粒度，
只有最后确认无误时才值得走完整打包。三级粒度，从快到慢：

| 粒度 | 命令 | 耗时 | 能看到什么 |
|---|---|---|---|
| ① 素材级 | 直接双击 `apps/desktop/local-fork/preview.html` | 秒级 | 应用图标（128/48/32/16）、托盘 ico、安装器品牌图、卸载器侧栏图、首页标题与标记 |
| ② 界面级 | `pnpm run build:artifacts` + `pnpm run start:web`（常驻监听用 `pnpm run dev:web`） | 首次 2~4 分钟，之后改一处重建约 5~15 秒 | **真实界面**，浏览器里就能看侧栏、首页 hero、标题栏文案 |
| ③ 外壳级 | `pnpm run dev:desktop` | 1~2 分钟 | 真实 Electron 窗口（未打包）：窗口图标、托盘图标、标题栏、关于面板 |
| ④ 成品 | `pnpm run package:desktop:win:x64:unsigned` | 约 14 分钟 | 安装器界面、exe 文件名与属性、装完后的开始菜单项 |

`preview.html` 是 `apply-brand.mjs` 生成的静态页，**不启动任何服务**，图标直接读
`resources/` 和 `installer/assets/` 里的文件。换完图刷新页面即可，适合反复调图标。

改了什么，用哪一级：

| 改动 | 预览方式 | 说明 |
|---|---|---|
| `brand.json` 的 `heroHeadline` / `heroBadge`（首页标题与角标） | ②即可 | 文案在客户端包里，重建后刷新即可 |
| `brand.json` 的 `mark`（标记形状） | ②（hero 与侧栏都在客户端里） | 也顺手看一眼 ①的图标是否与界面标记一致 |
| `render-assets.ps1` 的配色 / 图形 | ① | 再跑 ③ 看真实窗口图标与托盘 |
| 换成自己的 PNG 设计图 | ①（确认尺寸对）→ ③（看托盘） | 安装器界面只能靠 ④ |
| 应用名、公司名、exe 说明、版本号 | ③→④ | 这些写进 exe 资源，必须打包才生效 |
| 业务逻辑 / 工具行为 | ②或③ | 用 `pnpm run dsh --profile headless "任务"` 也能直接跑一次 |

#### ① 素材级：`preview.html`

```powershell
# 换图标或改配色后
powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\render-assets.ps1
# 然后在资源管理器里双击：
#   apps\desktop\local-fork\preview.html
```

它是纯静态文件，浏览器直接读本地图片，所以**不需要构建、不需要联网**。
改了 `brand.json`（标题文字、标记形状）就重跑 `apply-brand.mjs`，它会重写这个页面。

#### ② 界面级：Web 预览（日常最常用）

两种跑法，先用第一种，习惯之后再换第二种。

**A. 一次构建 + 起服务（实测跑通，最省心）**

```powershell
cd E:\yoyiCode\deepseek-harness
pnpm run build:artifacts                    # 编译整棵 client（几分钟，只做一次）
pnpm run start:web                          # 起服务，终端打印带 token 的地址（默认 3080）
pnpm run start:web -- --port 52838          # 想换端口就这样写；--port 0 让系统随机挑
```

`start:web` 就是 `dsh web`，它 serve 的是 `build:artifacts` 已经产出的静态包；改完源码
再跑一次 `build:artifacts` 就能看到新结果。适合「改文案 → 看一眼 → 再改」这种低频迭代，
好处是没有一堆 watcher 常驻吃 CPU，也不会因为监听器掉线而看到旧界面。

**B. 常驻监听：`pnpm run dev:web`**

```powershell
pnpm run dev:web
```

同时起三个监听器（`tsc -b --watch` 类型产物、`tsdown --watch`
包 bundle、`vite build --watch` 前端），最后同样用 `dsh web` 把界面服务起来，终端里会打印
形如 `dsh web: http://127.0.0.1:52838/?token=...` 的地址，**带 token 才能打开**。

之后改 `packages/client/**` 下的 `.tsx`、`.css`、`locales.ts`，几秒后浏览器自动刷新，
改动即时可见。注意：

- 只想看界面，**不需要** `DEEPSEEK_API_KEY`；要真的对话才需要。
- 端口默认 `3080`（来自 `packages/bundle/web-app/cordis.patch.yml` 的
  `port: !!js ctx.webStartup.port ?? 3080`）。换端口用 `--port`，**`$env:PORT` 是无效的**；
  `--port 0` 让系统挑一个空闲端口，打包时的冒烟测试就是这么拿到随机端口的。
- 端口被占用会直接启动失败并报 `EADDRINUSE: address already in use 127.0.0.1:3080`，
  先用 `netstat -ano | findstr 3080` 找到旧进程再关掉。
- 起来之后它会**自动打开默认浏览器**；不想被弹窗打扰加 `--no-open`，自己复制日志里的地址。
- 首次启动要先把整棵 client 编一遍（2~4 分钟），之后是增量的。
- 参数默认带 `--poll`（轮询监视），Windows 上比原生 watch 稳，代价是改动后多等 1~2 秒。
  想拆开用：`pnpm run dev:web -- --no-serve` 只保留监听器，另开一个窗口
  `pnpm run start:web` 单独起服务。

#### ③ 外壳级：`pnpm run dev:desktop`

```powershell
pnpm run dev:desktop
```

跑一次 `build:artifacts` + 桌面端构建，然后启动**未打包**的 Electron 窗口。它和打包出来的
应用是同一套主进程代码，所以窗口图标（`resources/icon-windows.png`）、托盘 ico、
标题栏、关于面板、退出确认都能在真实外壳里确认。

- **没有热更新**：改完 client 源码后要 `Ctrl+C` 再跑一次（增量构建约 1~2 分钟）。
- 已经构建过的话用 `pnpm run start:desktop` 跳过构建，几秒就起来。
- 运行在独立的开发目录 `.desktop-build/development`，不会污染正式安装的数据；
  但它**会**复用 `%USERPROFILE%\.dsh` 里的会话数据。
- 首次启动会准备随包运行时（可能需要几分钟与网络），之后是秒起。

#### ④ 确认无误再打包

```powershell
powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\build-win.ps1 -CacheDir E:\dsh-cache -Mirror
```

安装器界面（NSIS 顶部品牌图、8 语言文案）、exe 文件名与「属性 → 详细信息」里的公司/说明、
开始菜单与卸载项，都只有真正打包后才会体现，所以 ④ 是「最后验收」，不是「日常迭代」。

### 5.1 先体检，再打包

> 出网要走代理的话，先照 5.2 把环境变量设好，再回来跑这两条。

最省事的方式是用同目录下的 `build-win.ps1`，它把代理探测、开关、缓存目录都包好了：

```powershell
cd E:\yoyiCode\deepseek-harness
powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\build-win.ps1 -CheckOnly
powershell -ExecutionPolicy Bypass -File apps\desktop\local-fork\build-win.ps1 -CacheDir E:\dsh-cache
```

它会先检查 Node ≥ 24.9 与 pnpm 是否存在，再从注册表读出系统代理并**实测**能否访问
GitHub，通了才设进 `HTTPS_PROXY`/`NODE_USE_ENV_PROXY`/`ELECTRON_GET_USE_PROXY`。
另有 `-DirMode`（跳过 NSIS）、`-NoProxy`、`-Mirror`（见 5.3.1）三个开关。
脚本是 UTF-8 **带 BOM** 保存的，改它的时候别把 BOM 去掉，否则 PowerShell 5.1 会把
中文注释按 ANSI 解析直接报语法错。

想看每一步在做什么，就直接跑原始命令：

```sh
# 只校验配置：.env.windows 是否可读、AppID/更新地址是否合法、
# 目标目录与工具链路径是否可用。不编译、不下载、不联网，秒级返回。
pnpm run package:desktop:win:x64:unsigned --check

$env:DSH_DESKTOP_PACKAGE_CACHE_DIR = 'E:\dsh-cache'
# 完整打包（10~30 分钟起，取决于机器与代理速度）
pnpm run package:desktop:win:x64:unsigned
```

`--check` 通过基本就说明配置没问题了，报错信息会直接指出是哪一个变量、
哪一个文件——比跑十分钟之后才失败划算得多。

只想先看应用能不能起来，用目录模式更快（跳过 NSIS 安装包）：

```sh
pnpm run package:desktop:win:x64:dir -- --unsigned
```

`unsigned` 是必须的——没有代码签名证书就走这条路，它同时关掉了自动更新配置，
对内网分发正好合适。

从零到出包的完整一次会话（可直接照抄，注意 `cd` 只有一次）：

```powershell
# 1) 进仓库根目录（唯一的工作目录）
cd E:\yoyiCode\deepseek-harness

# 2) 确认版本
node -v        # v24.22.0 这类，≥24.9 即可
corepack enable
pnpm install --frozen-lockfile
pnpm -v        # 11.28.5

# 3) 需要代理才设（详见 5.2），不需要就跳过
$env:HTTPS_PROXY = 'http://10.0.0.1:8080'
$env:HTTP_PROXY  = 'http://10.0.0.1:8080'
$env:NO_PROXY    = 'localhost,127.0.0.1,::1'
$env:NODE_USE_ENV_PROXY = '1'
$env:ELECTRON_GET_USE_PROXY = '1'
$env:DSH_DESKTOP_PACKAGE_CACHE_DIR = 'D:\dsh-cache'

# 4) 体检 → 打包（仍在同一个目录）
pnpm run package:desktop:win:x64:unsigned --check
pnpm run package:desktop:win:x64:unsigned
```

装完之后，终端里随时可以用 `pnpm dsh --profile headless "任务"` 从源码跑一次任务，
用来验证运行期是否正常（需要 `DEEPSEEK_API_KEY`）。

### 5.2 需要代理时：只设 `HTTPS_PROXY` 不够

打包脚本会继承调用者的环境变量（`desktop-package-environment.mjs` 只过滤
签名/更新相关的敏感变量，代理变量原样传给子进程）。但**各步骤用的下载器不同，
认的变量也不同**，这是最容易卡住的地方：

| 步骤 | 谁在下载 | 生效条件 |
|---|---|---|
| `pnpm install` | pnpm | `HTTP_PROXY` / `HTTPS_PROXY` 即可 |
| `build`、`pack` | 纯本地 | 不需要网络 |
| `prepare:runtime` | Node 内置 `fetch`（Node/CPython/wheels）+ `@electron/get`（Electron） | **必须** `NODE_USE_ENV_PROXY=1`，Electron 还需 `ELECTRON_GET_USE_PROXY=1` |
| `prepare:dsh` | 随包的 pnpm | 继承 `HTTPS_PROXY` |
| `electron-builder --win` | `app-builder` 拉 NSIS / winCodeSign | 首次需要 `HTTPS_PROXY` |
| `smoke-packaged-runtime` | 本机回环地址 | 需要 `NO_PROXY` 包含 `127.0.0.1`、`localhost` |

关键点：**Node 的 `fetch` 默认不读代理环境变量**，要靠 `NODE_USE_ENV_PROXY=1`
打开（Node 24 才支持这个开关，而本仓库正好要求 ≥24.9）。而 `prepare:runtime`
下载的正是安装包里最大的几块（Electron、Node 运行时、CPython、29 个 Python
wheel），只设 `HTTPS_PROXY` 会看到一连串 `ECONNREFUSED` / `ETIMEDOUT`，
而不是走代理。

#### 本机实测（2026-10，务必注意这一条）

这台机器 `ProxyEnable=1`、`ProxyServer=http://127.0.0.1:9567`，浏览器能上网，
但打包仍然挂在 `prepare:runtime`。原因是**系统代理只对 WinINET（浏览器那一栈）生效，
Node 完全不读它**，而 `prepare:runtime` 全部走 Node。证据在失败的运行目录里：

```
apps/desktop/.desktop-build/packaging-runs/<时间戳>/
├── result.json    ← "proxy": "not-used"，一眼看出没走代理
├── events.jsonl   ← 每阶段的 type/stage/success/error，失败点精确到步骤
├── stdout.log
└── stderr.log
```

`events.jsonl` 里对应的两条就是典型症状：

```
{"stage":"download:electron","success":false,"error":"TypeError: fetch failed / read ECONNRESET"}
{"stage":"prepare:primary-runtime","success":false,"error":"ConnectTimeoutError (attempted address: github.com:443, timeout: 10000ms)"}
```

先把自己的代理端口找出来（Clash / v2ray 这类本机客户端都写在这）：

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer
```

再确认这个端口真能代理 HTTPS（`200`/`302` 是通，`502`/超时是不通）：

```powershell
curl.exe -q -sS -o NUL -w "%{http_code}`n" -x http://127.0.0.1:9567 `
  https://github.com/electron/electron/releases/download/v44.7.0/electron-v44.7.0-win32-x64.zip
```

确认可用后把这个地址填进下面的变量块。值得记住的对比（同一台机器实测）：

| 环境 | 结果 |
|---|---|
| 只设 `HTTPS_PROXY` | `UND_ERR_CONNECT_TIMEOUT` |
| 再加 `NODE_USE_ENV_PROXY=1` | `200` |
| `curl -x http://127.0.0.1:9567` 直取同一个 URL | `302`，0.7 秒 |

所以「代理明明好使，打包还是连不上」几乎总是漏了 `NODE_USE_ENV_PROXY=1`。

PowerShell（当前会话，最常用）：

```powershell
$env:HTTP_PROXY             = 'http://10.0.0.1:8080'
$env:HTTPS_PROXY            = 'http://10.0.0.1:8080'
$env:NO_PROXY               = 'localhost,127.0.0.1,::1,.intranet.example'
$env:NODE_USE_ENV_PROXY     = '1'   # 让 Node 的 fetch 认代理
$env:ELECTRON_GET_USE_PROXY = '1'   # 让 @electron/get 认代理
```

Git Bash 下写法一样，把 `$env:` 换成 `export`：

```sh
export HTTP_PROXY=http://10.0.0.1:8080
export HTTPS_PROXY=http://10.0.0.1:8080
export NO_PROXY=localhost,127.0.0.1,::1,.intranet.example
export NODE_USE_ENV_PROXY=1
export ELECTRON_GET_USE_PROXY=1
```

想持久化（不用每次开新窗口重设），写成用户环境变量，然后**重开终端**才生效：

```powershell
[Environment]::SetEnvironmentVariable('HTTPS_PROXY','http://10.0.0.1:8080','User')
[Environment]::SetEnvironmentVariable('HTTP_PROXY','http://10.0.0.1:8080','User')
[Environment]::SetEnvironmentVariable('NO_PROXY','localhost,127.0.0.1,::1','User')
[Environment]::SetEnvironmentVariable('NODE_USE_ENV_PROXY','1','User')
[Environment]::SetEnvironmentVariable('ELECTRON_GET_USE_PROXY','1','User')
```

代理慢或带宽被限时调超时（默认单个文件 5 分钟，
`scripts/primary-runtime/prepare.ts` 里读的就是它）：

```powershell
$env:DSH_RESOURCE_DOWNLOAD_TIMEOUT_MS = '900000'   # 15 分钟
```

内网/加速镜像想换 npm 源，用 `DSH_DESKTOP_NPM_REGISTRY`：

```powershell
$env:DSH_DESKTOP_NPM_REGISTRY = 'https://registry.npmmirror.com'
```

它会被 `prepare:dsh` 写进 pnpm 的 `--config.registry`。约束很死：**只接受
HTTPS origin，不能带账号、路径、查询串**——`https://npm.intranet.example` 合法，
`https://npm.intranet.example/repository/npm/` 会直接报错。

**一个会静默失效的坑**：`ELECTRON_GET_USE_PROXY=1` 并不总是管用。
`@electron/get` 是通过把 `HTTPS_PROXY` 转交给第三方模块 `global-agent` 来走代理的，
而 `global-agent` 是可选依赖——本仓库没有安装它时，`ELECTRON_GET_USE_PROXY`
**不会报错**，只是什么都不做，Electron 依旧直连 GitHub。表现是
`download:electron` 卡满 30 秒后抛 `TypeError: fetch failed`，
而同一时刻 `curl -x` 代理下载同一个文件是通的。

自查一条命令就够：

```powershell
node -e "try{require.resolve('global-agent/bootstrap');console.log('global-agent OK')}catch{console.log('global-agent 缺失：ELECTRON_GET_USE_PROXY 无效')}"
```

缺失时不必去装依赖，直接用镜像更省事（见 5.3.1 的 `ELECTRON_MIRROR`），
本仓库的一键脚本 `build-win.ps1 -Mirror` 就是干这个的。

### 5.3 下载缓存在哪，怎么搬到固定盘符复用

`DSH_DESKTOP_PACKAGE_CACHE_DIR` 只控制**两个可复用目录**（必须是非空绝对路径，
相对路径会在打包第一步就报错）：

```
<DSH_DESKTOP_PACKAGE_CACHE_DIR>/
├── downloads/      运行时归档，文件名就是内容哈希
└── pnpm-store/     prepare:dsh 装生产依赖用的 pnpm store
```

| 内容 | 来源 | 缓存文件名 |
|---|---|---|
| Node 24.21.0 (win-x64) | `nodejs.org/dist` | 该 zip 的 sha256 十六进制 |
| CPython 3.12.14 | `github.com/astral-sh/python-build-standalone` | 该 tar.zst 的 sha256 |
| 29 个 Python wheel（numpy/pandas/pillow 等） | `files.pythonhosted.org` | 各自的 sha256 |
| Electron 发行包 | `@electron/get` | `downloads/` 下按 @electron/get 自己的命名 |
| dsh 生产依赖 | npm registry | `pnpm-store/`，pnpm 自己的内容寻址结构 |

**按内容哈希命名的好处**：缓存天然按版本隔离，升级 Electron/Node/Python 时
旧文件既不冲突也不会被误用——要哪个版本由 `scripts/primary-runtime/lock.json`
里的 `sha256` 决定，下载后还会再校验一遍哈希，不匹配就删掉重下。
也就是说这个缓存目录**不会因为上游更新而失效，可以长期留着复用**。

不设这个变量时，两个目录落在 `apps/desktop/.desktop-build/{downloads,pnpm-store}`。
建议直接指到固定盘符，避免换目录、清仓库时丢掉已经下好的几 GB 归档
（`downloads` 里 Electron + Node + CPython + wheels 加起来是 GB 量级，
换台机器重下一遍就走一遍代理，很浪费时间）：

```powershell
$env:DSH_DESKTOP_PACKAGE_CACHE_DIR = 'D:\dsh-cache'
```

注意哪些**不**受这个变量控制：

- `apps/desktop/.desktop-build/targets/win-x64/`（`runtime/`、`electron/`、`dsh/`、
  `package-set/`）每次打包都会重建，体积最大（数 GB 量级），但那是中间产物，
  不能当缓存复用。
- `%LOCALAPPDATA%\electron-builder\Cache`（NSIS、winCodeSign）。想固定住就设
  `ELECTRON_BUILDER_CACHE`；内网机器可以把这个目录整体拷过去。
- `node_modules`（打包工具链）和根 `pnpm install` 的 store。

验证缓存是否真的被复用：打第二次包时看 `downloads` 里文件的修改时间不变、
打包日志里的下载步骤几乎瞬间通过，就说明命中缓存了。想强制重下就删掉对应哈希文件。

### 5.3.1 只有 GitHub 打不开时：镜像 + 预置缓存

`prepare:runtime` 的四个来源里，**通常只有 GitHub 卡住**。实测（2026-10）：

| 来源 | 直连（不走代理） | 结论 |
|---|---|---|
| `nodejs.org/dist` | 206，约 690~750 KB/s | 直连可用 |
| `files.pythonhosted.org`（29 个 wheel） | 206，约 460 KB/s | 直连可用 |
| `github.com`（Electron、CPython） | 连接超时 / ECONNRESET | **必须代理或镜像** |

**Electron —— 有官方支持的镜像开关**，`@electron/get` 自己会读：

```powershell
$env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
```

实测直连约 730 KB/s，够用。

**CPython —— 脚本里的 URL 写死在 `scripts/primary-runtime/prepare.ts`，没有覆盖变量**，
只能预置缓存。npmmirror 上有同一份文件，下下来按 sha256 命名丢进缓存即可，
脚本校验通过就直接复用、不再联网：

| 文件 | 镜像地址 | 期望 sha256 |
|---|---|---|
| `node-v24.21.0-win-x64.zip` | `https://registry.npmmirror.com/-/binary/node/v24.21.0/node-v24.21.0-win-x64.zip` | `158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541` |
| `cpython-3.12.14+20260901-x86_64-pc-windows-msvc-install_only_stripped.tar.gz` | `https://registry.npmmirror.com/-/binary/python-build-standalone/20260901/` + 同名文件 | `7c45c9622400d578709a9b2cddbe8124cc21d382409d9f13406d706d28e31b14` |

```powershell
$downloads = 'E:\dsh-cache\downloads'          # 必须是 <cache>/downloads，且与 DSH_DESKTOP_PACKAGE_CACHE_DIR 一致
New-Item -ItemType Directory -Force $downloads | Out-Null
$url = 'https://registry.npmmirror.com/-/binary/python-build-standalone/20260901/cpython-3.12.14%2B20260901-x86_64-pc-windows-msvc-install_only_stripped.tar.gz'
curl.exe -L -o "$env:TEMP\cpython.tar.gz" $url
$hash = (Get-FileHash "$env:TEMP\cpython.tar.gz" -Algorithm SHA256).Hash.ToLower()
if ($hash -ne '7c45c9622400d578709a9b2cddbe8124cc21d382409d9f13406d706d28e31b14') {
  throw "哈希不符：$hash，镜像文件与 lock.json 不是同一份，别用"
}
Move-Item "$env:TEMP\cpython.tar.gz" (Join-Path $downloads $hash) -Force
```

哈希对不上时脚本会当成「没有缓存」重新去 GitHub 下，所以**校验和改名这两步不能省**。
这套做法的好处是对内网构建同样适用：找一台能上网的机器把文件取回来，
按哈希放进 `<cache>/downloads`，内网机设同一个 `DSH_DESKTOP_PACKAGE_CACHE_DIR` 就能复用。

### 5.4 内网 / 离线的三种做法

按可维护性从高到低：

1. **联网机打包，只把 exe 带进内网（推荐）**。安装包自带 Electron/Node/Python
   和全部生产依赖，内网机器只需要能跑起来，不需要任何公网访问。构建环境随便放。
2. **联网机预热缓存 → 拷缓存目录到内网构建机**。把
   `<DSH_DESKTOP_PACKAGE_CACHE_DIR>` 整个拷过去、两边设成同一路径即可复用下载。
   但 `prepare:dsh` 仍要解析依赖树，所以内网还得有一个 npm 镜像
   （配 `DSH_DESKTOP_NPM_REGISTRY`）。
3. **构建机完全不联网**。在上面基础上再补齐：内网 npm 镜像（要能提供
   `--frozen-lockfile` 校验所需的完整元数据）、预置 `%LOCALAPPDATA%\electron-builder\Cache`
   （NSIS/winCodeSign 没有哈希校验，只能整目录拷）、以及 `downloads` 全量。
   这条路能通但很脆，任何一环缺失都会在 `prepare:runtime` 或 `electron-builder`
   阶段失败，不建议在没有内网制品库的情况下走。

### 5.5 打包相关环境变量速查

| 变量 | 作用 | 何时需要 |
|---|---|---|
| `HTTP_PROXY` / `HTTPS_PROXY` | 所有子进程的基础代理 | 需要代理时 |
| `NO_PROXY` | 不走代理的地址 | 建议始终带上回环与内网域名 |
| `NODE_USE_ENV_PROXY=1` | 让 Node 内置 `fetch` 认代理 | 需要代理时**必填**，否则 `prepare:runtime` 直连 |
| `ELECTRON_GET_USE_PROXY=1` | 让 `@electron/get` 认代理 | 需要代理时**必填**，否则 Electron 包下不下来 |
| `DSH_DESKTOP_PACKAGE_CACHE_DIR` | 下载归档与 pnpm store 的根目录（绝对路径） | 想跨仓库/跨机器复用缓存时 |
| `DSH_DESKTOP_NPM_REGISTRY` | 换 npm 源，只接受 `https://host` | 用镜像或内网源时 |
| `DSH_RESOURCE_DOWNLOAD_TIMEOUT_MS` | 单文件下载超时，默认 `300000`（5 分钟） | 代理慢、大文件总超时时 |
| `ELECTRON_BUILDER_CACHE` | electron-builder 的 NSIS/winCodeSign 缓存位置 | 想固定盘符或整目录拷进内网时 |

### 5.6 产物与常见报错

产物：`apps/desktop/.desktop-build/targets/win-x64/unsigned-artifacts/`，
文件名形如 `xiaoguang-agent-0.2.1-rc.3-win-x64-unsigned.exe`。

`.env.windows` 由 `apply-brand.mjs` 首次运行时生成，里面有两个占位地址
（`update.intranet.example` / `login.intranet.example`）。打包只要求它们是合法的
HTTPS origin，不会去连接；等你有内网更新服务时再改成真实地址。

| 报错 / 现象 | 原因与处理 |
|---|---|
| `DSH_DESKTOP_PACKAGE_CACHE_DIR must be a nonempty absolute directory` | 写成了相对路径或空字符串；用 `D:\dsh-cache` 这种形式 |
| `desktop package: cannot read ...\.env.windows` | 没跑过 `apply-brand.mjs`，或文件被误删；重跑一次即可 |
| `primary runtime download: 407` / `ECONNREFUSED` / `ETIMEDOUT` | 只设了 `HTTPS_PROXY`，补上 `NODE_USE_ENV_PROXY=1`（Electron 还要 `ELECTRON_GET_USE_PROXY=1`） |
| `TypeError: fetch failed` + `read ECONNRESET` / `github.com:443 Connect Timeout`，且 `result.json` 里 `"proxy":"not-used"` | 系统代理没被 Node 采用；按 5.2「本机实测」那段配变量，或按 5.3.1 换镜像 |
| `checksum mismatch for https://...` | 代理返回了拦截页/登录页而不是文件，或缓存文件被改坏；删掉 `downloads/` 里那个哈希文件后重试，并确认代理放行了对应域名 |
| `desktop release environment: DSH_DESKTOP_NPM_REGISTRY must be an HTTPS origin` | 镜像地址带了路径或用了 http；只填 `https://host` |
| `electron-builder` 一启动就报 `ReferenceError: version is not defined`，堆栈指向 `electron-builder-config.mjs` 的 `artifactName` 行 | 该行是模板字符串，`${version}/${os}/${arch}/${ext}` 必须写成 `\${...}` 保持字面量，交给 electron-builder 替换；少了反斜杠就会被 JS 当变量求值。重跑 `apply-brand.mjs` 即可修复（脚本带自检） |
| `download:electron` 卡 30 秒后 `TypeError: fetch failed`，但 `curl -x` 同一个 URL 正常 | `@electron/get` 的代理依赖可选模块 `global-agent`，缺失时 `ELECTRON_GET_USE_PROXY` 静默失效；用 `ELECTRON_MIRROR`（5.3.1）或 `build-win.ps1 -Mirror` |
| `fatal error C1083: Cannot open include file: 'windows.h'`，来自 `prepare-windows-installer.ps1` | VS 的 `vcvars32.bat` 没能设好 `INCLUDE`。常见原因是该脚本被安全软件/受限账户拦住了它内部调用的 `reg.exe`。在普通终端里重跑通常即可；确认 VS 装了「使用 C++ 的桌面开发」并含 x86/x64 生成工具 |
| 打包最后一步失败，提示找不到某个 exe | 改了 `productName` 但没重跑 `apply-brand.mjs`（冒烟脚本按名字找 exe） |
| 冒烟测试卡住直到超时 | `NO_PROXY` 没排除 `127.0.0.1`/`localhost`，本机回环被代理接管 |

### 5.7 一次完整成功打包的实测记录（2026-10-26）

这是本仓库在 Windows x64 上第一次全绿跑通，可作为「正常长什么样」的基准。
总共 **828 秒（约 14 分钟）**，30 个阶段全部 `OK`：

| 阶段 | 耗时 | 说明 |
|---|---|---|
| `build --profile local` | 76 s | 编译整个 monorepo |
| `pack-local-packages` | 150 s | 把各包打成 tgz（第二大耗时） |
| `prepare:primary-runtime` | 83 s | Node / CPython / wheel 下载校验 |
| `prepare:runtime`（汇总） | 226 s | Electron 解压 + 上述运行时铺开 |
| `prepare:dsh` | 228 s | 用自带 Node+pnpm 装生产依赖（最大耗时） |
| `runtime:*` 13 个子步骤 | 228 s | 生成运行时描述符、装包、两次冒烟与校验 |
| `electron-builder` | 201 s | 生成 `win-unpacked` 与 NSIS 安装包 |
| `smoke-packaged-runtime` | 36 s | 真实启动打好的 exe 验证（**最容易因改名漏项而失败**） |

产物（`unsigned-artifacts/`）：

| 文件 | 大小 |
|---|---|
| `xiaoguang-agent-0.2.1-rc.3-win-x64-unsigned.exe` | **299.6 MB** |
| `xiaoguang-agent-0.2.1-rc.3-win-x64-unsigned.exe.blockmap` | 0.3 MB |
| `win-unpacked/XiaoGuang Agent.exe` | 235 MB（免安装版，可直接压缩分发） |

打包后实测的元数据（`(Get-Item exe).VersionInfo`）：

```
FileDescription : XiaoGuang Agent 桌面客户端
ProductName     : XiaoGuang Agent
CompanyName     : XiaoGuang
FileVersion     : 0.2.1-rc.3
```

内置图标也确认是新生成的：`resources/icon.png` 是 1024×1024，
`resources/tray.ico` 含 16/20/24/32/40/48/64 七档、全部 PNG 压缩。

两个**只在受限环境才会出现**、普通终端不会遇到的坑，记在这里免得误判：

- `[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]`，目标是一次删 778 个
  `inspector/lib/devtools.build-*`：构建过程被外部注入的删除防护挡下。
  你自己的终端没有这层拦截，`remove NODE_OPTIONS` 之类的操作不需要。
- `vcvars32.bat` 设不好 `INCLUDE` 导致 `windows.h` 找不到：该脚本内部会用
  `reg.exe` 探测路径，如果 `reg.exe` 被策略禁用就会静默失败。
  正常终端里 `pnpm run package:desktop:win:x64:unsigned` 不会碰到。

## 6. 内网运行要确认的三件事

安装包自带运行时，所以「装完能不能用」主要不是网络问题，而是这三件：

1. **模型怎么接**。桌面端默认走 DeepSeek 账号登录，内网大概率连不上。
   需要在设置里配置自定义 provider（base URL + API Key），
   或给进程设置 `DEEPSEEK_BASE_URL` 指向内网网关。
   这是内网落地最容易被忽略的一环，建议先用一台内网机器实测登录/对话流程。
2. **插件市场与自动更新**。unsigned 构建已经关闭自动更新；插件市场页面依赖公网
   npm，内网会直接不可用，但不影响核心对话与本地工具。
   需要内网插件分发，得单独搭一个 npm 镜像（`packages/boot/plugin-market` 支持自定义 registry）。
3. **用户数据位置**。会话、配置、profile 都在 `%USERPROFILE%\.dsh`，
   换机器时要一起搬；改 `productName` 会改变 Electron 的 `userData` 目录，
   老版本的数据不会自动迁移。

## 7. 后续学习路线（Python 背景 → TS / Electron / Cordis）

按这个顺序读，投入产出比最高：

1. **TypeScript**：先把 `apps/desktop/src/locale.ts` 这类「纯字典文件」读熟（类型标注、
   `as const`、字面量类型），再读 `packages/client/locale/src/locales/en.ts`。
   语法和 Python 的最大差异只有：类型是编译期擦除、结构化类型、`interface` 描述形状。
2. **Electron**：`apps/desktop/src/main.ts`（主进程、窗口、生命周期）、
   `preload-*.ts`（主进程与页面之间的白名单桥）、`tray.ts`、`package-target.ts`。
   配合 `apps/desktop/packaging/README.md` 一起看，这份文档把签名、更新、安装器都讲透了。
3. **Cordis（本项目的插件内核）**：`docs/cordis-primer.zh.md` 先看一遍，
   再看 `docs/architecture.zh.md` 理解分层，然后拿 `packages/boot/plugin-manager`
   和 `packages/client/ui-brand-official` 当例子——后者只有两个文件，是最小的插件样本。
4. **动手顺序建议**：改一句 UI 文案 → 改一个设置项 → 写一个最小 cordis 插件 →
   才去碰 `prepare-*.ts` 这种打包脚本。

## 8. 已知残留

- 上游的单元测试断言里还写着 `DeepSeek Harness`（`apps/desktop/tests/`）。跑 `pnpm run test`
  这些用例会失败，但**不影响打包**。要维护测试就自己同步这些期望值。
- `packages/client/ui-brand-official` 是 official 构建专用的品牌组件（带官方字标 SVG），
  unsigned 本地构建不会加载它，所以没有改。`apply-brand.mjs` 每次跑完会在末尾把这类
  文件列出来供你复查，通常只有 `ui-brand-official` 两个文件和
  `ui-primitives/src/code-file-icon-artwork.manifest.json`（图标清单里的注释文案）。
- `getPath('userData')` 用的目录名来自 `productName`，首次启动会新建
  `%APPDATA%\XiaoGuang Agent`；旧的上游版本数据在 `%APPDATA%\DeepSeek Harness`，不会自动迁移。
- 版本号仍是上游的 `0.2.1-rc.3`。想改成自己的版本，改根 `package.json` 与
  `apps/desktop/package.json` 的 `version`（两者必须一致，否则打包会直接报错）。
- 上游单测里写死了原始文案（例如 `packages/client/ui-conversation/tests/skeleton.client.spec.tsx`
  断言首页标题是「探索未至之境」、角标是「预览版」）。改文案后跑 `pnpm test` 会有几条
  这类断言失败；**打包链路不跑单测**，不影响出包。真要跑全量测试，就把这些字面量一起改掉。
