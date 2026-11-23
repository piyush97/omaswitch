# OmaSwitch v2 manual test

Run this checklist on Omarchy before tagging `v2.0.0`. Use a disposable Hyprland config for the setup and rollback cases. Keep a copy of your real `~/.config/hypr/bindings.lua` outside the plugin directory.

From the v2 checkout, run `node --test tests/*.test.js`. Load the checkout through your local Omarchy plugin setup, then run:

```bash
omarchy-shell shell toggle piyush.omaswitch
```

## Switch and search

- [ ] Open at least three apps across two workspaces. Confirm `Alt+Tab`, reverse `Alt+Shift+Tab`, and release-to-focus preserve MRU behavior. Repeat with `Alt+Grave` for an app with multiple windows.
- [ ] In the picker, group windows by workspace. Confirm arrows skip headers, results stay numbered in display order, and `Alt+1` through `Alt+9` select the numbered windows when Hyprland does not claim those keys.
- [ ] Search by title and by a unique phrase visible in a terminal. Confirm the content search status clears, the phrase appears in a snippet, and the preview highlights the match. Repeat on a high-DPI monitor.
- [ ] Open the picker with no open windows, with a scope containing no windows, and with a query that has no matches. Confirm the messages distinguish these cases.
- [ ] Close a disposable window with `Ctrl+W`; the picker stays open and the row disappears. Move a window from another workspace with `Ctrl+M`; the picker closes and the moved window receives focus.

## Appearance and settings

- [ ] On two monitors, open the picker from each monitor. Confirm it opens on the focused monitor, and current-monitor and current-workspace scopes show only the corresponding windows.
- [ ] Open settings with `Ctrl+,`. Cycle focus with `Tab`, change scope, disable previews and content search, then press `Esc`. Confirm title filtering still works and the list uses the full width. Reopen after a shell restart and confirm settings persisted.
- [ ] In light and dark themes, check the selection marker, text contrast, long titles, narrow layout, and `?` shortcut help with previews off. Confirm `Esc` returns from help to results before closing the picker.

## Bindings

- [ ] With a disposable `bindings.lua` and no OmaSwitch lines, open the picker. Confirm there is no file change before clicking **Use OmaSwitch for Alt+Tab**. After clicking, confirm a timestamped backup exists and all three bindings work.
- [ ] Click **Remove OmaSwitch bindings**. Confirm only the marked block disappears. With hand-written v1 bindings, confirm the setup banner stays hidden and **Copy** in settings provides the optional same-app binding without editing the file.
- [ ] In a disposable session, make Hyprland report a new configuration error after the setup write. Confirm the pre-change bytes are restored and the picker reports the error. Separately confirm an unchanged pre-existing error does not trigger rollback.
- [ ] With no `bindings.lua`, confirm the picker offers manual setup instructions and does not create a file.

If any check fails, record the Omarchy, Hyprland, and Quickshell versions and the shortest reproduction. Do not tag the release until the checklist passes.
