<!-- impeccable:product-schema 1 -->
# OmaSwitch

## Platform

desktop (Quickshell QML overlay plugin on Hyprland, Omarchy Quattro). Not web, iOS, or Android.

## Users

Omarchy users on Linux who keep many windows open across workspaces (terminals, browsers, editors) and press `Alt+Tab` dozens of times a day. They are keyboard-first, customize their desktop, and install plugins from the Omarchy plugin marketplace. Secondary audience: hiring managers and engineers reading the owner's portfolio.

## Product Purpose

Switch to the window you want in one or two keystrokes, including when you only remember what was on screen, not its title.

Success for v2 (owner, 2026-11-21): more Omarchy users install and keep it (adoption), and it stands as a portfolio piece showing product and engineering craft.

## Positioning

The Omarchy `Alt+Tab` that finds anything. Recent windows first, live preview, and on-device OCR search of what is inside each window. As of 2026-11-21 roughly 20 marketplace plugins switch or overview windows (Exposé, altswitch, omalt-tab, hyprland-alttab, others); none search window contents. OmaSwitch competes on search, not on grid overviews.

## Operating Context

- Summoned by a Hyprland keybinding (`omarchy-shell shell summon piyush.omaswitch '{"mode":"cycle","direction":1}'`) or toggled as a searchable picker.
- Runs inside Omarchy Shell; no daemon, no extra package, no elevated privilege.
- Live previews via `hyprland-toplevel-export-v1`; OCR via `tesseract`, bundled with Omarchy.
- Users switch Omarchy themes often; the overlay must follow the active theme.

## Capabilities and Constraints

- Plugin id `piyush.omaswitch` is permanent (marketplace rule).
- Existing summon payloads must keep working across versions.
- Settings live in the plugin's entry in `~/.config/omarchy/shell.json`, written through the shell's `updateEntryInline`.
- Keybindings live in the user's `~/.config/hypr/bindings.lua` (Lua config). Plugins cannot register bindings through the manifest.
- OCR runs locally only; window contents never leave the machine.
- Tests run under plain `node` in CI (`node test_model.js`); no QML test runner in CI today.

## Brand Commitments

- Name: OmaSwitch. Tagline in use: "Alt+Tab Omarchy missing".
- Visual identity is the active Omarchy theme (colors, `Style.font.menuFamily`, `Style.cornerRadius`). No own palette.
- Write-up: https://piyushmehta.com/blog/omaswitch-alt-tab-omarchy

## Evidence on Hand

- Screenshots: `preview.png`, `screenshots/terminal-preview.png`, `screenshots/btop-preview.png` (v1 UI).
- GitHub: 14 stars, organic Google traffic only (26 unique visitors in 14 days, 2026-11-21).
- No user testimonials, install counts, or benchmarks exist. Do not invent any.

## Product Principles

1. Never slower than the last version to open and switch.
2. Keyboard first; the mouse works but is never required.
3. Search is the reason to choose OmaSwitch; every surface makes matches visible and explains why a row matched.
4. Native to Omarchy: theme, icons, and setup feel like part of the desktop.
5. Never touch user config without an explicit action and a backup.

## Accessibility and Inclusion

- Selection is shown by more than color (outline or marker plus background).
- All actions reachable from the keyboard; `Escape` always closes.
- Text contrast comes from the theme's menu colors; check the overlay against light and dark Omarchy themes.
- Respect Omarchy's animation setting; no motion when animations are off.
