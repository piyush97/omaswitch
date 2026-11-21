import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../Model.js" as Model

// OCR-based content search for window toplevels.
// Starts indexing when enabled && query.trim().length >= 3.
QtObject {
  id: root

  property var windows: []
  property string query: ""
  property bool enabled: false
  readonly property var textByAddress: ocrTextByAddress
  readonly property bool searching: ocrAddress !== "" || ocrQueue.length > 0 || ocrProcess.active

  property var ocrTextByAddress: ({})
  property var ocrQueue: []
  property string ocrAddress: ""
  property int ocrGeneration: 0
  property bool ocrGrabPending: false
  property int ocrCaptureSerial: 0
  property string ocrImagePath: ""
  property HyprlandToplevel ocrWindow: null
  readonly property Toplevel ocrCaptureSource: root.ocrWindow && root.ocrWindow.wayland
    ? root.ocrWindow.wayland : null

  onEnabledChanged: {
    if (enabled && query.trim().length >= 3)
      root.beginOcrIndex()
    else if (!enabled)
      root.cancelOcrIndex()
  }

  onQueryChanged: {
    if (enabled && query.trim().length >= 3)
      root.beginOcrIndex()
    else
      root.cancelOcrIndex()
  }

  function cancelOcrIndex() {
    root.ocrGeneration++
    root.ocrQueue = []
    root.ocrAddress = ""
    root.ocrWindow = null
    root.ocrGrabPending = false
    ocrCaptureTimeout.stop()
    if (ocrProcess.running) ocrProcess.signal(15)
    if (root.ocrImagePath) Quickshell.execDetached(["rm", "-f", root.ocrImagePath])
    root.ocrImagePath = ""
  }

  function reset() {
    root.cancelOcrIndex()
    root.ocrTextByAddress = ({})
  }

  function beginOcrIndex() {
    if (!enabled || root.query.trim().length < 3 || root.searching) return
    var queue = []
    for (var i = 0; i < root.windows.length; i++) {
      var key = Model.addressKey(root.windows[i])
      if (key && root.ocrTextByAddress[key] === undefined) queue.push(key)
    }
    root.ocrQueue = queue
    root.startNextOcr()
  }

  function startNextOcr() {
    root.ocrAddress = ""
    root.ocrWindow = null
    root.ocrGrabPending = false
    root.ocrImagePath = ""
    if (!enabled || root.query.trim().length < 3) {
      root.ocrQueue = []
      return
    }
    if (ocrProcess.active) return
    while (root.ocrQueue.length > 0) {
      var next = root.ocrQueue.slice()
      var address = next.shift()
      root.ocrQueue = next
      var window = Model.windowForAddress(Hyprland.toplevels.values, address)
      if (!window || !window.wayland) continue
      root.ocrAddress = address
      root.ocrWindow = window
      ocrCaptureTimeout.restart()
      return
    }
  }

  function grabOcrFrame() {
    if (!root.ocrAddress || !root.ocrCaptureSource || root.ocrGrabPending || !ocrCaptureView.hasContent) return
    root.ocrGrabPending = true
    var address = root.ocrAddress
    var generation = root.ocrGeneration
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR")
    if (!/^\/[A-Za-z0-9._\/-]+$/.test(runtimeDir) || /(^|\/)\.\.(\/|$)/.test(runtimeDir)) {
      root.finishOcr(address, "")
      return
    }
    root.ocrCaptureSerial++
    var path = runtimeDir + "/omaswitch-ocr-" +
      String(Date.now()) + "-" + String(root.ocrCaptureSerial) + "-" +
      Math.random().toString(36).slice(2) + ".png"
    root.ocrImagePath = path
    // Enlarge small glyphs without downsampling 4K captures; bound the long edge.
    // grabToImage multiplies its target by the host window's device pixel ratio.
    var size = ocrCaptureView.sourceSize
    var scale = Math.min(2, 7680 / Math.max(1, size.width, size.height)) /
      ocrCaptureView.Screen.devicePixelRatio
    var target = Qt.size(Math.max(1, Math.floor(size.width * scale)),
                         Math.max(1, Math.floor(size.height * scale)))
    var started = ocrCaptureView.grabToImage(function(result) {
      if (generation !== root.ocrGeneration || address !== root.ocrAddress) {
        Quickshell.execDetached(["rm", "-f", path])
        return
      }
      ocrCaptureTimeout.stop()
      root.ocrWindow = null
      root.ocrGrabPending = false
      if (!result || !result.saveToFile(path)) {
        Quickshell.execDetached(["rm", "-f", path])
        root.finishOcr(address, "")
        return
      }
      ocrProcess.address = address
      ocrProcess.generation = generation
      ocrProcess.path = path
      ocrProcess.output = ""
      ocrProcess.streamDone = false
      ocrProcess.exitedDone = false
      ocrProcess.active = true
      var languages = Quickshell.env("OMARCHY_OCR_LANGS") || "eng"
      if (!/^[A-Za-z0-9_+-]+$/.test(languages)) languages = "eng"
      ocrProcess.exec(["timeout", "8s", "tesseract", path, "stdout",
        "--oem", "1", "--psm", "11", "-l", languages, "--dpi", "150", "tsv"])
    }, target)
    if (!started) {
      Quickshell.execDetached(["rm", "-f", path])
      root.finishOcr(address, "")
    }
  }

  function finishOcr(address, text) {
    if (!address || address !== root.ocrAddress) return
    ocrCaptureTimeout.stop()
    root.ocrWindow = null
    root.ocrGrabPending = false
    root.ocrImagePath = ""
    var value = Model.parseOcrTsv(text)
    if (value.text.trim() !== "") {
      var next = Object.assign({}, root.ocrTextByAddress)
      next[address] = value
      root.ocrTextByAddress = next
    }
    root.startNextOcr()
  }

  function completeOcrProcess(address, generation, text, path) {
    Quickshell.execDetached(["rm", "-f", path])
    if (generation === root.ocrGeneration && address === root.ocrAddress)
      root.finishOcr(address, text)
    else if (enabled && root.query.trim().length >= 3 && root.ocrAddress === "") {
      if (root.ocrQueue.length > 0) root.startNextOcr()
      else root.beginOcrIndex()
    }
  }

  property Timer ocrCaptureTimeout: Timer {
    interval: 1200
    onTriggered: root.finishOcr(root.ocrAddress, "")
  }

  property Process ocrProcess: Process {
    property string address: ""
    property int generation: -1
    property string path: ""
    property string output: ""
    property bool streamDone: false
    property bool exitedDone: false
    property bool active: false

    function maybeComplete() {
      if (active && streamDone && exitedDone) {
        active = false
        root.completeOcrProcess(address, generation, output, path)
      }
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        parent.output = text
        parent.streamDone = true
        parent.maybeComplete()
      }
    }
    onExited: {
      exitedDone = true
      maybeComplete()
    }
  }

  // A 1x1 non-interactive host keeps the capture in the scene graph while
  // grabToImage renders the full toplevel offscreen.
  property PanelWindow ocrHost: PanelWindow {
    visible: enabled && root.ocrCaptureSource !== null
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "piyush-omaswitch-ocr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true }
    mask: Region {}

    ScreencopyView {
      id: ocrCaptureView
      width: Math.max(1, implicitWidth)
      height: Math.max(1, implicitHeight)
      captureSource: root.ocrCaptureSource
      live: false
      paintCursor: false
      constraintSize: Qt.size(1920, 1920)
      onHasContentChanged: {
        if (hasContent) Qt.callLater(root.grabOcrFrame)
      }
    }
  }
}
