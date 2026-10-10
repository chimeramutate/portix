# Portix design direction

Direction for UI work. Answers come from the project owner (2026-10-09); lines marked *(inferred)* were filled in by the agent and are open to correction.

## Personality

**Friendly workspace.** Approachable for people less at home with SSH: generous spacing, clear labels, nothing that needs prior knowledge to decode.

## Dials

`Dial: ENERGY 1 / RHYTHM 1 / MOTION 1`

- ENERGY 1: calm and restrained.
- MOTION 1: hover and focus states only; no decorative animation.
- RHYTHM 1 *(inferred)*: screens share one consistent structure, since this is a tool used every day, not a page to scroll through.

## Color

- **Base:** keep the existing navy surfaces in dark mode and the existing light surfaces in light mode (`AppPalette.dark` / `AppPalette.light` in `portix_app/lib/src/core/theme/app_theme.dart`). The app follows the OS light/dark setting.
- **One accent: cyan.** Used for interaction only: primary buttons, focus, selection, active tab.
  - Dark: `#14D7FF` (8.36:1 on card `#102B47`).
  - Light: the current `#0479A8` is 4.22:1 on card `#E9EFF7`, below 4.5:1, so it must be darkened until it passes on both `#E9EFF7` and `#FFFFFF`.
- **Status colors only for status:** green = online/success, amber = warning, danger = error. They are not used as decoration or for interaction.
- **Blue (`primaryBlue`) is retired as an accent.** Anything using it for interaction moves to cyan.

## Typography

**Native system font** per OS (San Francisco on macOS, Segoe UI on Windows, the desktop default on Linux), replacing the bundled Inter. No bundled UI font. The terminal keeps its own monospace setting.

## Shape *(inferred, from current code)*

Corner radius stays mostly 8 px (10 px for larger panels). Pills only for real status chips.

## Rules this direction relies on

- Every text pairing meets WCAG AA (4.5:1 normal, 3:1 large) in both themes; checked with the contrast script, not by eye.
- Visible keyboard focus on every interactive element, in the accent color, 3:1 against its neighbors.
- Empty, loading and error states say what happened and what to do next.
