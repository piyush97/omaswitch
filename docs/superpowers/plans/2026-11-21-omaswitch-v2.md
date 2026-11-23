# OmaSwitch v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship OmaSwitch 2.0.0: search snippets, workspace grouping, jump keys, same-app cycling, close/move actions, a settings view, one-click Alt+Tab setup, and a split, tested codebase.

**Architecture:** Pure logic lives in plain JS files (`Model.js`, `Settings.js`, `Bindings.js`) usable both from QML (`import "X.js" as X`) and from node (`module.exports` guard, as `Model.js` does today). QML is split into `services/` (no UI: settings store, OCR indexer, bindings runner) and `components/` (UI pieces). `Switcher.qml` stays the overlay root and owns state and key routing.

**Tech Stack:** Quickshell QML (Qt 6), Quickshell.Hyprland / Quickshell.Wayland, Omarchy Shell plugin host (`qs.Commons`, `qs.Ui`), node 22 `node --test` for logic tests.

**Spec:** `docs/superpowers/specs/2026-11-21-omaswitch-v2-design.md` (read it first; product context in `PRODUCT.md`).

## Global Constraints

- Plugin id stays `piyush.omaswitch`; manifest `kinds: ["overlay"]`, `keepLoaded: true`.
- These payloads keep working unchanged: `{"mode":"cycle","direction":1}`, `{"mode":"cycle","direction":-1}`, and `omarchy-shell shell toggle piyush.omaswitch`.
- No new packages, daemons, or sudo. Only `hyprctl`, `tesseract`, `cp`, `rm`, `timeout`, which v1 already relies on or Omarchy ships.
- OCR text stays in memory; temp capture files are deleted as in v1.
- Colors, fonts, radius come only from `Color.menu.*`, `Style.font.menuFamily`, `Style.cornerRadius`, `Style.space()`. No hard-coded colors.
- Selection is shown by more than color. `Escape` always closes (or leaves the settings view).
- No motion when Omarchy animations are off (reuse v1's `geometryAnimationsReady` gating and the theme's animation flag).
- Keep v1 fixes: stale toplevels (#13, `Model.managedWindows`), raise after focus (#18, `Model.focusCommand`), OCR highlight Unicode alignment (#19), emoji-safe truncation (#20), HiDPI OCR (#12).
- Commit messages: Conventional Commits, no `Co-authored-by` trailers. No em dash characters in user-facing copy.
- Every task ends with `node --test tests/` passing.
- The build machine has no Omarchy desktop. QML tasks are verified by tests of the logic they call plus the owner's manual checklist (Task 12). Do not claim QML behavior was observed.

## Review Focus

1. **Window closes while the overlay is open** (including after `Ctrl+W`): selection must stay on a valid row, jump numbers re-number, no crash on a stale `selectedIndex`. Test: `Model.clampSelection` in Task 3.
2. **`bindings.lua` with CRLF line endings or no trailing newline**: append/strip must not merge lines or leave stray blank lines. Tests in Task 4.
3. **Same-app cycle when the app has one window, or the selected row has no app id**: stays put, no error. Test in Task 3 (`appCycleIndex`).
4. **OCR snippet for a match near the start or end of a very long line, or text with emoji**: snippet never splits a surrogate pair and stays within the length cap. Test in Task 3 (`matchSnippet`).
5. **`shell.json` with this plugin's entry missing, extra unknown keys, or wrong types**: defaults apply, unknown keys survive writes. Tests in Task 2.

---

### Task 1: Test layout and CI

**Files:**
- Move: `test_model.js` -> `tests/model.test.js` (fix the require path to `../Model.js`)
- Modify: `.github/workflows/ci.yml` (step "Model tests")
- Modify: `CONTRIBUTING.md` (test command)

**Interfaces:**
- Produces: convention `tests/<name>.test.js`, each requiring `../<Name>.js`, run by `node --test tests/`.

- [ ] **Step 1:** `git mv test_model.js tests/model.test.js`, change `require("./Model.js")` to `require("../Model.js")`.
- [ ] **Step 2:** Run `node --test tests/`. Expected: 1 file, pass.
- [ ] **Step 3:** In `ci.yml`, rename the step to "Tests" and run `node --test tests/`. Update the test command in `CONTRIBUTING.md`.
- [ ] **Step 4:** Commit `test: move tests under tests/ and run with node --test`.

### Task 2: Settings schema

**Files:**
- Create: `Settings.js`, `tests/settings.test.js`

**Interfaces:**
- Produces:
  - `Settings.defaults` = `{ scope: "all", groupByWorkspace: true, livePreview: true, contentSearch: true, setupDismissed: false }`
  - `Settings.read(entry: object|null) -> object`: defaults merged with valid values from `entry`; invalid types or unknown `scope` values fall back to the default per key.
  - `Settings.patch(entry: object|null, key: string, value) -> object|null`: a full entry for `updateEntryInline` (copy of `entry` with the key set, unknown keys kept, `id` removed); `null` when `key` is unknown or `value` invalid.
  - `Settings.scopes` = `["all", "workspace", "monitor"]`

- [ ] **Step 1: Write failing tests**

```js
assert.deepEqual(Settings.read(null), Settings.defaults)
assert.deepEqual(Settings.read({ scope: "monitor", livePreview: false }).scope, "monitor")
assert.equal(Settings.read({ scope: "galaxy" }).scope, "all")
assert.equal(Settings.read({ groupByWorkspace: "yes" }).groupByWorkspace, true)
assert.deepEqual(Settings.patch({ id: "piyush.omaswitch", extra: 1 }, "contentSearch", false), { extra: 1, contentSearch: false })
assert.equal(Settings.patch({}, "scope", "galaxy"), null)
assert.equal(Settings.patch({}, "nope", true), null)
```

- [ ] **Step 2:** Run `node --test tests/settings.test.js`. Expected: FAIL, cannot find module.
- [ ] **Step 3:** Implement `Settings.js` with the `module.exports` guard used in `Model.js`.
- [ ] **Step 4:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: add settings schema`.

### Task 3: Model additions for rows, snippets, jumps, scope, app cycling

**Files:**
- Modify: `Model.js` (add functions, extend `module.exports`)
- Test: `tests/model.test.js`

**Interfaces:**
- Consumes: existing `appId`, `addressKey`, `ocrText`, `metadataMatches`, `boundedText`.
- Produces:
  - `scopedWindows(windows, scope: "all"|"workspace"|"monitor", ctx: { workspaceId, monitorName }) -> windows`. `workspace` keeps `w.workspace.id === ctx.workspaceId`; `monitor` compares `ctx.monitorName` with `w.monitor.name`, falling back to `w.workspace.monitor.name` (check which one Quickshell's `HyprlandToplevel` exposes; support both); missing ctx value means no filtering.
  - `titleMatch(window, query) -> { before, match, after } | null`: first case-insensitive match of the trimmed query in `label(window)`, original case preserved, for highlighting metadata matches in the title. `null` for an empty query or no match.
  - `displayRows(windows, opts: { group: bool }) -> Array<{ kind: "header", workspaceId, label } | { kind: "window", window, jump: number|null }>`. Group order follows the first appearance of each workspace in `windows` (already MRU sorted). `jump` is 1..9 for the first nine window rows in on-screen order, else `null`. With `group: false`, no header rows. Header `label` is `"Workspace " + id`; special workspaces (negative id or name starting `special`) use `"Special " + name`.
  - `windowRowIndex(rows, n: number) -> number`: index into `rows` of the window row with `jump === n`, or `-1`.
  - `stepWindowRow(rows, from: number, delta: number) -> number`: next index with `kind === "window"`, wrapping, skipping headers; `-1` if none.
  - `clampSelection(rows, index: number) -> number`: nearest window row at or before `index`, else first window row, else `-1`.
  - `matchSnippet(window, query, ocrByAddress, maxLength = 80) -> { before, match, after } | null`. Only for OCR-only matches (`null` when `metadataMatches`). Uses the first OCR line containing the query (case-insensitive, same per-word lowercasing as `ocrHighlights` for #19). Centers the match; trims at word boundaries; adds `"…"` to the trimmed side; never splits a surrogate pair; total length of the three parts <= `maxLength`.
  - `appCycleIndex(rows, from: number, direction: 1|-1) -> number`: next window row (wrapping) whose `appId` equals the app of `rows[from]`; returns `from` when there is no other or the app id is empty.
  - `closeTarget(window) -> string|null` and `moveHereLua(window, workspaceId) -> string|null`: `moveHereLua` returns `"(function() hl.dispatch(hl.dsp.window.move({ workspace = '<id>', follow = false, window = 'address:<addr>' })) end)"` for `Hyprland.dispatch` (pattern verified in the Exposé plugin), `null` without address or when the window is already on that workspace. `closeTarget` returns the normalized address or `null`.

- [ ] **Step 1: Write failing tests** (use fixtures shaped like the existing ones in `tests/model.test.js`)

```js
// scope
assert.deepEqual(Model.scopedWindows([a1, b2], "workspace", { workspaceId: 2 }), [b2])
assert.deepEqual(Model.scopedWindows([a1, b2], "monitor", { monitorName: "DP-1" }), [a1])
assert.deepEqual(Model.scopedWindows([a1, b2], "workspace", {}), [a1, b2])
// grouping and jumps
const rows = Model.displayRows([w1a, w2a, w1b], { group: true })
assert.deepEqual(rows.map(r => r.kind), ["header", "window", "window", "header", "window"])
assert.deepEqual(rows.filter(r => r.kind === "window").map(r => r.jump), [1, 2, 3])
assert.equal(rows[2].window, w1b)
assert.deepEqual(Model.displayRows([w1a, w2a], { group: false }).map(r => r.kind), ["window", "window"])
assert.equal(Model.displayRows(tenWindows, { group: false })[9].jump, null)
assert.equal(Model.windowRowIndex(rows, 3), 4)
assert.equal(Model.stepWindowRow(rows, 2, 1), 4)
assert.equal(Model.stepWindowRow(rows, 4, 1), 1)
assert.equal(Model.clampSelection(rows, 9), 4)
assert.equal(Model.clampSelection([], 0), -1)
// snippets
const ocr = { abc: "Build log\n  npm ERR! code ERR_404_DATABASE while fetching 🙂 more text here" }
assert.deepEqual(Model.matchSnippet(visualOnly, "err_404", ocr).match, "ERR_404")
assert.equal(Model.matchSnippet(active, "browser", ocr), null)
const s = Model.matchSnippet(visualOnly, "fetching", { abc: "x".repeat(300) + " fetching " + "🙂".repeat(100) }, 40)
assert.ok((s.before + s.match + s.after).length <= 40)
assert.ok(!/[\uD800-\uDBFF]$/.test(s.before + s.match + s.after))
// app cycling
assert.equal(Model.appCycleIndex(rows, 1, 1), 2) // two windows of the same app
assert.equal(Model.appCycleIndex(soloRows, 0, 1), 0)
// title highlight
assert.deepEqual(Model.titleMatch({ title: "GitHub - Pull" }, "hub"), { before: "Git", match: "Hub", after: " - Pull" })
assert.equal(Model.titleMatch({ title: "x" }, "  "), null)
// actions
assert.match(Model.moveHereLua({ address: "0xabc", workspace: { id: 3 } }, 1), /hl\.dsp\.window\.move\(\{ workspace = '1', follow = false, window = 'address:0xabc' \}\)/)
assert.equal(Model.moveHereLua({ address: "0xabc", workspace: { id: 1 } }, 1), null)
assert.equal(Model.closeTarget({}), null)
```

- [ ] **Step 2:** Run `node --test tests/model.test.js`. Expected: FAIL on the first new function.
- [ ] **Step 3:** Implement the functions in `Model.js`, export them.
- [ ] **Step 4:** Run `node --test tests/`. Expected: PASS, existing assertions untouched.
- [ ] **Step 5:** Commit `feat(model): rows, jump numbers, snippets, scope, app cycling, actions`.

### Task 4: Bindings text logic

**Files:**
- Create: `Bindings.js`, `tests/bindings.test.js`

**Interfaces:**
- Produces:
  - `Bindings.BEGIN = "-- OmaSwitch begin"`, `Bindings.END = "-- OmaSwitch end"`
  - `Bindings.block() -> string`: the marked block, exactly:

```lua
-- OmaSwitch begin
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.unbind("ALT + GRAVE")
o.bind("ALT + TAB", "OmaSwitch", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":1}'")
o.bind("ALT + SHIFT + TAB", "OmaSwitch (reverse)", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":-1}'")
o.bind("ALT + GRAVE", "OmaSwitch (same app)", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"scope\":\"app\",\"direction\":1}'")
-- OmaSwitch end
```

  - `Bindings.state(text: string) -> { managed: bool, handWritten: bool, hasAppScope: bool }`. `managed`: both markers present. `handWritten`: a non-comment line outside the markers contains `piyush.omaswitch`. `hasAppScope`: any non-comment line contains `"scope":"app"` (escaped or not).
  - `Bindings.needsSetup(text) -> bool`: `!managed && !handWritten`.
  - `Bindings.appendBlock(text) -> string`: keeps the file's line ending (`\r\n` if present), ensures exactly one blank line before the block and a trailing newline; idempotent when already `managed`.
  - `Bindings.stripBlock(text) -> string`: removes the block and the blank line added before it; unchanged when not managed.
  - `Bindings.newErrors(before: string, after: string) -> string[]`: trimmed non-empty lines of `after` absent from `before`.
  - `Bindings.appScopeLine() -> string`: the `ALT + GRAVE` `o.bind` line alone, for the copy button.

- [ ] **Step 1: Write failing tests**

```js
const stock = 'o.bind("SUPER + RETURN", "Terminal", "uwsm-app -- $TERMINAL")\n'
assert.equal(Bindings.needsSetup(stock), true)
const patched = Bindings.appendBlock(stock)
assert.equal(Bindings.state(patched).managed, true)
assert.equal(Bindings.appendBlock(patched), patched)
assert.equal(Bindings.stripBlock(patched), stock)
assert.equal(Bindings.stripBlock(Bindings.appendBlock("a\r\nb")), "a\r\nb\r\n")
assert.ok(!Bindings.appendBlock("a\r\nb").replace(/\r\n/g, "").includes("\n"))
assert.equal(Bindings.stripBlock(Bindings.appendBlock("x")), "x\n")
const hand = stock + "o.bind(\"ALT + TAB\", \"OmaSwitch\", \"omarchy-shell shell summon piyush.omaswitch '{\\\"mode\\\":\\\"cycle\\\"}'\")\n"
assert.deepEqual(Bindings.state(hand), { managed: false, handWritten: true, hasAppScope: false })
assert.equal(Bindings.needsSetup(hand), false)
assert.equal(Bindings.needsSetup("-- piyush.omaswitch\n"), true)
assert.deepEqual(Bindings.newErrors("old error\n", "old error\nnew error\n"), ["new error"])
assert.deepEqual(Bindings.newErrors("", "\n"), [])
```

- [ ] **Step 2:** Run `node --test tests/bindings.test.js`. Expected: FAIL.
- [ ] **Step 3:** Implement `Bindings.js` with the `module.exports` guard.
- [ ] **Step 4:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: add bindings patch logic`.

### Task 5: Extract services (no behavior change)

**Files:**
- Create: `services/OcrIndexer.qml`, `services/PluginSettings.qml`
- Modify: `Switcher.qml` (remove moved code, instantiate services)

**Interfaces:**
- Consumes: `Settings.read`, `Settings.patch`.
- Produces:
  - `OcrIndexer { property var windows; property string query; property bool enabled; readonly property var textByAddress; readonly property bool searching; function reset(); function cancel() }`. Move v1's OCR queue, capture `PanelWindow` (namespace `piyush-omaswitch-ocr`), `ocrProcess`, timeouts, and temp-file cleanup as is. Starts indexing when `enabled && query.trim().length >= 3`.
  - `PluginSettings { required property string pluginId; property var shell; readonly property var values /* Settings.read(entry) */; readonly property bool ready; function set(key, value) }`. Reads `~/.config/omarchy/shell.json` with a watched `FileView` (path from `Quickshell.env("HOME")`, not XDG), finds `plugins[]` entry by id, writes through `shell.updateEntryInline(pluginId, Settings.patch(entry, key, value))`. Keeps the pending value visible locally until the file reload confirms it (Exposé's `PluginSettings.qml` shows the pattern). Never writes when the file failed to parse.

- [ ] **Step 1:** Move OCR code into `services/OcrIndexer.qml`; `Switcher.qml` binds `windows`, `query`, `enabled: true` (setting wired in Task 10) and reads `textByAddress`.
- [ ] **Step 2:** Add `services/PluginSettings.qml`; instantiate in `Switcher.qml` with `pluginId: (root.manifest && root.manifest.id) || "piyush.omaswitch"`. Nothing reads it yet.
- [ ] **Step 3:** Run `node --test tests/`. Expected: PASS. Run `grep -n "ocr" Switcher.qml`: only uses of the indexer remain.
- [ ] **Step 4:** Commit `refactor: move OCR and settings into services`.

### Task 6: Extract components (no behavior change)

**Files:**
- Create: `components/SearchField.qml`, `components/WindowList.qml`, `components/WindowRow.qml`, `components/PreviewPane.qml`, `components/FooterHints.qml`
- Modify: `Switcher.qml`

**Interfaces:**
- Produces (properties in, signals out; components never call `Model` focus commands themselves):
  - `SearchField { property alias text; signal settingsRequested(); signal helpRequested() }`
  - `WindowList { property var rows; property int selectedIndex; property var iconSource /* function(window) */; property var snippetFor /* function(window) -> {before,match,after}|null */; signal activated(int index); signal hovered(int index) }`
  - `WindowRow { property var row; property bool selected; ... }` renders one window row; header rows arrive in Task 7.
  - `PreviewPane { property var window; property var highlights; property bool enabled }`: v1's two alternating ScreencopyViews and handoff logic, moved unchanged.
  - `FooterHints { property bool cycleMode; property bool settingsOpen }`

- [ ] **Step 1:** Move each visual block from `Switcher.qml` into its component; keep ids, timers, and the flicker-free handoff code intact in `PreviewPane`.
- [ ] **Step 2:** Run `node --test tests/`. Expected: PASS. `wc -l Switcher.qml`: under 450 lines.
- [ ] **Step 3:** Commit `refactor: split switcher UI into components`.

### Task 7: Grouped rows, snippets, jump keys

**Files:**
- Create: `components/GroupHeader.qml`
- Modify: `Switcher.qml`, `components/WindowList.qml`, `components/WindowRow.qml`, `components/FooterHints.qml`

**Interfaces:**
- Consumes: `Model.displayRows`, `Model.stepWindowRow`, `Model.windowRowIndex`, `Model.clampSelection`, `Model.matchSnippet`, `Model.titleMatch`.

- [ ] **Step 1:** `Switcher.qml` builds `rows = Model.displayRows(filtered, { group: !cycleMode && settings.values.groupByWorkspace })`. `select(delta)` uses `stepWindowRow`. After every refresh, `selectedIndex = Model.clampSelection(rows, selectedIndex)`.
- [ ] **Step 2:** `WindowRow` layout: icon, app name, elided title, jump number at the trailing edge (hidden when `null`), snippet line when `snippetFor(window)` is non-null with the match part in the theme's highlight treatment; otherwise the title shows `titleMatch` highlighted the same way. Selection shows a leading marker bar plus background.
- [ ] **Step 3:** Keys in `Switcher.qml`: in cycle mode `1`-`9` and in picker mode `Alt+1`-`Alt+9` call `windowRowIndex` and focus that row immediately.
- [ ] **Step 4:** `FooterHints` copy, picker mode: `Enter switch · Ctrl+W close · Ctrl+M move here · Alt+1-9 jump · Ctrl+, settings`. Hidden in cycle mode.
- [ ] **Step 4b:** The search field's `?` button (and `?` with an empty query) toggles a shortcuts panel in place of the preview, listing the spec's key table. `Escape` or `?` again hides it. No button ships without a working action.
- [ ] **Step 5:** Empty states: `No windows` with zero windows; `No match for "<query>"` with zero rows and OCR idle; add `Searching window contents…` under it while `OcrIndexer.searching`.
- [ ] **Step 6:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 7:** Commit `feat: group by workspace, match snippets, jump keys`.

### Task 8: Same-app cycling

**Files:**
- Modify: `Switcher.qml` (`open(payloadJson)`)

**Interfaces:**
- Consumes: `Model.appCycleIndex`, `Model.appId`.

- [ ] **Step 1:** In `open()`: when `payload.scope === "app"` and the overlay is open, set `selectedIndex = Model.appCycleIndex(rows, selectedIndex, direction)` and return. When closed, open in cycle mode with windows filtered to `Model.appId(focused window)` and select the second row (or the first when it is the only one).
- [ ] **Step 2:** Confirm the existing `{"mode":"cycle","direction":±1}` path is untouched: `git diff` shows the old branch unchanged except where it now skips when `scope === "app"`.
- [ ] **Step 3:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 4:** Commit `feat: cycle windows of the same app`.

### Task 9: Close and move actions

**Files:**
- Modify: `Switcher.qml`, `components/WindowRow.qml`

**Interfaces:**
- Consumes: `Model.closeTarget`, `Model.moveHereLua`.

- [ ] **Step 1:** `Ctrl+W`: call `close()` on the selected row's `HyprlandToplevel.wayland` (Quickshell Toplevel) when available; otherwise run `hyprctl dispatch closewindow address:<closeTarget>`. Mark the row `closing` (dimmed) until Hyprland's `closewindow` event refreshes the list. Overlay stays open.
- [ ] **Step 2:** `Ctrl+M`: `Hyprland.dispatch(Model.moveHereLua(window, Hyprland.focusedWorkspace.id))` when non-null, then focus the window with v1's focus path and close the overlay.
- [ ] **Step 3:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 4:** Commit `feat: close and move windows from the switcher`.

### Task 10: Settings view, scope, monitor placement

**Files:**
- Create: `components/SettingsView.qml`
- Modify: `Switcher.qml`, `services/OcrIndexer.qml` (bind `enabled`), `components/PreviewPane.qml` (bind `enabled`)

**Interfaces:**
- Consumes: `PluginSettings.values`, `PluginSettings.set`, `Settings.scopes`, `Model.scopedWindows`.
- Produces: `SettingsView { property var values; property var bindingState /* Bindings.state result or null */; signal changed(string key, var value); signal setupRequested(); signal removeRequested(); signal closed() }`.

- [ ] **Step 1:** `SettingsView` controls, all keyboard reachable with visible focus: Scope (All workspaces / Current workspace / Current monitor), Group by workspace, Live preview, Search window contents, plus the bindings section (filled in Task 11). `Escape` returns to the list.
- [ ] **Step 2:** `Switcher.qml`: `Ctrl+,` and the search field's settings button open it. Filtering uses `Model.scopedWindows(windows, settings.values.scope, { workspaceId: Hyprland.focusedWorkspace.id, monitorName: Hyprland.focusedMonitor.name })` before `filteredWindows`. Same-app cycling ignores scope.
- [ ] **Step 3:** Panel opens on the focused monitor: set `PanelWindow.screen` to the entry of `Quickshell.screens` whose `name === Hyprland.focusedMonitor.name`, evaluated in `open()` before `opened = true`.
- [ ] **Step 4:** `livePreview: false` hides `PreviewPane` and the list takes the full width; `contentSearch: false` disables the indexer.
- [ ] **Step 5:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 6:** Commit `feat: settings view, scope, open on focused monitor`.

### Task 11: First-run setup and binding removal

**Files:**
- Create: `services/BindingsSetup.qml`, `components/SetupBanner.qml`
- Modify: `Switcher.qml`, `components/SettingsView.qml`

**Interfaces:**
- Consumes: `Bindings.*`, `PluginSettings.set("setupDismissed", true)`.
- Produces: `BindingsSetup { readonly property var state /* Bindings.state or null when file missing */; readonly property bool busy; readonly property string error; function refresh(); function apply(); function remove() }`.

Copy (exact):
- Banner: `Alt+Tab still opens Omarchy's switcher.` Buttons: `Use OmaSwitch for Alt+Tab`, `Not now`.
- Missing file: `Add the bindings from the README to ~/.config/hypr/bindings.lua.`
- Restored: `Hyprland rejected the new bindings, so OmaSwitch put your file back:` followed by the new error lines and a `Manual setup steps` link that opens the README setup section (`xdg-open https://github.com/piyush97/omaswitch#setup`; confirm the anchor exists after Task 12).
- Settings, hand-written without app scope: `Add this line for same-app cycling:` plus `Bindings.appScopeLine()` and a `Copy` button (`wl-copy` is not guaranteed; use Quickshell's clipboard API).
- Settings buttons: `Set up Alt+Tab`, `Remove OmaSwitch bindings`.

- [ ] **Step 1:** `BindingsSetup.refresh()` reads `~/.config/hypr/bindings.lua` with `FileView` and sets `state`.
- [ ] **Step 2:** `apply()` sequence, each step a `Process`, stop on any failure: `hyprctl configerrors` -> before; `cp bindings.lua bindings.lua.omaswitch-<YYYYMMDD-HHMMSS>.bak`; write `Bindings.appendBlock(text)` via `FileView.setText`; `hyprctl reload`; `hyprctl configerrors` -> after; if `Bindings.newErrors(before, after).length`, copy the backup back, `hyprctl reload`, set `error`.
- [ ] **Step 3:** `remove()`: same sequence using `Bindings.stripBlock`.
- [ ] **Step 4:** `SetupBanner` shows above the list when `Bindings.needsSetup` on the read text and `!settings.values.setupDismissed`; never in cycle mode.
- [ ] **Step 5:** Run `node --test tests/`. Expected: PASS.
- [ ] **Step 6:** Commit `feat: one-click Alt+Tab setup with backup and restore`.

### Task 12: Release 2.0.0

**Files:**
- Modify: `manifest.json`, `CHANGELOG.md`, `README.md`
- Create: `docs/v2-manual-test.md`
- Add later (owner): `screenshots/*` v2 captures, `assets/icon.svg`

- [ ] **Step 1:** `manifest.json`: `"version": "2.0.0"`, description `Alt+Tab for Omarchy that finds any window, even by what is on screen.`, add `"preview": "preview.png"`. Add `"icon"` only once the owner provides `assets/icon.svg`.
- [ ] **Step 2:** `CHANGELOG.md`: `## [2.0.0]` with Added (snippets, grouping, jump keys, same-app cycling, close/move, settings, setup, focused-monitor), Changed (code split, tests), and the new optional `ALT + GRAVE` binding.
- [ ] **Step 3:** `README.md`: lead with search; keys table from the spec; setup section with the button first and the manual block second; uninstall step "press Remove OmaSwitch bindings first or delete the marked block"; note that Hyprland bindings on `Alt+1`-`Alt+9` take priority. Mark old screenshots as v1 until the owner replaces them.
- [ ] **Step 4:** `docs/v2-manual-test.md`: the spec's verification checklist as checkboxes, plus each Review Focus item as a manual step.
- [ ] **Step 5:** Run `node --test tests/` and `node -e "JSON.parse(require('fs').readFileSync('manifest.json','utf8'))"`. Expected: PASS.
- [ ] **Step 6:** Commit `chore(release): v2.0.0 docs`. Do not tag or publish: the owner tests on Omarchy first, then tags `v2.0.0` and updates the marketplace listing.
