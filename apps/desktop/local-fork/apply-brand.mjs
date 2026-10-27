#!/usr/bin/env node
/**
 * Apply `brand.json` to every product-name and brand surface this fork owns.
 *
 * The official desktop shell hard-codes the upstream product name in a handful of
 * places (electron-builder config, shell locale tables, NSIS locale tables, the CLI
 * launcher paths, the client brand label). This script keeps those in one place so a
 * rename is a config edit instead of a hunt.
 *
 * Usage:
 *   node apps/desktop/local-fork/apply-brand.mjs            # write changes
 *   node apps/desktop/local-fork/apply-brand.mjs --dry-run  # show what would change
 *
 * After a successful run, `replaceNames` in brand.json is rewritten to the current
 * product name, so the next rename only needs `productName` plus the old value.
 */

import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const DESKTOP_ROOT = resolve(HERE, '..')
const REPOSITORY_ROOT = resolve(DESKTOP_ROOT, '..', '..')
const BRAND_PATH = join(HERE, 'brand.json')
const BRAND_LEGACY_PATH = join(DESKTOP_ROOT, '.env.windows')

const dryRun = process.argv.includes('--dry-run')

const brand = JSON.parse(readFileSync(BRAND_PATH, 'utf8'))
const productName = brand.productName?.trim()
const slug = brand.slug?.trim()
const appId = brand.appId?.trim()
if (!productName || !slug || !appId) {
  throw new Error('brand.json: productName, slug and appId are required')
}
if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(slug)) {
  throw new Error('brand.json: slug must be lowercase letters, digits and single hyphens')
}
if (!/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/u.test(appId)) {
  throw new Error('brand.json: appId must be a reverse-DNS identifier such as com.example.app')
}

/** Every name currently written into the sources; all of them become `productName`. */
const previousNames = [...new Set([...(brand.replaceNames ?? []), productName])]
  .filter(name => typeof name === 'string' && name.trim() !== '')
  .sort((left, right) => right.length - left.length)

const changes = []

/**
 * Rewrite one file when its contents change.
 * @param {string} path absolute file path
 * @param {(text: string) => string} transform pure text transform
 */
function rewrite(path, transform) {
  if (!existsSync(path)) return
  const before = readFileSync(path, 'utf8')
  const after = transform(before)
  if (after === before) return
  changes.push(relative(REPOSITORY_ROOT, path).split('\\').join('/'))
  if (!dryRun) writeFileSync(path, after)
}

/** Replace every previous product name with the current one. */
function replaceNames(text) {
  let result = text
  for (const name of previousNames) result = result.split(name).join(productName)
  return result
}

/** Interface languages whose locale tables this fork rewrites. */
const LOCALES = ['zh', 'en', 'ja', 'es', 'fr', 'de', 'ru', 'pt']

/**
 * Build a four-point sparkle outline as a closed SVG path.
 *
 * The radius falls to `innerRatio` on the diagonals, which is what turns a
 * circle into the concave twinkle. Same geometry as the icon drawn by
 * `render-assets.ps1`, so the in-app mark matches the executable icon.
 * @param {object} mark - width, height, radius, innerRatio, lobePower, samples.
 * @returns {string} path data in the mark's own coordinate system.
 */
function buildMarkPath(mark) {
  const centerX = mark.width / 2
  const centerY = mark.height / 2
  const points = []
  for (let index = 0; index < mark.samples; index++) {
    const angle = (2 * Math.PI * index) / mark.samples
    const lobe = Math.abs(Math.cos(2 * angle)) ** mark.lobePower
    const distance = mark.radius * (mark.innerRatio + (1 - mark.innerRatio) * lobe)
    points.push(`${(centerX + distance * Math.cos(angle)).toFixed(2)} ${(centerY + distance * Math.sin(angle)).toFixed(2)}`)
  }
  return `M${points.join('L')}Z`
}

/**
 * Rewrite one locale key inside every `export const <locale> = { ... }` block.
 * @param {string} text - locale module source.
 * @param {string} key - translation key, such as `hero.headline`.
 * @param {Record<string, string>} values - replacement text keyed by locale.
 * @returns {string} source with the value replaced where a locale is configured.
 */
function replacePerLocale(text, key, values) {
  const pattern = new RegExp(`^export const (${LOCALES.join('|')}) = \\{`, 'gmu')
  const blocks = [...text.matchAll(pattern)]
  if (blocks.length === 0) return text
  // Locale authors mix quote styles to avoid escaping apostrophes ("Dans l'inconnu").
  const keyPattern = new RegExp(`('${key.replaceAll('.', '\\.')}':\\s*)(?:'[^']*'|"[^"]*")`, 'u')
  let result = ''
  let cursor = 0
  for (const [index, block] of blocks.entries()) {
    const start = block.index
    const end = index + 1 < blocks.length ? blocks[index + 1].index : text.length
    result += text.slice(cursor, start)
    const segment = text.slice(start, end)
    const value = values[block[1]]
    result += value === undefined
      ? segment
      : segment.replace(keyPattern, (_match, head) => `${head}'${value.replaceAll("'", "\\'")}'`)
    cursor = end
  }
  return result + text.slice(cursor)
}

// --- files that only embed the product name ------------------------------------------------
const nameOnlyFiles = [
  'apps/desktop/src/locale.ts',
  'apps/desktop/src/main.ts',
  'apps/desktop/installer/extract-report.h',
  'apps/desktop/cli/dsh',
  'apps/desktop/cli/dsh.cmd',
  // Packaging scripts locate the built executable and application bundle by product name.
  'apps/desktop/scripts/smoke-packaged-runtime.ts',
  'apps/desktop/scripts/package-target.ts',
  'apps/desktop/scripts/package-macos.ts',
  'apps/desktop/scripts/verify-retained-desktop.ts',
  'apps/desktop/scripts/development-app.ts',
  // The agent introduces itself to the model with this line.
  'packages/core/system-prompt/src/index.ts',
  'packages/client/ui-plugin-manager/src/client/locales.ts',
  'packages/client/ui-settings-account/src/client/locales.ts',
  'packages/client/ui-settings-account/src/client/locales/onboarding.ts',
  'packages/client/ui-settings-models/src/client/locales.ts',
  'packages/client/ui-sidebar-documentpreview/src/client/office/locales.ts',
]
for (const file of nameOnlyFiles) rewrite(join(REPOSITORY_ROOT, file), replaceNames)

// --- NSIS installer locale tables -----------------------------------------------------------
const installerLocales = join(DESKTOP_ROOT, 'installer', 'locales')
for (const file of readdirSync(installerLocales).filter(name => name.endsWith('.json'))) {
  rewrite(join(installerLocales, file), replaceNames)
}

// --- electron-builder: product name, protocol label, artifact file name ---------------------
// artifactName is a template literal in the generated config, and electron-builder substitutes
// ${version}/${os}/${arch}/${ext} itself: those must stay escaped (`\${...}`) or the config
// module evaluates them as JavaScript variables and throws "version is not defined".
// `${output.suffix}` is deliberately unescaped — it is interpolated by the config itself.
const BUILDER_CONFIG_PATH = join(DESKTOP_ROOT, 'scripts', 'electron-builder-config.mjs')
const artifactNameLine = 'artifactName: `' + slug + '-\\${version}-\\${os}-\\${arch}${output.suffix}.\\${ext}`'
rewrite(BUILDER_CONFIG_PATH, text => replaceNames(text
  .replace(/productName: '[^']*'/u, `productName: '${productName}'`)
  .replace(/protocols: \[\{ name: '[^']*', schemes: \['dsh'\] \}\]/u, `protocols: [{ name: '${productName}', schemes: ['dsh'] }]`)
  .replace(/artifactName: `[^`]*`/u, artifactNameLine)))
if (!dryRun && existsSync(BUILDER_CONFIG_PATH)
  && !readFileSync(BUILDER_CONFIG_PATH, 'utf8').includes(artifactNameLine)) {
  throw new Error(`brand: failed to write ${artifactNameLine} into electron-builder-config.mjs`)
}

// --- client shell brand label (window title and sidebar name) --------------------------------
const clientLocales = join(REPOSITORY_ROOT, 'packages', 'client', 'locale', 'src', 'locales')
for (const file of readdirSync(clientLocales).filter(name => name.endsWith('.ts'))) {
  rewrite(join(clientLocales, file), text =>
    text.replace(/('brand\.localBuild':\s*)'[^']*'/u, `$1'${productName.replaceAll("'", "\\'")}'`))
}

// --- brand mark: the whale silhouette used by the sidebar rail and the hero ------------------
// Both surfaces draw `FISH_LOGO_PATH` (the sidebar through FishLogo, the hero through its own
// inline svg plus two deformation targets for the hover tail-wag). Replacing the resting path
// without the two morph targets would animate a whale tail out of an unrelated glyph, so all
// three get the same custom outline: the hero keeps its CSS sway but stops wagging a tail.
const MARK = {
  width: 30,
  height: 24,
  radius: 11.5,
  innerRatio: 0.06,
  lobePower: 3.2,
  samples: 120,
  ...(brand.mark ?? {}),
}
const MARK_PATH = typeof brand.mark?.path === 'string' && brand.mark.path.trim() !== ''
  ? brand.mark.path.trim()
  : buildMarkPath(MARK)

rewrite(join(REPOSITORY_ROOT, 'packages', 'client', 'ui-primitives', 'src', 'FishLogo.tsx'), text => text
  .replace(/export const FISH_LOGO_VIEWBOX = \{ width: [\d.]+, height: [\d.]+ \}/u,
    `export const FISH_LOGO_VIEWBOX = { width: ${MARK.width}, height: ${MARK.height} }`)
  .replace(/export const FISH_LOGO_PATH = '[^']*'/u, `export const FISH_LOGO_PATH = '${MARK_PATH}'`))

const HERO_SKELETON_PATH = join(REPOSITORY_ROOT, 'packages', 'client', 'ui-conversation', 'src', 'client', 'skeleton', 'EmptyHero.tsx')
rewrite(HERO_SKELETON_PATH, text => text
  .replace(/const HERO_SWIM_UP_PATH =\s*'[^']*'/u, `const HERO_SWIM_UP_PATH = '${MARK_PATH}'`)
  .replace(/const HERO_SWIM_DOWN_PATH =\s*'[^']*'/u, `const HERO_SWIM_DOWN_PATH = '${MARK_PATH}'`))

// --- hero headline, per interface language --------------------------------------------------
const heroHeadline = brand.heroHeadline
const heroHeadlineByLocale = typeof heroHeadline === 'string'
  ? Object.fromEntries(LOCALES.map(locale => [locale, heroHeadline]))
  : Object.fromEntries(Object.entries(heroHeadline ?? {}).map(([locale, value]) => [locale, String(value)]))
if (Object.keys(heroHeadlineByLocale).length > 0) {
  rewrite(join(REPOSITORY_ROOT, 'packages', 'client', 'ui-conversation', 'src', 'client', 'locales.ts'),
    text => replacePerLocale(text, 'hero.headline', heroHeadlineByLocale))
}

// --- hero badge: the pill printed after the headline in the empty conversation --------------
// `heroBadge: ""` removes it completely; any other string replaces the "预览版 / Preview" copy in
// all eight interface languages. Upstream renders the element unconditionally, so an empty
// translation alone would leave an empty pill behind — the render line gets a presence check.
const HERO_BADGE_PLAIN = '<span className={css.previewBadge}>{t(\'hero.preview\')}</span>'
const HERO_BADGE_GUARDED = `{t('hero.preview') === '' ? null : ${HERO_BADGE_PLAIN}}`
const heroBadge = typeof brand.heroBadge === 'string' ? brand.heroBadge : undefined
if (heroBadge !== undefined) {
  const badgeByLocale = Object.fromEntries(LOCALES.map(locale => [locale, heroBadge]))
  rewrite(join(REPOSITORY_ROOT, 'packages', 'client', 'ui-conversation', 'src', 'client', 'locales.ts'),
    text => replacePerLocale(text, 'hero.preview', badgeByLocale))
  // Normalise before re-applying so the transform is idempotent in both directions.
  rewrite(HERO_SKELETON_PATH, text => text
    .split(HERO_BADGE_GUARDED).join(HERO_BADGE_PLAIN)
    .split(HERO_BADGE_PLAIN).join(heroBadge === '' ? HERO_BADGE_GUARDED : HERO_BADGE_PLAIN))
}

// --- DMG filename printed by the packaging command (mirrors the artifact template) ----------
rewrite(join(DESKTOP_ROOT, 'scripts', 'package-target.ts'), text =>
  text.replace(/(const filename = `)[a-z0-9-]+(?=-\$\{buildVersion\})/u, `$1${slug}`))

// --- desktop manifest: product name for Electron itself, plus publisher metadata --------------
const manifestPath = join(DESKTOP_ROOT, 'package.json')
{
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
  let dirty = false
  // Electron derives app.getPath('userData') from the packaged manifest, not from
  // electron-builder's productName, so the two must agree.
  if (manifest.productName !== productName) {
    manifest.productName = productName
    dirty = true
  }
  if (typeof brand.companyName === 'string' && brand.companyName.trim() !== ''
    && manifest.author?.name !== brand.companyName) {
    manifest.author = { ...manifest.author, name: brand.companyName }
    dirty = true
  }
  // electron-builder copies `description` into the executable's FileDescription, which is the
  // text Windows shows in file properties and in the task manager process list.
  if (typeof brand.description === 'string' && brand.description.trim() !== ''
    && manifest.description !== brand.description) {
    manifest.description = brand.description
    dirty = true
  }
  if (dirty) {
    changes.push(relative(REPOSITORY_ROOT, manifestPath).split('\\').join('/'))
    if (!dryRun) writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
  }
}

// --- local packaging settings (git-ignored): app id and intranet service origins -------------
if (!existsSync(BRAND_LEGACY_PATH)) {
  const updateOrigin = brand.updateOrigin ?? 'https://update.intranet.example'
  const loginOrigin = brand.loginOrigin ?? 'https://login.intranet.example'
  const dotenv = `# Written by apps/desktop/local-fork/apply-brand.mjs; ignored by Git.
# Unsigned Windows packaging reads this file. Replace the two origins with the real
# intranet services, or keep them as placeholders when automatic updates are unused.
DSH_DESKTOP_APP_ID=${appId}
DSH_DESKTOP_AUTO_UPDATE_ENV=test
DSH_DESKTOP_MANDATORY_UPDATE_TEST_ORIGIN=${updateOrigin}
DSH_DESKTOP_MANDATORY_UPDATE_CONFIG='{"allowedAuthOrigins":["${loginOrigin}"]}'
DSH_DESKTOP_WINDOWS_COMPRESSION_LEVEL=3
DSH_DESKTOP_WINDOWS_SIGNATURE_CACHE_CONCURRENCY=4
`
  changes.push('apps/desktop/.env.windows (created)')
  if (!dryRun) writeFileSync(BRAND_LEGACY_PATH, dotenv)
}

// --- asset preview page: look at the mark, the headline and the icons without building ----------
const PREVIEW_PATH = join(HERE, 'preview.html')
const previewHeadline = heroHeadlineByLocale.zh
  ?? heroHeadlineByLocale.en
  ?? ''
{
  const html = buildPreviewHtml({ headline: previewHeadline, badge: heroBadge, mark: MARK })
  const current = existsSync(PREVIEW_PATH) ? readFileSync(PREVIEW_PATH, 'utf8') : ''
  if (current !== html) {
    changes.push('apps/desktop/local-fork/preview.html (generated)')
    if (!dryRun) writeFileSync(PREVIEW_PATH, html)
  }
}

/**
 * Render the stand-alone asset preview page.
 *
 * It reads the already-generated image files next to it, so it opens instantly
 * with no build step: the point is to check a brand tweak before spending
 * minutes on `package:desktop`.
 * @param {object} options - headline text, optional badge text and mark geometry.
 * @returns {string} complete HTML document.
 */
function buildPreviewHtml({ headline, badge, mark }) {
  const version = JSON.parse(readFileSync(join(DESKTOP_ROOT, 'package.json'), 'utf8')).version ?? ''
  const markSvg = `<svg viewBox="0 0 ${mark.width} ${mark.height}" width="34" height="${(34 * mark.height / mark.width).toFixed(1)}" fill="none" aria-hidden="true"><path d="${MARK_PATH}" fill="currentColor"/></svg>`
  return `<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<title>${productName} · 品牌素材预览</title>
<style>
  :root { color-scheme: light; --ink: #1b1f24; --muted: #6b7280; --line: #e5e7eb; --bg: #f7f8fa; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 32px; background: var(--bg); color: var(--ink);
         font: 14px/1.6 "Segoe UI", "Microsoft YaHei", system-ui, sans-serif; }
  h1 { margin: 0 0 4px; font-size: 20px; }
  p.lead { margin: 0 0 28px; color: var(--muted); }
  section { background: #fff; border: 1px solid var(--line); border-radius: 12px;
            padding: 20px 24px; margin-bottom: 18px; }
  h2 { margin: 0 0 14px; font-size: 13px; font-weight: 600; color: var(--muted);
       text-transform: uppercase; letter-spacing: .06em; }
  .hero { display: flex; align-items: center; justify-content: center; gap: 10px;
          padding: 28px; font-size: 26px; font-weight: 500; color: var(--ink); }
  .hero .badge { font: 11px/1 ui-monospace, monospace; color: var(--muted);
                 border: 1px solid var(--line); border-radius: 4px; padding: 3px 5px;
                 align-self: flex-start; margin-top: 2px; }
  .rail { display: flex; align-items: center; gap: 8px; padding: 10px 14px;
          border: 1px solid var(--line); border-radius: 10px; width: max-content; }
  .rail .name { font-size: 13px; font-weight: 500; }
  .rail .ver { font-size: 11px; color: var(--muted); }
  .icons { display: flex; align-items: flex-end; gap: 28px; flex-wrap: wrap; }
  .icons figure { margin: 0; text-align: center; }
  .icons figcaption { font-size: 11px; color: var(--muted); margin-top: 6px; }
  .icons img { display: block; border-radius: 18%; }
  .assets { display: flex; gap: 24px; flex-wrap: wrap; align-items: flex-start; }
  .assets figure { margin: 0; }
  .assets figcaption { font-size: 11px; color: var(--muted); margin-top: 6px; }
  .assets img { display: block; max-width: 100%; border: 1px solid var(--line); border-radius: 6px; }
  footer { color: var(--muted); font-size: 12px; }
  code { background: #eef1f5; border-radius: 4px; padding: 1px 5px; }
</style>
<h1>${productName} · 品牌素材预览</h1>
<p class="lead">这是静态预览，不启动应用。<code>apply-brand.mjs</code> 会重写本文件，图标由 <code>render-assets.ps1</code> 生成。</p>

<section>
  <h2>首页 hero（标题 + 标记）</h2>
  <div class="hero">${markSvg}<span>${headline}</span>${badge ? `<span class="badge">${badge}</span>` : ''}</div>
</section>

<section>
  <h2>侧栏左上角</h2>
  <div class="rail">
    ${markSvg.replace('width="34"', 'width="24"').replace(/height="[\d.]+"/u, `height="${(24 * mark.height / mark.width).toFixed(1)}"`)}
    <span class="name">${productName}</span>
    <span class="ver">v${version}</span>
  </div>
</section>

<section>
  <h2>应用图标</h2>
  <div class="icons">
    <figure><img src="../resources/icon-windows.png" width="128" height="128" alt=""><figcaption>128</figcaption></figure>
    <figure><img src="../resources/icon-windows.png" width="48" height="48" alt=""><figcaption>48</figcaption></figure>
    <figure><img src="../resources/icon-windows.png" width="32" height="32" alt=""><figcaption>32</figcaption></figure>
    <figure><img src="../resources/icon-windows.png" width="16" height="16" alt=""><figcaption>16</figcaption></figure>
    <figure><img src="../resources/tray-windows.ico" width="32" height="32" alt=""><figcaption>托盘 32</figcaption></figure>
    <figure><img src="../resources/tray-windows.ico" width="16" height="16" alt=""><figcaption>托盘 16</figcaption></figure>
  </div>
</section>

<section>
  <h2>安装器素材</h2>
  <div class="assets">
    <figure><img src="../installer/assets/brand.png" width="300" alt=""><figcaption>brand.png 600×196</figcaption></figure>
    <figure><img src="../installer/assets/brand-dark.png" width="300" alt=""><figcaption>brand-dark.png（深色底）</figcaption></figure>
    <figure><img src="../installer/assets/uninstaller-sidebar.png" width="82" alt=""><figcaption>uninstaller-sidebar.png 164×314</figcaption></figure>
  </div>
</section>

<footer>改图后刷新本页即可看到效果；要改标题文字或标记形状，编辑 <code>brand.json</code> 后重跑 <code>apply-brand.mjs</code>。</footer>
</html>
`
}

// --- record the applied name so upstream merges are renamed again on the next run -----------
const recorded = [...new Set([...(brand.replaceNames ?? []), productName])]
if (!dryRun && JSON.stringify(brand.replaceNames) !== JSON.stringify(recorded)) {
  brand.replaceNames = recorded
  writeFileSync(BRAND_PATH, `${JSON.stringify(brand, null, 2)}\n`)
}

if (changes.length === 0) {
  console.log(`brand: "${productName}" is already applied; nothing to rewrite`)
} else {
  console.log(`brand: ${dryRun ? 'would update' : 'updated'} ${changes.length} file(s) for "${productName}"`)
  for (const file of changes) console.log(`  - ${file}`)
}

// --- report brand names still present outside the surfaces this script owns -----------------
const SCAN_ROOTS = ['apps/desktop/src', 'apps/desktop/renderer', 'apps/desktop/installer', 'apps/web/src', 'packages/client']
const SCAN_EXTENSIONS = new Set(['.ts', '.tsx', '.json', '.html', '.css', '.h', '.nsh', '.cmd'])
const SKIP_DIRECTORIES = new Set(['node_modules', 'lib', 'dist', 'tests', '__snapshots__'])
const leftovers = []
for (const name of previousNames.filter(value => value !== productName)) {
  for (const root of SCAN_ROOTS) walk(join(REPOSITORY_ROOT, root), name, leftovers)
}
if (leftovers.length > 0) {
  console.log('\nbrand: these files still mention an upstream product name (review by hand):')
  for (const entry of leftovers.slice(0, 20)) console.log(`  - ${entry}`)
  if (leftovers.length > 20) console.log(`  … and ${leftovers.length - 20} more`)
}

/**
 * Collect files under one root that still contain a literal product name.
 * @param {string} directory directory to scan
 * @param {string} needle literal text to look for
 * @param {string[]} found accumulator of matched paths
 */
function walk(directory, needle, found) {
  if (!existsSync(directory)) return
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (SKIP_DIRECTORIES.has(entry.name)) continue
    const path = join(directory, entry.name)
    if (entry.isDirectory()) { walk(path, needle, found); continue }
    const extension = entry.name.slice(entry.name.lastIndexOf('.'))
    if (!SCAN_EXTENSIONS.has(extension)) continue
    let text
    try { text = readFileSync(path, 'utf8') } catch { continue }
    if (text.includes(needle)) found.push(relative(REPOSITORY_ROOT, path).split('\\').join('/'))
  }
}
