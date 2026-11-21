const assert = require("node:assert/strict")
const Settings = require("../Settings.js")

assert.deepEqual(Settings.read(null), Settings.defaults)
assert.deepEqual(Settings.read({ scope: "monitor", livePreview: false }).scope, "monitor")
assert.equal(Settings.read({ scope: "galaxy" }).scope, "all")
assert.equal(Settings.read({ groupByWorkspace: "yes" }).groupByWorkspace, true)
assert.deepEqual(Settings.patch({ id: "piyush.omaswitch", extra: 1 }, "contentSearch", false), { extra: 1, contentSearch: false })
assert.equal(Settings.patch({}, "scope", "galaxy"), null)
assert.equal(Settings.patch({}, "nope", true), null)

console.log("Settings checks passed")
