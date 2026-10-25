# Portix design direction

Direction for UI work. Decided by the project owner on 2026-10-25, replacing the navy + cyan direction of 2026-10-09. Lines marked *(inferred)* were filled in by the agent and are open to correction.

## Personality

**Swiss pro tool.** Clean, functional and dense: a neutral slate canvas, one green accent, clear type hierarchy, grid alignment. Content (terminal, files, logs) carries the screen; chrome stays quiet.

## Dials

`Dial: ENERGY 1 / RHYTHM 1 / MOTION 1 / DENSITY 8`

- ENERGY 1: calm and restrained.
- MOTION 1: hover and focus states only (150-250 ms); no decorative animation.
- RHYTHM 1: screens share one consistent structure, since this is a tool used every day.
- DENSITY 8: compact spacing (4/8/12/16/24/32 px scale), compact controls; 32 px row and control height is the default.

## Color

Slate neutrals, following the OS light/dark setting (`AppPalette.dark` / `AppPalette.light` in `portix_app/lib/src/core/theme/app_theme.dart`).

| Token | Dark | Light |
|---|---|---|
| bg | `#0B1120` | `#F8FAFC` |
| surface | `#131B2E` | `#FFFFFF` |
| surfaceCard | `#1B2336` | `#EEF2F6` |
| border | `#273349` | `#E2E8F0` |
| text / muted | `#F8FAFC` / `#94A3B8` | `#0F172A` / `#475569` |
| **accent** | `#22C55E` | `#166534` |

- **One accent: green (`AppColors.accent`).** Interaction only: primary buttons, focus, selection, active tab.
- **Status colors only for status:** green = online/success, amber = warning, danger = error. Because success and the accent share a hue, status is never shown by color alone: it always has an icon or a label.
- **Categorical colors** (`blue`, `cyan`, profile colors, file types, log levels) label things; they are never used for interaction.
- The terminal keeps its own ANSI themes.

## Typography

**Native system font** per OS for the UI. Monospace only for content that is code or machine output: terminal, logs, paths, fingerprints, commands.

Weights stay light: 400 body, 500 labels and emphasis, 600 titles. Nothing heavier.

## Shape *(inferred)*

Corner radius 8 px (10 px for dialogs and larger panels), as in the current code. Borders over shadows; no shadow except on popups and dialogs. Pills only for real status chips.

## Rules this direction relies on

- Every text pairing meets WCAG AA (4.5:1 normal, 3:1 large) in both themes; checked with a contrast script, not by eye. Input borders are 3:1 against every surface they sit on.
- Visible keyboard focus on every interactive element, in the accent color.
- Empty, loading and error states say what happened and what to do next.
