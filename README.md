# OmaSwitch

[![CI](https://github.com/piyush97/omaswitch/actions/workflows/ci.yml/badge.svg)](https://github.com/piyush97/omaswitch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/piyush97/omaswitch)](https://github.com/piyush97/omaswitch/releases/latest)
[![Omarchy plugin](https://img.shields.io/badge/Omarchy-plugin-0f172a)](https://omarchyplugins.com/plugin.html?id=piyush.omaswitch)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**The `Alt+Tab` Omarchy was missing: recent windows first, live previews, and search by what's actually on screen.**

![OmaSwitch showing a live terminal preview](preview.png)

OmaSwitch is a keyboard-first window switcher overlay for [Omarchy](https://omarchy.org/). Tap `Alt+Tab` to jump back to your last window, keep tapping to walk your history, or start typing to find a window by its title, app, workspace — or **any text visible inside it**.

**Write-up:** [OmaSwitch: The Alt+Tab Omarchy Has Been Missing](https://piyushmehta.com/blog/omaswitch-alt-tab-omarchy)

## Features

- **Recent windows first.** Global most-recently-used order across all workspaces, so the window you want is usually one tap away.
- **Live preview.** The highlighted window streams live in a side pane — no stale screenshots — with smooth, flicker-free handoff as you cycle.
- **Search what you saw.** Type three or more characters and OmaSwitch reads the text inside your windows with on-device OCR. Remember an error code but not which of six terminals printed it? Type the code.
- **See where it matched.** When a window matches only on its contents, the preview outlines exactly where that text appears.
- **Keyboard-first, mouse-friendly.** Cycle, filter, and confirm without leaving the home row; click works too.
- **Native to Omarchy.** Follows your active theme, uses app icons from your desktop entries, and needs no daemon, extra package, or elevated privilege.

## See it in action

**Pick the project window without leaving the keyboard.** Search or cycle, then confirm with `Enter`.

![OmaSwitch with a project terminal preview](screenshots/terminal-preview.png)

**Check a live preview before switching.** The preview follows the selection, so similarly named windows are easy to tell apart.

![OmaSwitch with a live btop preview](screenshots/btop-preview.png)

## Install

```bash
omarchy plugin add https://github.com/piyush97/omaswitch.git --enable
```

It installs into your user configuration. Nothing else is required — OCR uses the `tesseract` package that Omarchy already ships.

### Requirements

| Requirement | Why | If missing |
| --- | --- | --- |
| Omarchy Quattro (Quickshell + Hyprland) | Hosts the overlay | Plugin cannot load |
| `hyprland-toplevel-export-v1` | Live previews and OCR captures | Switching and title search still work; preview pane stays empty |
| `tesseract` (bundled with Omarchy) | Search inside window contents | Title/app/workspace search still works |

## Make it your Alt+Tab

> **Installing does not change your keybindings.** Omarchy's default `Alt+Tab` cycles windows directly and will keep doing so until you replace it. This one-time step is what most "it doesn't open" reports come down to.

Add this to `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

o.bind("ALT + TAB", "OmaSwitch", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":1}'")
o.bind("ALT + SHIFT + TAB", "OmaSwitch (reverse)", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":-1}'")
```

Reload and confirm there are no errors:

```bash
hyprctl reload
hyprctl configerrors
```

Prefer to keep Omarchy's defaults? Bind either `summon` command to a different key instead. To open the searchable picker directly (no cycling):

```bash
omarchy-shell shell toggle piyush.omaswitch
```

## Usage

| Key | Action |
| --- | --- |
| `Alt+Tab` | Open and move to the next recent window |
| `Alt+Shift+Tab` | Open and move backward |
| `Tab`, `↓`, `→` | Next window |
| `Shift+Tab`, `↑`, `←` | Previous window |
| Type | Filter by title, app, workspace, or visible text |
| `Backspace` / `Ctrl+Backspace` | Delete a character / word |
| `Ctrl+U` | Clear the search |
| `Enter` or click | Focus the selected window |
| `Esc` or click outside | Close without switching |

## Searching window contents

Type at least three characters. Title, app, and workspace matches appear instantly; OmaSwitch then scans your open windows one at a time and adds content matches as they arrive (the header shows *searching contents…* while it works).

When a window matches **only** because of text inside it, the preview draws a box around each occurrence, using Tesseract's page layout analysis to locate the words.

**Languages.** OCR defaults to English. To add others, install the Tesseract language pack and set `OMARCHY_OCR_LANGS` in the environment the shell starts with:

```bash
sudo pacman -S tesseract-data-fra
# then, e.g. in your session environment:
OMARCHY_OCR_LANGS=eng+fra
```

**What OCR can't see.** Very small text, low-contrast text, and stylised fonts may be missed. Windows that can't be captured still match by title, app, and workspace.

### Privacy

OCR runs entirely on your machine — there is no network request and no AI service.

- Each capture is written to your private runtime directory (`$XDG_RUNTIME_DIR`) only while it is scanned, then deleted.
- Extracted text lives in memory only and is discarded when the switcher closes.
- Scanning starts only after you type a search; simply cycling with `Alt+Tab` never runs OCR.

## Update or remove

```bash
omarchy plugin update piyush.omaswitch --yes
```

```bash
omarchy plugin disable piyush.omaswitch
omarchy plugin remove piyush.omaswitch --yes
```

If you added the `Alt+Tab` bindings above, remove them from `bindings.lua` too, or `Alt+Tab` will do nothing.

## Troubleshooting

<details>
<summary><b>Alt+Tab still cycles windows directly</b></summary>

The default bindings are still active. Make sure both `hl.unbind` lines are present, then:

```bash
hyprctl reload
hyprctl configerrors
omarchy menu keybindings --print | grep -E 'ALT \+ TAB|OmaSwitch'
```

</details>

<details>
<summary><b>The plugin isn't listed</b></summary>

```bash
omarchy-shell shell rescanPlugins
omarchy plugin list --json
```

</details>

<details>
<summary><b>It opens, but there's no preview</b></summary>

The selected window may not be capturable, or your compositor lacks `hyprland-toplevel-export-v1`. This is expected fallback behavior — the list stays fully usable.

</details>

<details>
<summary><b>Searching doesn't find text I can see</b></summary>

Check that Tesseract and your language data are installed (`tesseract --list-langs`), and that `OMARCHY_OCR_LANGS` names only installed languages. Small or low-contrast text is a known OCR limit. If something reasonable is still missed, please [open an issue](https://github.com/piyush97/omaswitch/issues/new) with the app and roughly what was on screen.

</details>

<details>
<summary><b>Quickshell crashed</b></summary>

There is a known upstream Quickshell crash on Qt 6.11.x (`QObjectWrapper::wrap`) that also affects setups without OmaSwitch. To check whether OmaSwitch is involved, run `omarchy plugin disable piyush.omaswitch` and see if the crash persists. Please include the crash report in an issue either way.

</details>

<details>
<summary><b>A QML error appears</b></summary>

```bash
journalctl --user -f | grep -Ei 'piyush.omaswitch|Switcher.qml|qml.*(error|warning)'
```

</details>

## How it works

| File | Role |
| --- | --- |
| [`Switcher.qml`](Switcher.qml) | The overlay: window list, double-buffered live preview, OCR capture queue, keyboard handling |
| [`Model.js`](Model.js) | Pure logic — MRU ordering, filtering, OCR layout parsing, highlight geometry — testable without a compositor |
| [`test_model.js`](test_model.js) | Regression suite, including the preview and OCR lifecycle |
| [`manifest.json`](manifest.json) | Omarchy plugin manifest |

Design choices worth knowing:

- **No per-window streams.** Two capture views handle smooth preview handoff; a single extra capture runs only during an OCR search.
- **No retained window objects.** The list holds plain snapshots, never compositor-owned objects, so a window closing mid-switch can't leave a dangling reference.
- **Focus lands after the overlay closes.** Hyprland restores focus when the overlay unmaps; OmaSwitch applies your selection after that, so the switch always sticks.

## Contributing

Bug reports, ideas, and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Release history is in [CHANGELOG.md](CHANGELOG.md).

Thanks to everyone who has contributed fixes and features, including [@ekropotin](https://github.com/ekropotin), [@ovsw](https://github.com/ovsw), [@kandosol](https://github.com/kandosol), [@zkiss](https://github.com/zkiss), and [@jefflord-pmg](https://github.com/jefflord-pmg) for the OCR idea.

## License

[MIT](LICENSE). OmaSwitch is an independent community plugin and is not affiliated with Omarchy.
