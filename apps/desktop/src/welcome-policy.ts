/**
 * Whether this build opens the first-run welcome window before the workspace.
 *
 * The upstream window offers exactly two routes — sign in to a DeepSeek account,
 * or paste an official DeepSeek API key (`apps/desktop/src/client/WelcomePage.tsx`).
 * An intranet deployment has neither: models come from a self-hosted vLLM /
 * Ollama endpoint, and every user enters that endpoint themselves on
 * `Settings → 模型 → 添加模型提供商 → 自定义模型 API`. That page needs no
 * account, no key from us, and no composition change — so the entry window is
 * only an obstacle and this fork leaves it off.
 *
 * `DSH_DESKTOP_WELCOME=1` restores the upstream first-run flow, which is what
 * you want when checking the branded welcome window itself.
 * @param env - environment mapping read for the override.
 * @returns true only when the deployment explicitly asks for the welcome flow.
 */
export function welcomeEntryEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.DSH_DESKTOP_WELCOME === '1'
}
