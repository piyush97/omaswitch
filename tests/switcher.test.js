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
