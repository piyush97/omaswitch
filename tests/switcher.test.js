const test = require('node:test')
const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const source = name => readFileSync(require('node:path').join(__dirname, '..', name), 'utf8')
const qml = source('Switcher.qml')

test('close and move target a selected window without shell interpolation', () => {
  assert.match(qml, /Model\.closeTarget\(selectedWindow\)/)
  assert.match(qml, /\["hyprctl", "dispatch", "closewindow", "address:" \+ address\]/)
  assert.match(qml, /Model\.moveHereLua\(selectedWindow, workspace\.id\)/)
})

test('picker scopes snapshots and opens on the focused monitor', () => {
  assert.match(qml, /Model\.scopedWindows\(allWindows, pluginSettings\.values\.scope,/)
  assert.match(qml, /Quickshell\.screens\.find/)
  assert.match(qml, /screen: root\.targetScreen/)
  assert.match(qml, /enabled: root\.opened && pluginSettings\.values\.contentSearch/)
  assert.match(qml, /pluginSettings\.values\.livePreview && root\.previewTarget/)
})

test('picker groups rows while cycling stays flat and selection skips headers', () => {
  assert.match(qml, /Model\.displayRows\([^]*?group: !cycleMode && pluginSettings\.values\.groupByWorkspace/)
  assert.match(qml, /Model\.clampSelection\(rows,/)
  assert.match(qml, /Model\.stepWindowRow\(rows,/)
})

test('same-app cycling uses the current app and skips other apps', () => {
  assert.match(qml, /payload\.scope === "app"/)
  assert.match(qml, /Model\.appCycleIndex\(rows, selectedIndex, delta\)/)
  assert.match(qml, /Model\.appId\(window\) === cycleApp/)
})

test('digit shortcuts focus an on-screen window rather than indexing headers', () => {
  assert.match(qml, /Model\.windowRowIndex\(root\.rows,/)
  assert.match(qml, /Qt\.Key_1[^]*?Qt\.Key_9/)
})

test('omit patterns are watched and applied when refreshing', () => {
  assert.match(qml, /!Model\.excluded\(window, root\.omitPatterns\)/)
  assert.match(qml, /omaswitch-omit\.json/)
  assert.match(qml, /watchChanges: true[\s\S]*?onFileChanged: reload\(\)/)
})

test('an omitted focused window makes Alt+Tab start at the first row', () => {
  const vm = require('node:vm')
  const Model = require('../Model.js')
  const refresh = qml.match(/^  function refresh\(\) \{[\s\S]*?^  \}/m)
  assert.ok(refresh)
  const focusedTray = { address: '0xa', title: 'pCloud', activated: true, wayland: { appId: 'pcloud.bin' }, workspace: { id: 1 } }
  const previous = { address: '0xb', title: 'Editor', activated: false, wayland: { appId: 'code' }, workspace: { id: 1 }, lastIpcObject: { focusHistoryID: 1 } }
  const root = { mruAddresses: ['a', 'b'], omitPatterns: [/^pcloud/i] }
  const context = vm.createContext({ root, Model, Hyprland: { toplevels: { values: [focusedTray, previous] } }, rebuildRows() {} })
  vm.runInContext(refresh[0] + '\nrefresh()', context)
  assert.equal(root.focusedOmitted, true)
  assert.deepEqual(vm.runInContext('allWindows', context).map(w => w.title), ['Editor'])
  root.omitPatterns = []
  vm.runInContext('refresh()', context)
  assert.equal(root.focusedOmitted, false, 'nothing omitted keeps the old cycle start')
  assert.match(qml, /var firstTarget = root\.focusedOmitted \? 0 : 1/)
  assert.match(qml, /root\.selectedIndex = direction < 0 \? root\.rows\.length - 1 : firstTarget/)
})

test('a preview click focuses the window whose frame is on screen (#16)', () => {
  const vm = require('node:vm')
  const Model = require('../Model.js')
  const sourceA = { id: 'surface-a' }, sourceB = { id: 'surface-b' }
  const a = { address: '0xa', title: 'A', wayland: sourceA, workspace: { id: 1 }, lastIpcObject: {} }
  const b = { address: '0xb', title: 'B', wayland: sourceB, workspace: { id: 1 }, lastIpcObject: {} }
  assert.equal(Model.windowForSource([a, b], sourceB), b)
  assert.equal(Model.windowForSource([a], sourceB), null)
  assert.equal(Model.windowForSource([a], null), null, 'no displayed frame matches nothing')
  assert.equal(Model.windowForSource(null, sourceA), null)

  const handler = qml.match(/^  function focusPreviewSource\(source\) \{[\s\S]*?^  \}/m)
  assert.ok(handler)
  const committed = []
  const root = {
    pendingFocus: null,
    dismiss() {},
    focusSelected() { committed.push('selection') }
  }
  const context = vm.createContext({
    root, Model,
    Hyprland: { toplevels: { values: [a, b] } },
    pendingFocusBackstop: { restart() { committed.push(root.pendingFocus.title) } }
  })
  vm.runInContext(handler[0], context)
  for (const [source, expected] of [[sourceA, 'A'], [sourceB, 'B'], [null, 'selection']]) {
    committed.length = 0
    context.focusPreviewSource(source)
    assert.deepEqual(committed, [expected])
  }
  // The frame can belong to a window the filter removed from rows; it still wins.
  committed.length = 0
  context.focusPreviewSource(sourceA)
  assert.deepEqual(committed, ['A'])
  assert.equal(typeof root.pendingFocus.wayland, 'undefined', 'pendingFocus must be a scalar snapshot')

  const pane = source('components/PreviewPane.qml')
  assert.match(pane, /signal previewClicked\(var source\)/)
  assert.match(pane, /root\.previewClicked\(root\.activePreview === 1 \? root\.previewSourceB/)
  assert.match(qml, /onPreviewClicked: function\(source\) \{ root\.focusPreviewSource\(source\) \}/)
})
