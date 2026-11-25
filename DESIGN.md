# Dictora website — DESIGN.md

Direction: calm, native-Mac, trustworthy. A quiet utility that feels like part of macOS, not a startup
gradient. Built from the app icon (indigo) and the product's own promise (private, on-device).
Not based on real-site comparisons (UXKIN not connected); derived from the project and the icon.

## Color (light / dark)
| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| --bg | #FAFAF8 | #0E0F14 | page background |
| --surface | #FFFFFF | #171923 | cards, mock windows |
| --text | #14151A | #ECEDF2 | body and headings |
| --text-muted | #5A5D6B | #A2A5B4 | secondary text (>=4.5:1 on bg) |
| --border | #E4E4E0 | #2A2D3A | hairlines |
| --primary | #4338CA | #8B93FF | buttons, links, focus ring |
| --primary-text | #FFFFFF | #0E0F14 | text on primary |
| --accent | #D97706 | #F2A33A | one highlight only: the "after" text in the demo |

Icon gradient (#4F63FF -> #4A1FB0) is used only on the app icon, never on headings or backgrounds.

## Typography
- Family: system stack (`-apple-system, "SF Pro Text", "Inter", system-ui, sans-serif`); mono: `ui-monospace, "SF Mono"` for keys and dictated text.
- Scale (px / line height): 14/20, 16/26, 18/28, 22/30, 30/38, 44/50, 60/64. Weights 400, 600, 700.
- Body 16px+, lines capped at 65ch.

## Spacing and shape
- 8-based scale: 4, 8, 16, 24, 32, 48, 80, 120. Section padding 80 (mobile) / 120 (desktop). Content width 1080.
- Radius: 8 (controls), 14 (cards), 999 (pills). One soft shadow: `0 8px 30px rgb(0 0 0 / .08)` (none in dark; use border).

## Components
- Primary button: --primary fill, 8 radius, 44px tall; hover darkens 8%; visible 3px focus ring in --primary at 2px offset.
- Secondary: border only. Quiet: text link with underline on hover.
- Key cap: mono, --surface, 1px border, 6 radius (for Fn / Globe, ⌥Space).
- Cards: --surface, 1px --border, 14 radius. Not three identical cards: feature rows alternate layout.

## Imagery
- Real app icon (Design/AppIcon-master.png). Product visuals are HTML/CSS recreations of the overlay and menu bar, marked as illustrations until real screenshots exist.
- Icons: none beyond inline SVG waveform from the icon; no emoji.
