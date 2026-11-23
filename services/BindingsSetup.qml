import QtQuick
import Quickshell
import Quickshell.Io
import "../Bindings.js" as Bindings

QtObject {
  id: root
  readonly property string path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
  readonly property var state: original === null ? null : Bindings.state(original)
  readonly property bool busy: update.running || awaitingExit
  readonly property bool loaded: original !== null || missing
  property string error: ""
  property bool missing: false
  property var original: null
  property bool awaitingExit: false
  property bool streamDone: false
  property bool exitDone: false
  property int exitCode: 0

  function refresh() { if (!busy) bindingsFile.reload() }
  function apply() { if (state && Bindings.needsSetup(original)) change(Bindings.appendBlock(original)) }
  function remove() { if (state?.managed) change(Bindings.stripBlock(original)) }

  function change(next) {
    if (busy || original === null || next === original) return
    var script = decodeURIComponent(Qt.resolvedUrl("update-bindings.sh").toString().replace(/^file:\/\//, ""))
    error = ""
    streamDone = false
    exitDone = false
    awaitingExit = true
    update.command = ["bash", script, path, original, next]
    update.running = true
  }

  function finish() {
    if (!exitDone || !streamDone) return
    error = exitCode === 0 ? "" : (updateErrors.text.trim() || "Could not change OmaSwitch bindings.")
    awaitingExit = false
    Qt.callLater(root.refresh)
  }

  property FileView reader: FileView {
    id: bindingsFile
    path: root.path
    printErrors: false
    // A rollback restores the exact bytes it saw, so its error stays until
    // the file changes on disk or disappears; then it no longer applies.
    onLoaded: {
      var next = text()
      if (root.original !== null && next !== root.original) root.error = ""
      root.original = next
      root.missing = false
    }
    onLoadFailed: { root.error = ""; root.original = null; root.missing = true }
  }

  property Process runner: Process {
    id: update
    stderr: StdioCollector {
      id: updateErrors
      onStreamFinished: { root.streamDone = true; root.finish() }
    }
    onExited: function(code, status) {
      root.exitCode = status === 0 ? code : -1
      root.exitDone = true
      root.finish()
    }
  }
}
