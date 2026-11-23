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

  const embeddedMarkers = 'print("' + Bindings.BEGIN + '")\nuser code\nprint("' + Bindings.END + '")\n'
  assert.equal(Bindings.state(embeddedMarkers).managed, false)
  assert.equal(Bindings.stripBlock(embeddedMarkers), embeddedMarkers)

  // Fix round 1: END-before-BEGIN is not managed
  const wrongOrder = "some content\n" + Bindings.END + "\n" + Bindings.BEGIN + "\nmore\n"
  assert.equal(Bindings.state(wrongOrder).managed, false, "END before BEGIN should not be managed")
  assert.equal(Bindings.stripBlock(wrongOrder), wrongOrder, "stripBlock should return unchanged when END before BEGIN")

  // Fix round 1: only-BEGIN is not managed
  const onlyBegin = "some content\n" + Bindings.BEGIN + "\nmore\n"
  assert.equal(Bindings.state(onlyBegin).managed, false, "only BEGIN should not be managed")
  assert.equal(Bindings.stripBlock(onlyBegin), onlyBegin, "stripBlock should return unchanged when only BEGIN")

  // Fix round 1: non-blank user line above block survives stripBlock
  const userLine = "user code here\n"
  const withUserLine = userLine + "\n" + Bindings.block() + "\n"
  assert.equal(Bindings.state(withUserLine).managed, true, "block with user line should be managed")
  const stripped = Bindings.stripBlock(withUserLine)
  assert.ok(stripped.includes("user code here"), "stripBlock should preserve non-blank user line")
  assert.equal(stripped, userLine, "stripBlock should only remove block and blank line")
})
