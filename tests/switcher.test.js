const test = require('node:test')
const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const source = name => readFileSync(require('node:path').join(__dirname, '..', name), 'utf8')
const qml = source('Switcher.qml')

test('picker groups rows while cycling stays flat and selection skips headers', () => {
  assert.match(qml, /Model\.displayRows\([^]*?group: !cycleMode && pluginSettings\.values\.groupByWorkspace/)
  assert.match(qml, /Model\.clampSelection\(rows,/)
  assert.match(qml, /Model\.stepWindowRow\(rows,/)
})

test('digit shortcuts focus an on-screen window rather than indexing headers', () => {
  assert.match(qml, /Model\.windowRowIndex\(root\.rows,/)
  assert.match(qml, /Qt\.Key_1[^]*?Qt\.Key_9/)
})
