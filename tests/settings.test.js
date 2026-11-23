const assert = require("node:assert/strict")
const Settings = require("../Settings.js")

assert.deepEqual(Settings.read(null), Settings.defaults)
assert.deepEqual(Settings.read({ scope: "monitor", livePreview: false }).scope, "monitor")
assert.equal(Settings.read({ scope: "galaxy" }).scope, "all")
assert.equal(Settings.read({ groupByWorkspace: "yes" }).groupByWorkspace, true)
assert.deepEqual(Settings.patch({ id: "piyush.omaswitch", extra: 1 }, "contentSearch", false), { extra: 1, contentSearch: false })
assert.equal(Settings.patch({}, "scope", "galaxy"), null)
assert.equal(Settings.patch({}, "nope", true), null)

// Run the shipped store's JS against a fake shell. QML bindings are represented by getters.
const qml = require("node:fs").readFileSync(__dirname + "/../services/PluginSettings.qml", "utf8")
const vm = require("node:vm")
const callbacks = []
const writes = []
const root = {
  diskReady: false, diskEntry: { id: "piyush.omaswitch", extra: 1 }, pending: {}, inFlight: null,
  pluginId: "piyush.omaswitch", shell: { updateEntryInline: (id, values) => writes.push([id, { ...values }]) },
  confirmationTimeout: { restart() {} }, reloadRequested() {},
  get entry() { return { ...(this.inFlight || this.diskEntry), ...this.pending } }
}
const ctx = vm.createContext({ root, Settings, Qt: { callLater: fn => callbacks.push(fn) } })
for (const name of ["set", "flush", "contains"])
  root[name] = vm.runInContext(`(${qml.match(new RegExp(`^  function ${name}\\([^]*?^  }`, "m"))[0]})`, ctx)
assert.equal(root.set("scope", "galaxy"), false)
assert.equal(root.set("unknown", true), false)
assert.equal(callbacks.length, 0)
assert.equal(root.set("livePreview", false), true)
callbacks.shift()()
assert.equal(writes.length, 0, "never write while disk state is unreadable")
root.diskReady = true
root.flush()
assert.deepEqual(writes, [["piyush.omaswitch", { extra: 1, livePreview: false }]])
assert.equal(root.set("contentSearch", false), true)
callbacks.shift()()
assert.equal(writes.length, 1, "wait for confirmation before flushing a second edit")
assert.equal(root.entry.contentSearch, false)

console.log("Settings checks passed")
