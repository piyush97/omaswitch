const assert = require("node:assert/strict")
const Model = require("./Model.js")

const active = { title: "Browser", activated: true, wayland: { appId: "chromium" }, workspace: { id: 1 }, lastIpcObject: { focusHistoryID: 0 } }
const previous = { title: "Terminal", activated: false, wayland: { appId: "foot" }, workspace: { id: 2 }, lastIpcObject: { focusHistoryID: 1 } }
const old = { title: "Notes", activated: false, lastIpcObject: { class: "obsidian", focusHistoryID: 8 }, workspace: { id: 3 } }

assert.deepEqual(Model.sortedWindows([old, previous, active]), [active, previous, old])
assert.equal(Model.isCurrent(active), true)
assert.equal(Model.isCurrent({ activated: false, lastIpcObject: { focusHistoryID: 0 } }), true)
assert.deepEqual(Model.filteredWindows([active, previous, old], "foot"), [previous])
assert.deepEqual(Model.filteredWindows([active, previous, old], "notes"), [old])
const visualOnly = { address: "0xabc", title: "Terminal", lastIpcObject: { class: "kitty" } }
assert.deepEqual(Model.filteredWindows([visualOnly], "ERR_404_DATABASE"), [])
assert.deepEqual(
  Model.filteredWindows([visualOnly], "ERR_404_DATABASE", { abc: "Build failed: ERR_404_DATABASE" }),
  [visualOnly],
  "OCR text must participate in normal case-insensitive filtering"
)
const longTitle = { title: "x".repeat(180) + "needle", lastIpcObject: { class: "app" } }
assert.deepEqual(Model.filteredWindows([longTitle], "needle"), [longTitle],
  "search must use full metadata rather than display-truncated labels")
assert.equal(Model.detail(old), "obsidian · ws 3")
assert.equal(Model.label({ title: "x".repeat(161) }), "x".repeat(159) + "…")
assert.equal(Model.detail({ wayland: { appId: "x".repeat(161) } }), "x".repeat(159) + "…")

// --- window lifetime: delegate rows contain scalars, never compositor QObjects ---
const liveWindow = {
  address: "0xabc",
  title: "Editor",
  activated: true,
  wayland: { appId: "code" },
  workspace: { id: 4 },
  lastIpcObject: { focusHistoryID: 2 }
}
const snapshot = Model.windowSnapshot(liveWindow)
assert.deepEqual(snapshot, {
  address: "0xabc",
  title: "Editor",
  activated: true,
  workspace: { id: 4 },
  lastIpcObject: { class: "code", focusHistoryID: 2 }
})
assert.equal(snapshot.wayland, undefined, "delegate snapshots must not retain Toplevel QObjects")
assert.notEqual(snapshot.workspace, liveWindow.workspace, "workspace metadata must be copied")
assert.equal(Model.windowForAddress([liveWindow], "abc"), liveWindow)
assert.equal(Model.windowForAddress([liveWindow], "0xdead"), null)

// --- application icon lookup ---
const desktopEntries = [
  { id: "foot.desktop", name: "Foot", icon: "foot" },
  { id: "visual-studio-code.desktop", name: "Visual Studio Code", icon: "visual-studio-code" },
  { id: "org.telegram.desktop", name: "Telegram Desktop", icon: "telegram" }
]
assert.equal(Model.desktopEntryForWindow({ wayland: { appId: "foot" } }, desktopEntries), desktopEntries[0])
assert.equal(Model.desktopEntryForWindow({ wayland: { appId: "code" } }, desktopEntries), desktopEntries[1])
assert.equal(Model.desktopEntryForWindow({ lastIpcObject: { class: "telegram" } }, desktopEntries), desktopEntries[2])
assert.equal(Model.desktopEntryForWindow({ wayland: { appId: "unknown-app" } }, desktopEntries), null)

// --- focusCommand: switching to windows on other workspaces ---
// Reproduces the bug: confirming a selection previously used the native
// activate path, which focuses the window but does NOT move to its workspace,
// and the plain `focuswindow` fallback dropped the 0x address prefix, so the
// lookup silently missed. Verifies the fix always dispatches an explicit,
// workspace-switching command.
const target = { title: "Browser", address: "55ea685ceda0", workspace: { id: 5 } }
const targetHex = { title: "Browser", address: "0x55ea685ceda0", workspace: { id: 5 } }
const expected = "hyprctl dispatch \"hl.dsp.focus({ window = 'address:0x55ea685ceda0' })\" >/dev/null 2>&1 || hyprctl dispatch focuswindow \"address:0x55ea685ceda0\""

assert.ok(Model.focusCommand(target), "window with address must produce a dispatch command")
assert.equal(Model.focusCommand(target), expected, "address must be normalized with 0x prefix")
assert.equal(Model.focusCommand(targetHex), expected, "existing 0x prefix must be preserved")
assert.ok(Model.focusCommand(target).startsWith("hyprctl dispatch \"hl.dsp.focus("),
  "primary dispatch must be the workspace-switching hl.dsp.focus form")
assert.ok(Model.focusCommand(target).includes("|| hyprctl dispatch focuswindow \"address:0x55ea685ceda0\""),
  "plain focuswindow must remain as the stock-Hyprland fallback")
assert.equal(Model.focusCommand({}), null, "no address cannot produce a focus command")
assert.equal(Model.focusCommand(null), null, "no window cannot produce a focus command")
assert.equal(Model.focusCommand({ address: "abc'; touch /tmp/pwned; '" }), null,
  "non-hex compositor addresses must never reach a shell command")
// Exercise the shipped QML capture handlers without a compositor or timing luck.
const fs = require("node:fs")
const vm = require("node:vm")
const qml = fs.readFileSync(__dirname + "/Switcher.qml", "utf8")
assert.match(qml, /\.map\(Model\.windowSnapshot\)/, "ListView rows must use scalar snapshots")
assert.match(qml, /onObjectRemovedPre\(window\)[\s\S]*?previewSourceA === source[\s\S]*?previewSourceB === source[\s\S]*?resetPreview\(\)/,
  "capture sources must clear before any retained toplevel is destroyed")
assert.match(qml, /function close\(\)[\s\S]*?root\.rows = \[\][\s\S]*?root\.allWindows = \[\]/,
  "closing the overlay must release all row snapshots")
assert.match(qml, /filterText\.trim\(\)\.length >= 3[\s\S]*?beginOcrIndex\(\)/,
  "OCR must remain lazy until a meaningful search query exists")
assert.ok(
  qml.includes('"timeout", "5s", "tesseract", path, "stdout"') &&
  qml.includes('Quickshell.execDetached(["rm", "-f", path])'),
  "OCR must invoke local tesseract without a shell and delete its temporary capture"
)
assert.match(qml, /\^\[A-Za-z0-9_\+\-\]\+\$[\s\S]*?languages = "eng"/,
  "OCR language configuration must be validated before reaching a process")
assert.match(qml, /runtimeDir[\s\S]*?\(\^\|\\\/\)\\\.\\\.\(\\\/\|\$\)/,
  "OCR must reject unsafe runtime directory traversal")
assert.match(qml, /function resetOcr\(\)[\s\S]*?ocrTextByAddress = \(\{\}\)/,
  "OCR text must remain session-only and clear when the overlay closes")
assert.match(qml, /omaswitch-ocr-" \+[\s\S]*?Date\.now\(\)[\s\S]*?Math\.random\(\)/,
  "each OCR capture must use a unique runtime-directory path")
assert.match(qml, /property int generation: -1[\s\S]*?property bool streamDone: false[\s\S]*?property bool exitedDone: false[\s\S]*?property bool active: false/,
  "OCR process reuse must wait for an immutable generation and both exit signals")
assert.match(qml, /function onObjectRemovedPre\(window\) \{[\s\S]*?root\.resetOcr\(\)/,
  "window topology changes must clear cached OCR text before an address can be reused")
const timeoutHandler = qml.match(/id: previewCaptureTimeout[\s\S]*?onTriggered: \{([\s\S]*?)^    \}/m)
assert.ok(timeoutHandler, "pending preview captures must have bounded cancellation")
const targetHandler = qml.match(/^  onPreviewTargetChanged: \{([\s\S]*?)^  \}/m)
assert.ok(targetHandler)
const root = {
  opened: true, previewTarget: null, previewSourceA: null, previewSourceB: null,
  activePreview: -1, pendingPreview: -1, previewAvailable: false
}
const later = []
let timeoutRunning = false
const previewViewA = { hasContent: false }
const previewViewB = { hasContent: false }
const context = vm.createContext({
  root, previewViewA, previewViewB,
  Qt: { callLater: function(callback) { later.push(callback) } },
  previewCaptureTimeout: {
    restart: function() { timeoutRunning = true },
    stop: function() { timeoutRunning = false }
  }
})
Object.defineProperty(context, "previewTarget", { get: function() { return root.previewTarget } })
for (const name of ["queuePreview", "previewReady", "cancelPendingPreview", "resetPreview"]) {
  const handler = qml.match(new RegExp("^  function " + name + "\\([^)]*\\) \\{[\\s\\S]*?^  \\}", "m"))
  assert.ok(handler, name)
  root[name] = vm.runInContext("(" + handler[0] + ")", context)
}

root.previewTarget = "no-frame"
root.queuePreview(root.previewTarget)
assert.equal(timeoutRunning, true)
root.previewTarget = "healthy"
root.queuePreview(root.previewTarget)
assert.equal(root.previewSourceA, "no-frame", "do not retarget an in-flight capture")
vm.runInContext(timeoutHandler[1], context)
assert.equal(root.previewSourceA, null)
assert.equal(timeoutRunning, false)
assert.equal(later.length, 1)
later.shift()()
assert.equal(root.previewSourceA, "healthy", "a failed capture must not block the newest target")
assert.equal(timeoutRunning, true)
root.previewReady(0)
assert.equal(root.activePreview, 0)
assert.equal(root.pendingPreview, -1)
assert.equal(timeoutRunning, false)

root.previewTarget = "failed-standby"
root.queuePreview(root.previewTarget)
vm.runInContext(timeoutHandler[1], context)
assert.equal(root.activePreview, 0, "a failed standby capture must retain the current frame")
assert.equal(root.previewSourceA, "healthy")
assert.equal(root.previewSourceB, null)

root.resetPreview()
root.previewTarget = "no-frame"
root.queuePreview(root.previewTarget)
vm.runInContext(timeoutHandler[1], context)
assert.equal(root.pendingPreview, -1)
assert.equal(later.length, 0, "do not repeatedly retry an unavailable source")

root.previewTarget = "old"
root.queuePreview(root.previewTarget)
root.previewTarget = "new"
root.previewReady(0)
assert.equal(root.activePreview, -1, "a stale frame must not replace the selected preview")
assert.equal(timeoutRunning, false)
assert.equal(later.length, 1)
root.opened = false
root.previewTarget = null
vm.runInContext("(function() {" + targetHandler[1] + "})()", context)
later.shift()()
assert.equal(root.previewSourceA, null, "a queued capture must not restart after closing")
assert.equal(root.previewSourceB, null)
assert.equal(timeoutRunning, false)

root.opened = true
root.activePreview = 0
root.previewSourceA = "old"
root.previewSourceB = "cached"
previewViewB.hasContent = true
root.queuePreview("cached")
assert.equal(root.activePreview, 1, "a ready standby buffer needs no new frame event")
assert.equal(timeoutRunning, false)

root.resetPreview()
let captureSourceA = null
Object.defineProperty(root, "previewSourceA", {
  get: function() { return captureSourceA },
  set: function(value) {
    captureSourceA = value
    previewViewA.hasContent = value !== null
    if (previewViewA.hasContent) root.previewReady(0)
  }
})
root.previewTarget = "instant"
root.queuePreview(root.previewTarget)
assert.equal(root.activePreview, 0)
assert.equal(timeoutRunning, false, "subscribe before assigning a source that becomes ready synchronously")

console.log("Model and preview lifecycle checks passed")

// --- MRU ordering: unranked windows (no meaningful focusHistoryID) ---
// Hyprland reports focusHistoryID: null / "" for windows not meaningfully in
// the focus history (transient/popup clients). Number(null) === 0 and
// Number("") === 0, so the old historyRank() wrongly ranked them as the
// current window (rank 0), surfacing stale windows above genuinely recent
// ones and mislabeling them as current. They must sort AFTER all ranked
// windows, in source order, and never be treated as current.
const editorCur = { title: "Editor", activated: true, lastIpcObject: { focusHistoryID: 0 }, wayland: { appId: "ed" } }
const termPrev = { title: "Term", activated: false, lastIpcObject: { focusHistoryID: 1 }, wayland: { appId: "foot" } }
const staleNull = { title: "StalePopup", activated: false, lastIpcObject: { focusHistoryID: null }, wayland: { appId: "popup" } }
const staleEmpty = { title: "Mystery", activated: false, lastIpcObject: { focusHistoryID: "" }, wayland: { appId: "unknown" } }
const staleBlank = { title: "Blank", activated: false, lastIpcObject: { focusHistoryID: " " }, wayland: { appId: "blank" } }

assert.deepEqual(
  Model.sortedWindows([termPrev, editorCur, staleNull, staleEmpty, staleBlank]).map(function(w) { return w.title }),
  ["Editor", "Term", "StalePopup", "Mystery", "Blank"],
  "unranked windows must sort AFTER ranked ones, in source order"
)

assert.equal(Model.isCurrent(staleNull), false, "null focusHistoryID must not be current")
assert.equal(Model.isCurrent(staleEmpty), false, "empty focusHistoryID must not be current")
assert.equal(Model.isCurrent({ activated: false, lastIpcObject: {} }), false, "missing focusHistoryID must not be current")
assert.equal(Model.isCurrent(editorCur), true, "activated window must be current")
assert.equal(Model.isCurrent({ activated: false, lastIpcObject: { focusHistoryID: 0 } }), true, "real rank 0 must be current")

// --- normalizeAddress: toplevel vs event-payload address forms ---
// Toplevels expose "0x55ea685ceda0" while the activewindowv2 event payload is
// the bare "55ea685ceda0". Comparing the two forms directly never matches, so
// the MRU would never recognise the window that was just focused.
assert.equal(Model.normalizeAddress("55ea685ceda0"), "0x55ea685ceda0", "bare address gains 0x")
assert.equal(Model.normalizeAddress("0x55ea685ceda0"), "0x55ea685ceda0", "0x form is preserved")
assert.equal(Model.normalizeAddress(" 55ea685ceda0 "), "0x55ea685ceda0", "surrounding space is trimmed")
assert.equal(Model.normalizeAddress(""), "", "empty stays empty")
assert.equal(Model.normalizeAddress("   "), "", "whitespace-only stays empty")
assert.equal(Model.normalizeAddress(null), "", "null stays empty")
assert.equal(Model.normalizeAddress(undefined), "", "undefined stays empty")
assert.equal(Model.normalizeAddress("../escape"), "", "non-hex addresses are rejected")

// --- sortedWindows(rankFn): caller-supplied ordering ---
// lastIpcObject is a cached snapshot that is not refreshed when focus moves, so
// focusHistoryID can name a stale window as rank 0 and the cycle pre-selection
// then lands on the window already focused. Switcher.qml supplies an MRU rank
// built from activewindowv2 events instead; the default must stay focusRank.
const byTitle = { Editor: 2, Term: 0, Notes: 1 }
assert.deepEqual(
  Model.sortedWindows([editorCur, termPrev, old], function(w) { return byTitle[w.title] }).map(function(w) { return w.title }),
  ["Term", "Notes", "Editor"],
  "rankFn must override focusRank"
)
assert.deepEqual(
  Model.sortedWindows([termPrev, editorCur, old]).map(function(w) { return w.title }),
  ["Editor", "Term", "Notes"],
  "omitting rankFn must keep the focusRank default"
)
assert.deepEqual(
  Model.sortedWindows([termPrev, editorCur, old], null).map(function(w) { return w.title }),
  ["Editor", "Term", "Notes"],
  "a non-function rankFn must fall back to focusRank"
)
assert.deepEqual(
  Model.sortedWindows([editorCur, termPrev], function() { return 0 }).map(function(w) { return w.title }),
  ["Editor", "Term"],
  "equal ranks must preserve source order"
)

// historyRank is exported so Switcher.qml can seed unseen windows with it.
assert.equal(Model.historyRank(editorCur), 0, "ranked window keeps its history rank")
assert.equal(Model.historyRank(staleNull), 1000000, "unranked window sorts last")

// --- MRU ordering across workspaces ---
// Quickshell's cached lastIpcObject ranks can become stale because focusing one
// client changes every client's rank, while not every cached object refreshes.
// The live activewindowv2 address order must take precedence across desktops.
const wsCurrent = { address: "aaa", title: "Current", activated: true, lastIpcObject: { focusHistoryID: 0 }, workspace: { id: 5 } }
const wsPrevious = { address: "0xbbb", title: "Previous", activated: false, lastIpcObject: { focusHistoryID: 9 }, workspace: { id: 2 } }
const wsStaleSecond = { address: "ccc", title: "Stale second", activated: false, lastIpcObject: { focusHistoryID: 1 }, workspace: { id: 5 } }

assert.deepEqual(
  Model.sortedWindows([wsStaleSecond, wsPrevious, wsCurrent], ["0xaaa", "bbb", "0xccc"]).map(function(w) { return w.title }),
  ["Current", "Previous", "Stale second"],
  "live global MRU addresses must override stale cached ranks across workspaces"
)
assert.deepEqual(Model.promoteAddress(["aaa", "bbb", "ccc"], "0xbbb"), ["bbb", "aaa", "ccc"])
assert.deepEqual(
  Model.addressesByHistory([
    { address: "0xccc", focusHistoryID: 8 },
    { address: "0xaaa", focusHistoryID: 0 },
    { address: "aaa", focusHistoryID: 0 },
    { address: "0xbbb", focusHistoryID: 1 }
  ]),
  ["aaa", "bbb", "ccc"]
)

var replayed = ["ddd", "eee"]
var seededMru = ["aaa", "bbb", "ccc"]
for (var replayIndex = replayed.length - 1; replayIndex >= 0; replayIndex--)
  seededMru = Model.promoteAddress(seededMru, replayed[replayIndex])
assert.deepEqual(seededMru, ["ddd", "eee", "aaa", "bbb", "ccc"])
console.log("Model checks passed")
