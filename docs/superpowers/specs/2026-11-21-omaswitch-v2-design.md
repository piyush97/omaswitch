# OmaSwitch v2 design

Status: draft for owner approval (2026-11-21)
Product context: [PRODUCT.md](../../../PRODUCT.md)

## Intent

v2 is a redesign and feature overhaul of OmaSwitch, aimed at two outcomes the owner named:

1. More Omarchy users install it and keep using it.
2. It works as a portfolio piece that shows product thinking and engineering craft.

The marketplace has about 20 window switcher or overview plugins. The most-starred (Exposé 47, altswitch 26, omalt-tab 25; OmaSwitch 14, all as of 2026-11-21) compete on grids, animations, and hot corners. None search inside windows. v2 makes that search the headline and removes the friction that stops people from adopting it.

## Goals

- Search that explains itself: every OCR match shows the matching line in the row.
- Rows a person can scan in under a second: app icon, title, workspace, and match snippet.
- Fewer keystrokes to common targets: same-app cycling, direct jump keys, workspace grouping.
- Act on windows without leaving the switcher: close, move to the current workspace.
- One-click setup of `Alt+Tab` from inside the overlay.
- A settings page for the handful of choices users actually differ on.
- A codebase a contributor can read: small QML components, pure JS logic with node tests.

## Non-goals (v2.0)

- Exposé-style grid of all windows. Possible v2.1 if users ask.
- Own color palette or fonts. The active Omarchy theme stays the visual identity.
- Support outside Omarchy Quattro (plain Hyprland, other shells).
- Reopening closed windows, window rules, tiling or layout management.
- Hot corners, gestures.

## Anti-goals (fail even if it works)

- Opening or switching slower than v1.3.3.
- Breaking existing bindings. These payloads must keep working unchanged:
  - `omarchy-shell shell summon piyush.omaswitch '{"mode":"cycle","direction":1}'`
  - `omarchy-shell shell summon piyush.omaswitch '{"mode":"cycle","direction":-1}'`
  - `omarchy-shell shell toggle piyush.omaswitch`
- Editing `bindings.lua` without an explicit click, a backup, and an automatic restore when Hyprland reports errors.
- Requiring new packages, a daemon, or sudo.
- OCR text leaving the machine or persisting to disk after the overlay closes.

## Constraints

- Quickshell QML plugin, manifest `kinds: ["overlay"]`, `keepLoaded: true`, plugin id `piyush.omaswitch`.
- Settings stored in the plugin entry of `~/.config/omarchy/shell.json` via the shell's `updateEntryInline` (the pattern Exposé uses in `PluginSettings.qml`).
- Icons via Quickshell `DesktopEntries` and `Quickshell.iconPath`; `Model.desktopEntryForWindow` already maps windows to entries.
- CI runs `node test_model.js`, a manifest JSON parse, and whitespace checks. New logic must be testable under plain node.
- The build machine has no Omarchy desktop. Visual and interactive verification happens on the owner's machine with a manual checklist.

## Approaches considered

| | Approach | Trade-off | Decision |
|---|---|---|---|
| A | Best Alt+Tab built around search: redesign list + preview, add search snippets, icons, grouping, same-app cycling, jump keys, actions, settings, setup | Sharp identity nobody else has; does not compete with grid overviews | **Chosen** (owner, 2026-11-21) |
| B | A plus an Exposé-style grid mode | Wider appeal, about twice the work, head-on with the most-starred plugin, muddier pitch | Rejected for v2.0; grid is a v2.1 candidate |
| C | Search-first command palette for windows | Most distinctive, hardest to explain in one line, slower adoption | Rejected |

Layout options: (1) list left with large live preview right, (2) preview on top with list below, (3) compact list with delayed preview. **Layout 1 chosen** (owner): keeps the live preview people notice, best on wide screens, room for snippets.

## Design

### Layout

```
┌──────────────────────────────────────────────────────────────┐
│ ⌕ search windows and their contents           ⚙  ? shortcuts │
├────────────────────────┬─────────────────────────────────────┤
│ WORKSPACE 1            │                                     │
│ ▣ kitty      ~/oma…  1 │                                     │
│   "npm run build fai…" │          live preview               │
│ ▣ firefox    GitHub  2 │          (selected window)          │
│ WORKSPACE 3            │                                     │
│ ▣ code       Model.js 3│                                     │
├────────────────────────┴─────────────────────────────────────┤
│ Enter switch · Ctrl+W close · Ctrl+M move here · Alt+1-9 jump│
└──────────────────────────────────────────────────────────────┘
```

- List column about 40% width, preview fills the rest, as in v1.
- Row: app icon, app name, title (elided), jump number 1 to 9 for the first nine rows in display order.
- When the row matched through OCR, a second line shows the matched line, trimmed around the match, with the match highlighted. Metadata matches highlight inside the title.
- Workspace header rows when grouping is on, in picker mode only. Groups follow MRU order of their most recent window; inside a group, MRU order.
- Cycle mode (Alt held) always shows a flat MRU list with no headers, so one `Alt+Tab` lands on the row directly below the current window and the selection never jumps between groups. Grouping only applies once the picker is open for searching.
- Jump numbers 1 to 9 always count on-screen row order (header rows skipped), so the number shown is the number pressed.
- Footer hint line lists the active keys. Hidden in cycle mode (Alt held) to stay quiet.
- Empty state: "No windows" when nothing is open; "No match for "<query>"" plus "Searching window contents…" while OCR runs.
- Opens on the monitor that has keyboard focus.

### Modes and keys

| Context | Key | Action |
|---|---|---|
| Cycle (Alt held) | `Tab` / `Shift+Tab` | Next / previous in MRU (unchanged) |
| Cycle | release `Alt` | Switch to selected (unchanged) |
| Cycle | `` ` `` while Alt held (the `ALT + GRAVE` binding) | Next window of the selected row's app |
| Cycle | `1`-`9` while Alt held | Switch to that row now |
| Picker | type | Filter; OCR search starts at 3 characters (unchanged) |
| Picker | `Alt+1`-`Alt+9` | Switch to that row |
| Both | `Ctrl+W` | Close selected window (Hyprland close request; the app may still prompt) |
| Both | `Ctrl+M` | Move selected window to the current workspace and focus it |
| Both | `Ctrl+,` | Open settings view |
| Both | `Escape` | Close overlay, or leave settings view |
| Both | `Enter` / click | Switch |

Same-app cycling runs through the summon payload `summon piyush.omaswitch '{"mode":"cycle","scope":"app","direction":1}'`, bound to `ALT + GRAVE`. Hyprland handles that key before the overlay sees it, so the logic lives in the summon handler (as v1 already does for a repeat summon while open), not in `Keys.onPressed`:

- Overlay closed: open in cycle mode listing only windows of the focused window's app, selection on the second one.
- Overlay open: move to the next window of the selected row's app.

`1`-`9` and `Alt+1`-`Alt+9` are handled in `Keys.onPressed`. If the user has bound those chords in Hyprland, Hyprland wins; the README says so. Omarchy's default bindings use `SUPER` plus digits for workspaces, so `Alt` plus digits is normally free.

After `Ctrl+W`, the row stays (dimmed) until Hyprland reports the window gone, so an app that shows a save prompt does not leave a missing row.

### Settings

Stored in the plugin's `shell.json` entry. Shown in a settings view inside the overlay.

| Key | Values | Default |
|---|---|---|
| `scope` | `all`, `workspace`, `monitor` | `all` |
| `groupByWorkspace` | bool | `true` |
| `livePreview` | bool | `true` |
| `contentSearch` (OCR) | bool | `true` |
| `setupDismissed` | bool | `false` |

Invalid or missing values fall back to defaults and never overwrite the file.

### First-run setup

1. On open, read `~/.config/hypr/bindings.lua`. If it contains no `piyush.omaswitch` summon and `setupDismissed` is false, show a one-line banner: "Alt+Tab still opens Omarchy's switcher. [Use OmaSwitch for Alt+Tab] [Not now]".
2. On click:
   1. Copy `bindings.lua` to `bindings.lua.omaswitch-<timestamp>.bak`.
   2. Append a marked block (`-- OmaSwitch begin` / `-- OmaSwitch end`) with the unbinds and binds from the README.
   3. Record `hyprctl configerrors` before the change. Run `hyprctl reload`, then `hyprctl configerrors` again.
   4. Restore only if the new error output contains lines that were not there before. Pre-existing errors elsewhere in the user's config do not block setup. On restore: put the backup back, reload again, and show the new error lines with a link to the README steps.
3. "Not now" sets `setupDismissed`. The settings view keeps a "Set up Alt+Tab" button.
4. If `bindings.lua` does not exist, show the README command instead of the button.
5. The block contains: `hl.unbind` for `ALT + TAB`, `ALT + SHIFT + TAB`, and `ALT + GRAVE`, then `o.bind` for all three (forward cycle, reverse cycle, same-app cycle).
6. Users who added v1 bindings by hand (a `piyush.omaswitch` summon outside the marked block) count as set up; no banner. If they have no `"scope":"app"` binding, the settings view shows the one line to add, with a copy button. Their hand-written lines are never edited.
7. The settings view has "Remove OmaSwitch bindings" when the marked block exists: it takes a fresh backup, strips the block, reloads, and runs the same error check. A plugin cannot run code on uninstall, so the README uninstall steps tell users to press this first or delete the block by hand.

The text transforms (detect existing binding, build block, strip block) are pure functions in `Bindings.js` with node tests.

### Code structure

| File | Role |
|---|---|
| `Switcher.qml` | Overlay root: summon/IPC handling, state, key routing |
| `components/SearchField.qml` | Query input, settings and help buttons |
| `components/WindowList.qml`, `components/WindowRow.qml`, `components/GroupHeader.qml` | List, rows, headers |
| `components/PreviewPane.qml` | The two alternating ScreencopyViews from v1, unchanged logic |
| `components/SetupBanner.qml`, `components/SettingsView.qml`, `components/FooterHints.qml` | Setup, settings, hints |
| `services/OcrIndexer.qml` | OCR queue, capture, tesseract process (moved from `Switcher.qml`) |
| `services/PluginSettings.qml` | Read `shell.json`, write via `updateEntryInline` |
| `Model.js` | Existing filter/sort/OCR logic plus grouping, jump numbering, snippets, scope filter |
| `Bindings.js` | Binding detection and patch text |
| `Settings.js` | Schema, defaults, validation |
| `tests/*.test.js` | Node tests; CI runs all of them |

Behavior from v1 that must survive: MRU history, stale toplevel filtering (#13), raising floating windows after focus (#18), OCR highlight alignment with Unicode case folding (#19), emoji-safe truncation (#20), HiDPI OCR (#12).

### Release

- Version 2.0.0, CHANGELOG entry, manifest gains `icon` and `preview` fields.
- README rewritten around search: new screenshots and a short screen recording made by the owner on Omarchy.
- Update the marketplace listing (verify issue against the release commit).
- Update the blog post with what changed in v2.

## Decided vs open

Decided by owner: approach A, layout 1, goals adoption plus portfolio.

Decided in this doc (owner can override at approval): key map above, settings list, setup flow with backup and auto-restore, file structure, `ALT + GRAVE` for same-app cycling.

Settled after the builder check (2026-11-21): cycle mode is flat MRU and grouping applies to the picker only; jump numbers follow on-screen order; same-app cycling is handled by the summon handler; setup restores only on new config errors; the block includes `ALT + GRAVE`; hand-written v1 bindings are left alone; settings offers removal of the block. v2 work starts from `v1.3.3` (`89d681a`).

Left to the builder:
- Exact spacing, row height, icon size, and snippet length, within the theme's `Style` scale.
- How the settings view is laid out inside the overlay.
- Internal component APIs and how state is passed.
- Test organization beyond "pure logic has node tests".

## Verification

- Node tests for all pure logic (model, grouping, snippets, bindings patch, settings validation).
- Manual checklist on the owner's Omarchy machine: every key in the table, setup on a fresh `bindings.lua` and on one that already binds OmaSwitch, failed reload restore, light and dark themes, two monitors, OCR on a HiDPI display, existing summon payloads.
- Open speed compared with v1.3.3 on the same machine, by eye and with a screen recording.
