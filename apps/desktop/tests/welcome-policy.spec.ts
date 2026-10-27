import { expect, it } from 'vitest'
import { welcomeEntryEnabled } from '../src/welcome-policy.ts'

it('keeps the first-run welcome window closed on an intranet build', () => {
  expect(welcomeEntryEnabled({})).toBe(false)
  expect(welcomeEntryEnabled({ DSH_DESKTOP_WELCOME: '0' })).toBe(false)
  expect(welcomeEntryEnabled({ DSH_DESKTOP_WELCOME: 'true' })).toBe(false)
})

it('restores the upstream welcome flow only for an explicit opt-in', () => {
  expect(welcomeEntryEnabled({ DSH_DESKTOP_WELCOME: '1' })).toBe(true)
})
