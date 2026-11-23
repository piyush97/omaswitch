import QtQuick
import Quickshell
import Quickshell.Io
import "../Settings.js" as Settings

// Settings store that reads ~/.config/omarchy/shell.json and writes through
// shell.updateEntryInline. Keeps pending edits visible locally until the file
// reload confirms them.
QtObject {
  id: root

  required property string pluginId
  property var shell: null
  readonly property var values: Settings.read(root.entry)
  readonly property bool ready: diskReady
  property bool diskReady: false
  property var diskEntry: null
  property var pending: ({})
  property var inFlight: null
  property bool recovering: false
  readonly property var entry: {
    var next = Object.assign({}, root.inFlight || root.diskEntry || {})
    return Object.assign(next, root.pending)
  }

  signal reloadRequested()

  property Timer confirmationTimeout: Timer {
    interval: 2000
    onTriggered: root.reconcile()
  }

  function contains(entry, expected) {
    if (!entry)
      return false
    for (var key in expected)
      if (JSON.stringify(entry[key]) !== JSON.stringify(expected[key]))
        return false
    return true
  }

  function load(raw) {
    var config
    try {
      config = JSON.parse(raw)
      if (!config || Array.isArray(config) || config.version !== 1)
        throw new Error("expected shell.json version 1")
    } catch (error) {
      root.loadFailed()
      console.warn(root.pluginId + ": could not read settings: " + error)
      return
    }

    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    var next = null
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === root.pluginId) {
        next = plugins[i]
        break
      }
    }
    root.diskEntry = next
    root.diskReady = true
    if (root.inFlight && root.contains(next, root.inFlight)) {
      root.inFlight = null
      root.confirmationTimeout.stop()
    } else if (root.recovering) {
      root.discardEdits()
      console.warn(root.pluginId + ": settings write was not confirmed; restored disk settings")
    }
    root.recovering = false
    // FileView still owns its read job during onLoaded. Let it finish
    // before a write or another reload can run.
    Qt.callLater(root.flush)
  }

  function loadFailed() {
    root.diskReady = false
    if (root.recovering)
      root.discardEdits()
  }

  function discardEdits() {
    root.confirmationTimeout.stop()
    root.inFlight = null
    root.pending = ({})
    root.recovering = false
  }

  function reconcile() {
    root.recovering = true
    root.reloadRequested()
  }

  function set(name, value) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function")
      return false
    var next = Settings.patch(root.pending, name, value)
    if (next === null)
      return false
    root.pending = next
    Qt.callLater(root.flush)
    return true
  }

  function flush() {
    if (!root.diskReady || root.inFlight || Object.keys(root.pending).length === 0
        || !root.shell || typeof root.shell.updateEntryInline !== "function")
      return
    if (!root.diskEntry) {
      root.discardEdits()
      console.warn(root.pluginId + ": cannot save settings without a configured plugin entry")
      return
    }
    var next = root.diskEntry
    for (var name in root.pending) {
      next = Settings.patch(next, name, root.pending[name])
      if (next === null) {
        root.discardEdits()
        return
      }
    }
    if (root.contains(root.diskEntry, next)) {
      root.pending = ({})
      return
    }
    root.inFlight = next
    root.pending = ({})
    try {
      // false also means unchanged, and true only acknowledges the
      // host's in-memory update. Disk observation confirms either case.
      root.shell.updateEntryInline(root.pluginId, next)
      root.confirmationTimeout.restart()
      root.reloadRequested()
    } catch (error) {
      root.discardEdits()
      console.warn(root.pluginId + ": could not save settings: " + error)
      root.reloadRequested()
    }
  }

  property FileView fileView: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: function(error) {
      root.loadFailed()
      console.warn(root.pluginId + ": could not load shell.json: " + error)
    }
    onFileChanged: Qt.callLater(function() { reload() })
  }

  Component.onCompleted: {
    if (fileView.path) {
      root.reloadRequested.connect(function() {
        Qt.callLater(function() { fileView.reload() })
      })
    }
  }
}
