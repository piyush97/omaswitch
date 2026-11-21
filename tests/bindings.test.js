const assert = require("node:assert/strict")
const test = require("node:test")
const Bindings = require("../Bindings.js")

test("Bindings text logic", () => {
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
})
