// The composer remains in ConversationRoot so switching out of the blank-draft
// phase does not remount its textarea.

import { useState } from 'react'
import type { ReactNode, RefObject } from 'react'
import {
  FISH_LOGO_PATH, FISH_LOGO_VIEWBOX, IconChevronDownOutlineRegular, IconFolderCloseRegular, IconFolderOpenRegular,
} from '@deepseek-ai/dsh-client-ui-primitives'
import { workspaceTitleOf } from '@deepseek-ai/dsh-util-workspace-path'
import type { ConversationContentProps } from '../contract/slots.ts'
import css from './HeroShell.module.css'

/** The owner's locale seat type, passed to hero chrome as a plain prop. */
type HeroTranslate = ConversationContentProps['t']

/**
 * Basename label for the workspace chip (the shared derivation);
 * separator-only paths echo the raw cwd.
 * @param cwd - workspace directory path (non-empty).
 * @returns chip label.
 */
export function workspaceLabel(cwd: string): string {
  const base = workspaceTitleOf(cwd)
  return base !== '' ? base : cwd
}

/**
 * The workspace chip (folder + label + chevron), always interactive: before
 * the first message the workspace stays switchable — picking another one
 * moves the New Session flow to that workspace's blank session. Without a
 * label the chip renders its placeholder state: closed folder + the
 * "Choose workspace" call to action.
 * @param props.label - chip label (see {@link workspaceLabel}); omitted → placeholder.
 * @param props.menuOpen - menu expansion echo.
 * @param props.onClick - menu toggle.
 * @returns the chip button element.
 */
export function WorkspaceChip({ buttonRef, label, menuOpen = false, onClick, t }: {
  buttonRef?: RefObject<HTMLButtonElement>
  label?: string | undefined
  menuOpen?: boolean
  onClick?: () => void
  t: HeroTranslate
}) {
  return (
    <button
      ref={buttonRef}
      type="button"
      className={css.workspace}
      aria-label={t('hero.chooseWorkspace')}
      aria-haspopup="menu"
      aria-expanded={menuOpen}
      onClick={onClick}
    >
      {label === undefined
        ? <IconFolderCloseRegular className={css.folder} size={16} />
        : <IconFolderOpenRegular className={css.folder} size={16} />}
      <span className={css.workspaceLabel}>{label ?? t('hero.chooseWorkspace')}</span>
      <IconChevronDownOutlineRegular className={css.chevron} size={12} />
    </button>
  )
}

/** Hero chrome props. The workspace row rides the InputBar accessory hole, not here. */
export interface HeroShellProps {
  /** The owner's locale seat, passed down as a plain prop. */
  t: HeroTranslate
  /** Authorized renderer for the hero brand-mark slot. */
  renderSlot: ConversationContentProps['renderSlot']
  /** Overlay content after the stack (modals). */
  children?: ReactNode
}

/* Hover swim morph targets: the resting FISH_LOGO_PATH with weighted
   regional deformation baked in (generated programmatically — parse the
   path's absolute M/C/L/Z commands, displace points with smoothstep falloff
   weights, emit the same command structure so SMIL can interpolate `d`
   between them). Tail: rotation about (15.6, 5.2) with weight growing toward
   the tail tip (x>15, y<8.5) — UP -7°, DOWN +6°. Mouth/fin swoosh: a bend,
   not a rotation — vertical lift with weight-squared falloff from the body
   anchor (14.1, 15.0), so the near end stays seated and the mouth corner
   sweeps most, a smile lift (UP -0.7 units at the tip, DOWN +0.5). The eye
   subpaths carry zero weight and stay fixed. */
const HERO_SWIM_UP_PATH = 'M26.50 12.00L26.30 12.59L25.70 13.12L24.77 13.55L23.59 13.83L22.26 13.94L20.87 13.91L19.55 13.75L18.36 13.50L17.37 13.21L16.62 12.93L16.09 12.71L15.76 12.55L15.59 12.48L15.52 12.47L15.49 12.49L15.47 12.52L15.48 12.59L15.55 12.76L15.71 13.09L15.93 13.62L16.21 14.37L16.50 15.36L16.75 16.55L16.91 17.87L16.94 19.26L16.83 20.59L16.55 21.77L16.12 22.70L15.59 23.30L15.00 23.50L14.41 23.30L13.88 22.70L13.45 21.77L13.17 20.59L13.06 19.26L13.09 17.87L13.25 16.55L13.50 15.36L13.79 14.37L14.07 13.62L14.29 13.09L14.45 12.76L14.52 12.59L14.53 12.52L14.51 12.49L14.48 12.47L14.41 12.48L14.24 12.55L13.91 12.71L13.38 12.93L12.63 13.21L11.64 13.50L10.45 13.75L9.13 13.91L7.74 13.94L6.41 13.83L5.23 13.55L4.30 13.12L3.70 12.59L3.50 12.00L3.70 11.41L4.30 10.88L5.23 10.45L6.41 10.17L7.74 10.06L9.13 10.09L10.45 10.25L11.64 10.50L12.63 10.79L13.38 11.07L13.91 11.29L14.24 11.45L14.41 11.52L14.48 11.53L14.51 11.51L14.53 11.48L14.52 11.41L14.45 11.24L14.29 10.91L14.07 10.38L13.79 9.63L13.50 8.64L13.25 7.45L13.09 6.13L13.06 4.74L13.17 3.41L13.45 2.23L13.88 1.30L14.41 0.70L15.00 0.50L15.59 0.70L16.12 1.30L16.55 2.23L16.83 3.41L16.94 4.74L16.91 6.13L16.75 7.45L16.50 8.64L16.21 9.63L15.93 10.38L15.71 10.91L15.55 11.24L15.48 11.41L15.47 11.48L15.49 11.51L15.52 11.53L15.59 11.52L15.76 11.45L16.09 11.29L16.62 11.07L17.37 10.79L18.36 10.50L19.55 10.25L20.87 10.09L22.26 10.06L23.59 10.17L24.77 10.45L25.70 10.88L26.30 11.41Z'
const HERO_SWIM_DOWN_PATH = 'M26.50 12.00L26.30 12.59L25.70 13.12L24.77 13.55L23.59 13.83L22.26 13.94L20.87 13.91L19.55 13.75L18.36 13.50L17.37 13.21L16.62 12.93L16.09 12.71L15.76 12.55L15.59 12.48L15.52 12.47L15.49 12.49L15.47 12.52L15.48 12.59L15.55 12.76L15.71 13.09L15.93 13.62L16.21 14.37L16.50 15.36L16.75 16.55L16.91 17.87L16.94 19.26L16.83 20.59L16.55 21.77L16.12 22.70L15.59 23.30L15.00 23.50L14.41 23.30L13.88 22.70L13.45 21.77L13.17 20.59L13.06 19.26L13.09 17.87L13.25 16.55L13.50 15.36L13.79 14.37L14.07 13.62L14.29 13.09L14.45 12.76L14.52 12.59L14.53 12.52L14.51 12.49L14.48 12.47L14.41 12.48L14.24 12.55L13.91 12.71L13.38 12.93L12.63 13.21L11.64 13.50L10.45 13.75L9.13 13.91L7.74 13.94L6.41 13.83L5.23 13.55L4.30 13.12L3.70 12.59L3.50 12.00L3.70 11.41L4.30 10.88L5.23 10.45L6.41 10.17L7.74 10.06L9.13 10.09L10.45 10.25L11.64 10.50L12.63 10.79L13.38 11.07L13.91 11.29L14.24 11.45L14.41 11.52L14.48 11.53L14.51 11.51L14.53 11.48L14.52 11.41L14.45 11.24L14.29 10.91L14.07 10.38L13.79 9.63L13.50 8.64L13.25 7.45L13.09 6.13L13.06 4.74L13.17 3.41L13.45 2.23L13.88 1.30L14.41 0.70L15.00 0.50L15.59 0.70L16.12 1.30L16.55 2.23L16.83 3.41L16.94 4.74L16.91 6.13L16.75 7.45L16.50 8.64L16.21 9.63L15.93 10.38L15.71 10.91L15.55 11.24L15.48 11.41L15.47 11.48L15.49 11.51L15.52 11.53L15.59 11.52L15.76 11.45L16.09 11.29L16.62 11.07L17.37 10.79L18.36 10.50L19.55 10.25L20.87 10.09L22.26 10.06L23.59 10.17L24.77 10.45L25.70 10.88L26.30 11.41Z'

/**
 * The hero fish (34px wide), static at rest. Hovering swims the whale in
 * place: a gentle head-up sway (CSS, on the hitbox hover) while the body
 * itself morphs — SMIL interpolates `d` through the tail-up and tail-down
 * targets on the same 1.6s period, so the tail wags and the fin flutters in
 * real curve deformation. Decorative — hidden from the accessibility tree;
 * reduced motion keeps the static filled logo on hover (sampled at
 * mouseenter; a mid-hover preference change takes effect on the next enter).
 * @param props.hovering - driven by the hitbox parent's pointer state.
 * @returns the fish svg element.
 */
function HeroFish({ hovering }: { hovering: boolean }) {
  return (
    <svg
      className={css.fish}
      width={34}
      height={(34 * FISH_LOGO_VIEWBOX.height) / FISH_LOGO_VIEWBOX.width}
      viewBox={`0 0 ${FISH_LOGO_VIEWBOX.width} ${FISH_LOGO_VIEWBOX.height}`}
      fill="none"
      aria-hidden="true"
    >
      <path d={FISH_LOGO_PATH} fill="currentColor">
        {hovering && (
          <animate
            attributeName="d"
            values={`${FISH_LOGO_PATH};${HERO_SWIM_UP_PATH};${FISH_LOGO_PATH};${HERO_SWIM_DOWN_PATH};${FISH_LOGO_PATH}`}
            keyTimes="0;0.35;0.55;0.75;1"
            calcMode="spline"
            keySplines="0.45 0 0.55 1;0.45 0 0.55 1;0.45 0 0.55 1;0.45 0 0.55 1"
            dur="1.6s"
            repeatCount="indefinite"
          />
        )}
      </path>
    </svg>
  )
}

/**
 * Render the hero chrome (headline only; no composer, no workspace row).
 * @param props - see {@link HeroShellProps}.
 * @returns the centered hero element tree.
 */
export function HeroShell({ t, renderSlot, children }: HeroShellProps) {
  const [hovering, setHovering] = useState(false)
  return (
    <div className={css.root}>
      <div className={css.stack}>
        <div className={css.headline}>
          {/* figma 34:10412: fish 34×25 leading the headline, gap 10. */}
          <span
            className={css.fishHitbox}
            onPointerEnter={(event) => {
              if (event.pointerType !== 'touch'
                && window.matchMedia('(hover: hover) and (prefers-reduced-motion: no-preference)').matches) {
                setHovering(true)
              }
            }}
            onPointerLeave={() => { setHovering(false) }}
          >
            {renderSlot('conversation.hero.brand.mark', { size: 34, className: css.fish }, {
              fallback: <HeroFish hovering={hovering} />,
            })}
          </span>
          <span className={css.titleGroup}>
            {/* Own element: keeps the headline text addressable apart from the badge. */}
            <span>{t('hero.headline')}</span>
            {t('hero.preview') === '' ? null : <span className={css.previewBadge}>{t('hero.preview')}</span>}
          </span>
        </div>
        <div className={css.body}>
          {/* The composer remains mounted outside this component. */}
        </div>
      </div>
      {children}
    </div>
  )
}
