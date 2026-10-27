import type { IconProps } from './icons/props.ts'

/** Native viewBox of {@link FISH_LOGO_PATH} (width and height in user units). */
export const FISH_LOGO_VIEWBOX = { width: 30, height: 24 }

/** The fish silhouette path data, exported for consumers that compose their own svg (entrance effects, masks) around the same geometry. */
export const FISH_LOGO_PATH = 'M26.50 12.00L26.30 12.59L25.70 13.12L24.77 13.55L23.59 13.83L22.26 13.94L20.87 13.91L19.55 13.75L18.36 13.50L17.37 13.21L16.62 12.93L16.09 12.71L15.76 12.55L15.59 12.48L15.52 12.47L15.49 12.49L15.47 12.52L15.48 12.59L15.55 12.76L15.71 13.09L15.93 13.62L16.21 14.37L16.50 15.36L16.75 16.55L16.91 17.87L16.94 19.26L16.83 20.59L16.55 21.77L16.12 22.70L15.59 23.30L15.00 23.50L14.41 23.30L13.88 22.70L13.45 21.77L13.17 20.59L13.06 19.26L13.09 17.87L13.25 16.55L13.50 15.36L13.79 14.37L14.07 13.62L14.29 13.09L14.45 12.76L14.52 12.59L14.53 12.52L14.51 12.49L14.48 12.47L14.41 12.48L14.24 12.55L13.91 12.71L13.38 12.93L12.63 13.21L11.64 13.50L10.45 13.75L9.13 13.91L7.74 13.94L6.41 13.83L5.23 13.55L4.30 13.12L3.70 12.59L3.50 12.00L3.70 11.41L4.30 10.88L5.23 10.45L6.41 10.17L7.74 10.06L9.13 10.09L10.45 10.25L11.64 10.50L12.63 10.79L13.38 11.07L13.91 11.29L14.24 11.45L14.41 11.52L14.48 11.53L14.51 11.51L14.53 11.48L14.52 11.41L14.45 11.24L14.29 10.91L14.07 10.38L13.79 9.63L13.50 8.64L13.25 7.45L13.09 6.13L13.06 4.74L13.17 3.41L13.45 2.23L13.88 1.30L14.41 0.70L15.00 0.50L15.59 0.70L16.12 1.30L16.55 2.23L16.83 3.41L16.94 4.74L16.91 6.13L16.75 7.45L16.50 8.64L16.21 9.63L15.93 10.38L15.71 10.91L15.55 11.24L15.48 11.41L15.47 11.48L15.49 11.51L15.52 11.53L15.59 11.52L15.76 11.45L16.09 11.29L16.62 11.07L17.37 10.79L18.36 10.50L19.55 10.25L20.87 10.09L22.26 10.06L23.59 10.17L24.77 10.45L25.70 10.88L26.30 11.41Z'

/**
 * Render the fish logo.
 * @param props.size - width in px (default 24; height keeps the 23.16:17.04 ratio).
 * @param props.className - extra class for layout placement.
 * @returns the logo svg (aria-hidden; pair with the wordmark for accessibility).
 */
export function FishLogo({ size = 24, className }: IconProps) {
  return (
    <svg
      width={size}
      height={(size * FISH_LOGO_VIEWBOX.height) / FISH_LOGO_VIEWBOX.width}
      className={className}
      viewBox={`0 0 ${FISH_LOGO_VIEWBOX.width} ${FISH_LOGO_VIEWBOX.height}`}
      fill="none"
      aria-hidden="true"
    >
      <path d={FISH_LOGO_PATH} fill="currentColor" />
    </svg>
  )
}
