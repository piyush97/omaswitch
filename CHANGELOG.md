# Changelog

All notable changes to OmaSwitch. Versions match `manifest.json` and the [GitHub releases](https://github.com/piyush97/omaswitch/releases).

## [2.1.0]

### Added

- Click the live preview to switch to the window it shows. Previously a click on the preview closed the switcher without switching. Ported from a contribution by grothjan. ([#16](https://github.com/piyush97/omaswitch/pull/16))

## [2.0.0] — 2026-11-23

### Added

- Omit windows from the switcher by app/class or title pattern, configured in `~/.config/omarchy/omaswitch-omit.json` (`omit` or `exclude` arrays) and reloaded live. ([#23](https://github.com/piyush97/omaswitch/issues/23), [#24](https://github.com/piyush97/omaswitch/pull/24))
- Workspace groups, numbered results, and highlighted content snippets in the picker.
- Same-app cycling with `Alt+Grave`, close with `Ctrl+W`, and move to the focused workspace with `Ctrl+M`.
- Settings for window scope, grouping, live previews, and content search.
- Opt-in `Alt+Tab` setup and removal with backups and rollback on reload errors.

### Changed

- Open the switcher on the focused monitor.
- Split picker UI and capture services into separate components, with regression tests for window selection and binding updates.
- The switcher opens faster: it no longer rescans the whole icon theme on every open. ([#27](https://github.com/piyush97/omaswitch/pull/27))
- Settings and the setup banner use Omarchy's themed controls, with a visible focus border for keyboard users. ([#29](https://github.com/piyush97/omaswitch/pull/29))

### Fixed

- The picker follows the theme on Qt 6.12 (Omarchy 4.5) instead of drawing an unthemed white card. ([#26](https://github.com/piyush97/omaswitch/pull/26))
- Content search finds text in windows on fractionally scaled (for example 1.5x) monitors, and OCR runs faster there. ([#28](https://github.com/piyush97/omaswitch/pull/28))
- Typing a plain `i` finds the dotted capital `İ` in titles and window text. ([#28](https://github.com/piyush97/omaswitch/pull/28))
- Settings copies the `ALT + GRAVE` bind line for same-app cycling instead of an unbind line. ([#28](https://github.com/piyush97/omaswitch/pull/28))
- A binding rollback error clears once `bindings.lua` changes or is removed. ([#28](https://github.com/piyush97/omaswitch/pull/28))

## [1.3.3] — 2026-11-21

### Fixed
- Search highlights in the preview now stay on the matched word when the window text contains letters that grow when lowercased, such as the Turkish dotted capital I (`İ`). Previously the box could drift onto the next word or disappear. ([#19](https://github.com/piyush97/omaswitch/pull/19))
- Long window titles and details that are cut off at an emoji no longer end in a broken replacement glyph; the whole emoji is dropped instead. ([#20](https://github.com/piyush97/omaswitch/pull/20))

## [1.3.2] — 2026-11-21

### Fixed
- Closed apps (for example Spotify) no longer linger in the switcher. Quickshell can keep toplevels it recreated from late title or focus events; the switcher now skips windows with no workspace. ([#13](https://github.com/piyush97/omaswitch/issues/13))
- On Omarchy 4.5, the selected window now comes to the front in floating layouts. Focus is followed by `alter_zorder` top, since Lua `hl.dsp.focus` moves focus without raising. ([#14](https://github.com/piyush97/omaswitch/issues/14))

## [1.3.1] — 2026-10-06

### Fixed
- High-DPI/4K OCR no longer shrinks 12px text to 6px. Captures enlarge glyphs up to 2x, preserve aspect ratio, and cap the physical long edge at 7680 pixels independently of display scaling. ([#12](https://github.com/piyush97/omaswitch/issues/12))

## [1.3.0] — 2026-10-04

### Added
- When a window matches only on visible text, the preview outlines where that text appears, using Tesseract's page layout analysis. ([#8](https://github.com/piyush97/omaswitch/issues/8))

### Fixed
- OCR captures were clamped per axis to 1280×720, distorting aspect ratio and dropping small text. Captures now scale uniformly (long edge 1920), and the per-window OCR budget is 8 s.

## [1.2.0] — 2026-10-04

### Added
- Search by text visible inside windows, using on-device OCR with Omarchy's bundled Tesseract. Starts after three typed characters; metadata matches still appear instantly. ([#8](https://github.com/piyush97/omaswitch/issues/8))
- `OMARCHY_OCR_LANGS` selects installed OCR languages.

### Security
- OCR runs without a shell; window addresses and language settings are validated before use.
- Captures are deleted after scanning and extracted text is discarded when the switcher closes.

## [1.1.2] — 2026-10-04

### Added
- Application icons in the window list. ([#6](https://github.com/piyush97/omaswitch/pull/6), @ovsw)

### Fixed
- `Alt+Tab` intermittently leaving focus unchanged — the selection now applies after the overlay unmaps. ([#7](https://github.com/piyush97/omaswitch/pull/7), @ekropotin)
- Most-recently-used order across workspaces, plus a Qt 6.11 crash guard for rapid cycling. ([#5](https://github.com/piyush97/omaswitch/pull/5), @ovsw)
- Switcher resizing while previews load. ([#11](https://github.com/piyush97/omaswitch/pull/11), @kandosol; closes [#10](https://github.com/piyush97/omaswitch/issues/10))
- Preview flicker and transitions, via double-buffered preview handoff. ([#9](https://github.com/piyush97/omaswitch/pull/9), @zkiss)
- A preview capture that never produced a frame could block every later selection.
- The window list no longer retains compositor-owned window objects, and previews release a window before it is destroyed.

### Documentation
- Clarified that installing does not replace Omarchy's default `Alt+Tab` bindings.

[2.0.0]: https://github.com/piyush97/omaswitch/releases/tag/v2.0.0
[1.3.3]: https://github.com/piyush97/omaswitch/releases/tag/v1.3.3
[1.3.2]: https://github.com/piyush97/omaswitch/releases/tag/v1.3.2
[1.3.1]: https://github.com/piyush97/omaswitch/releases/tag/v1.3.1
[1.3.0]: https://github.com/piyush97/omaswitch/releases/tag/v1.3.0
[1.2.0]: https://github.com/piyush97/omaswitch/releases/tag/v1.2.0
[1.1.2]: https://github.com/piyush97/omaswitch/releases/tag/v1.1.2
