const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const { tmpdir } = require('node:os')
const { join } = require('node:path')
const { spawnSync } = require('node:child_process')
const Bindings = require('../Bindings.js')

for (const mode of ['unchanged errors', 'new errors', 'reload failure', 'external edit']) {
  test(`bindings transaction: ${mode}`, t => {
    const dir = fs.mkdtempSync(join(tmpdir(), 'oma-bindings-'))
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
    const path = join(dir, 'bindings.lua')
    const original = '-- custom bindings\r\n'
    const updated = Bindings.appendBlock(original)
    fs.writeFileSync(path, mode === 'external edit' ? '-- rewritten\n' : original, { mode: 0o640 })
    fs.writeFileSync(join(dir, 'hyprctl'), `#!/usr/bin/env bash
if [[ $1 == configerrors ]]; then
  echo 'pre-existing warning'
  if grep -q piyush.omaswitch "$TEST_BINDINGS" && [[ $TEST_MODE == 'new errors' ]]; then echo 'new error'; fi
elif [[ $1 == reload && $TEST_MODE == 'reload failure' ]] && grep -q piyush.omaswitch "$TEST_BINDINGS"; then
  exit 1
fi
`, { mode: 0o755 })
    const run = (from, to) => spawnSync('bash', [join(__dirname, '../services/update-bindings.sh'), path, from, to], {
      encoding: 'utf8', env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, TEST_MODE: mode, TEST_BINDINGS: path }
    })
    const result = run(original, updated)
    assert.equal(result.status, mode === 'unchanged errors' ? 0 : 1, result.stderr)
    assert.equal(fs.readFileSync(path, 'utf8'), mode === 'external edit' ? '-- rewritten\n' : mode === 'unchanged errors' ? updated : original)
    assert.equal(fs.statSync(path).mode & 0o777, 0o640)
    const backups = fs.readdirSync(dir).filter(name => name.endsWith('.bak'))
    assert.equal(backups.length, mode === 'external edit' ? 0 : 1)
    if (backups.length) assert.equal(fs.readFileSync(join(dir, backups[0]), 'utf8'), original)
    if (mode === 'new errors') assert.match(result.stderr, /put your file back:\nnew error/)
    if (mode === 'unchanged errors') {
      const removed = run(updated, Bindings.stripBlock(updated))
      assert.equal(removed.status, 0, removed.stderr)
      assert.equal(fs.readFileSync(path, 'utf8'), original)
    }
  })
}
