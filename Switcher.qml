import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Keyboard-first window switcher overlay with a live window peek.
//
// Opened with `omarchy-shell shell toggle piyush.omaswitch` (bind it to
// a key in ~/.config/hypr/bindings.lua). Lists Hyprland toplevels from the
// Quickshell Hyprland singleton, filters live as you type, and focuses the
// selection through the native Wayland toplevel API, with hyprctl as fallback.
//
// The right side shows a live preview (Windows-11-style "peek") of the
// highlighted window via two alternating ScreencopyViews. The current frame
// stays visible while the standby view starts the next capture, then swaps only
// after the new frame is ready.
// Two preview views handle smooth handoff; one extra capture runs only during
// local OCR search. No capture view is created per window. If the
// compositor lacks the hyprland-toplevel-export protocol (or the view gets
// no frames), the preview pane stays reserved but empty — the list width
// does not jump while captures load or swap between windows.

Item {
  id: root

  property var shell: null
  property var manifest: null

  // The plugin host hides us by calling close() after removing us from
  // openPanelIds; we must not fight it, so `opened` is only our UI state.
  property bool opened: false
  property bool geometryAnimationsReady: false
  property bool geometrySyncQueued: false
  property real displayedCardWidth: 0
  property real displayedCardHeight: 0
  property real cardXScale: 1
  property real cardYScale: 1
  property bool cycleMode: false
  property var mruAddresses: []
  property var pendingMruPromotions: []
  property string filterText: ""
  property int selectedIndex: 0
  property var ocrTextByAddress: ({})
  readonly property var previewHighlights: root.opened && selectedIndex >= 0 && selectedIndex < rows.length
    ? Model.ocrHighlights(rows[selectedIndex], filterText, root.ocrTextByAddress) : []
  property var ocrQueue: []
  property string ocrAddress: ""
  property int ocrGeneration: 0
  property bool ocrGrabPending: false
  property int ocrCaptureSerial: 0
  property string ocrImagePath: ""
  property HyprlandToplevel ocrWindow: null
  readonly property Toplevel ocrCaptureSource: root.ocrWindow && root.ocrWindow.wayland
    ? root.ocrWindow.wayland : null
  readonly property bool ocrSearching: root.ocrAddress !== "" || root.ocrQueue.length > 0 || ocrProcess.active
  property int openGeneration: 0

  // Scalar window snapshots + filtered rows; no QObjects in the delegate model.
  property var allWindows: []
  property var rows: []

  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int listGap: Style.space(4)
  readonly property int gap: Style.space(12)

  // Guard the index: assigning a shorter rows array notifies bindings before
  // rebuildRows() gets to clamp selectedIndex.
  readonly property HyprlandToplevel selectedToplevel: root.opened && selectedIndex >= 0 && selectedIndex < rows.length
    ? Model.windowForAddress(Hyprland.toplevels.values, rows[selectedIndex].address) : null
  property bool previewAvailable: false
  property Toplevel previewSourceA: null
  property Toplevel previewSourceB: null
  property int activePreview: -1
  property int pendingPreview: -1
  readonly property Toplevel previewTarget: root.opened && root.selectedToplevel && root.selectedToplevel.wayland
    ? root.selectedToplevel.wayland : null
  // Reserve the preview pane as soon as a capturable window is selected.
  // This keeps card geometry stable while the first screencopy frame arrives.
  readonly property bool previewLayout: root.opened && root.previewTarget !== null

  onPreviewTargetChanged: {
    if (!previewTarget) {
      root.resetPreview()
      return
    }
    root.queuePreview(previewTarget)
  }

  readonly property int cardWidth: Math.min(root.previewLayout ? Style.space(1080) : Style.space(760), panel.width - Style.gapsOut * 2)
  readonly property int desiredListHeight: Math.max(root.rowHeight, rows.length * root.rowHeight)
  readonly property int desiredCardHeight: root.contentMargin * 2 + root.headerHeight + root.listGap + root.desiredListHeight
  readonly property int cardHeight: Math.min(
    Math.max(root.previewLayout ? Style.space(400) : 0, root.desiredCardHeight),
    panel.height - Style.gapsOut * 2)
  readonly property int contentHeight: Math.max(0, root.displayedCardHeight - root.contentMargin * 2)
  readonly property int innerWidth: Math.max(0, root.displayedCardWidth - root.contentMargin * 2)
  readonly property int listWidth: root.previewLayout ? Math.max(Style.space(300), Math.round(root.innerWidth * 0.40)) : root.innerWidth
  readonly property int previewWidth: root.previewLayout ? Math.max(0, root.innerWidth - root.listWidth - root.gap) : 0
  readonly property int listHeight: Math.max(0, root.contentHeight - root.headerHeight - root.listGap)
  // Positive before the pane appears, so ScreencopyView can obtain its first
  // frame and flip hasContent without depending on a zero-sized parent.
  readonly property int previewConstraintWidth: Math.max(1, Math.min(Style.space(580), panel.width - Style.space(420)))
  readonly property int previewConstraintHeight: Math.max(1, Math.min(Style.space(360), panel.height - Style.gapsOut * 2 - root.contentMargin * 2))

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  function scheduleCardGeometrySync() {
    if (root.geometrySyncQueued) return
    root.geometrySyncQueued = true
    Qt.callLater(function() {
      root.geometrySyncQueued = false
      root.syncCardGeometry()
    })
  }

  function syncCardGeometry() {
    var nextWidth = root.cardWidth
    var nextHeight = root.cardHeight
    if (nextWidth <= 0 || nextHeight <= 0) return

    var oldVisualWidth = root.displayedCardWidth > 0
      ? root.displayedCardWidth * root.cardXScale : nextWidth
    var oldVisualHeight = root.displayedCardHeight > 0
      ? root.displayedCardHeight * root.cardYScale : nextHeight

    cardXAnimation.stop()
    cardYAnimation.stop()

    root.displayedCardWidth = nextWidth
    root.displayedCardHeight = nextHeight

    if (!root.geometryAnimationsReady) {
      root.cardXScale = 1
      root.cardYScale = 1
      return
    }

    // FLIP: snap layout once, then animate only the scene-graph transform.
    // This avoids re-laying out ListView/ScreencopyView/borders every frame.
    root.cardXScale = oldVisualWidth / nextWidth
    root.cardYScale = oldVisualHeight / nextHeight
    cardXAnimation.restart()
    cardYAnimation.restart()
  }

  onCardWidthChanged: root.scheduleCardGeometrySync()
  onCardHeightChanged: root.scheduleCardGeometrySync()

  NumberAnimation {
    id: cardXAnimation
    target: root
    property: "cardXScale"
    to: 1
    duration: 110
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: cardYAnimation
    target: root
    property: "cardYScale"
    to: 1
    duration: 110
    easing.type: Easing.OutCubic
  }

  function cancelPendingPreview() {
    var index = root.pendingPreview
    root.pendingPreview = -1
    previewCaptureTimeout.stop()
    if (index === 0) root.previewSourceA = null
    else if (index === 1) root.previewSourceB = null
  }

  function resetPreview() {
    root.cancelPendingPreview()
    root.previewSourceA = null
    root.previewSourceB = null
    root.activePreview = -1
    root.previewAvailable = false
  }

  Timer {
    id: previewCaptureTimeout
    interval: 300
    onTriggered: {
      var source = root.pendingPreview === 0 ? root.previewSourceA : root.previewSourceB
      root.cancelPendingPreview()
      if (root.opened && root.previewTarget && root.previewTarget !== source) {
        Qt.callLater(function() {
          if (root.opened) root.queuePreview(root.previewTarget)
        })
      }
    }
  }

  function queuePreview(source) {
    if (!root.opened || !source) return

    // Already showing the requested source.
    if (root.activePreview === 0 && root.previewSourceA === source) return
    if (root.activePreview === 1 && root.previewSourceB === source) return

    // Never retarget a ScreencopyView while it is waiting for a frame.
    // previewTarget still tracks newer selections; previewReady() will discard
    // this frame if it became stale and then queue only the newest target.
    if (root.pendingPreview >= 0) return

    var next = root.activePreview === 0 ? 1 : 0
    if (root.activePreview < 0) next = 0

    // Ping-pong buffers retain their previous frames. If the requested window
    // is already sitting in the standby buffer, assigning the same
    // captureSource again is a no-op and no hasContentChanged signal will fire.
    // Promote that already-ready frame immediately instead.
    if (next === 0 && root.previewSourceA === source && previewViewA.hasContent) {
      root.activePreview = 0
      root.previewAvailable = true
      return
    }
    if (next === 1 && root.previewSourceB === source && previewViewB.hasContent) {
      root.activePreview = 1
      root.previewAvailable = true
      return
    }

    root.pendingPreview = next
    previewCaptureTimeout.restart()
    if (next === 0)
      root.previewSourceA = source
    else
      root.previewSourceB = source
  }

  function previewReady(index) {
    if (root.pendingPreview !== index) return

    var source = index === 0 ? root.previewSourceA : root.previewSourceB
    if (!source) return

    if (source !== root.previewTarget) {
      // The capture completed for an older selection. Do not show it and do
      // not retarget from inside this hasContent callback. Clear the in-flight
      // state first, then queue the latest selection on the next event turn.
      root.cancelPendingPreview()
      Qt.callLater(function() {
        if (root.opened)
          root.queuePreview(root.previewTarget)
      })
      return
    }

    // Swap only after the currently selected source has a frame. Keep the
    // previous buffer alive behind it as standby for the next selection.
    root.activePreview = index
    root.pendingPreview = -1
    previewCaptureTimeout.stop()
    root.previewAvailable = true
  }

  function rebuildRows() {
    rows = Model.filteredWindows(allWindows, filterText, root.ocrTextByAddress)
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
    if (selectedIndex < 0 && rows.length > 0) selectedIndex = 0
  }

  function setFilter(value) {
    filterText = value
    selectedIndex = 0
    rebuildRows()
    if (filterText.trim().length >= 3)
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

  function resetOcr() {
    root.cancelOcrIndex()
    root.ocrTextByAddress = ({})
  }

  function beginOcrIndex() {
    if (!root.opened || root.filterText.trim().length < 3 || root.ocrSearching) return
    var queue = []
    for (var i = 0; i < root.allWindows.length; i++) {
      var key = Model.addressKey(root.allWindows[i])
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
    if (!root.opened || root.filterText.trim().length < 3) {
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
    root.rebuildRows()
    root.startNextOcr()
  }

  function completeOcrProcess(address, generation, text, path) {
    Quickshell.execDetached(["rm", "-f", path])
    if (generation === root.ocrGeneration && address === root.ocrAddress)
      root.finishOcr(address, text)
    else if (root.opened && root.filterText.trim().length >= 3 && root.ocrAddress === "") {
      if (root.ocrQueue.length > 0) root.startNextOcr()
      else root.beginOcrIndex()
    }
  }

  function refresh() {
    allWindows = Model.sortedWindows(Hyprland.toplevels.values, root.mruAddresses).map(Model.windowSnapshot)
    rebuildRows()
  }

  function seedMru(text) {
    var clients = []
    try { clients = JSON.parse(text || "[]") } catch (e) { clients = [] }
    var seeded = Model.addressesByHistory(clients)
    for (var i = root.pendingMruPromotions.length - 1; i >= 0; i--)
      seeded = Model.promoteAddress(seeded, root.pendingMruPromotions[i])
    root.pendingMruPromotions = []
    root.mruAddresses = seeded
    if (root.opened) root.refresh()
  }

  function iconSource(window) {
    var entries = DesktopEntries.applications.values || []
    var entry = Model.desktopEntryForWindow(window, entries)
    var library = root.shell ? root.shell.appLibrary : null
    if (entry && library && typeof library.iconSource === "function")
      return library.iconSource(entry.icon)
    if (entry && entry.icon) {
      var entryIcon = Quickshell.iconPath(String(entry.icon), true)
      if (entryIcon) return entryIcon
    }
    var appIcon = Quickshell.iconPath(Model.appId(window), true)
    if (appIcon) return appIcon
    return Quickshell.iconPath("application-x-executable", true)
  }

  // Selection waiting to be applied once this overlay is gone. See focusSelected().
  property var pendingFocus: null

  function applyPendingFocus() {
    var window = root.pendingFocus
    if (!window) return
    root.pendingFocus = null
    pendingFocusBackstop.stop()
    if (!Model.windowForAddress(Hyprland.toplevels.values, window.address)) return
    var command = Model.focusCommand(window)
    if (command) {
      Quickshell.execDetached(["sh", "-c", command])
    }
  }

  // Backstop only: if the compositor emits no restore -- nothing was focused
  // before we opened -- apply the selection anyway rather than dropping it.
  Timer {
    id: pendingFocusBackstop
    interval: 250
    repeat: false
    onTriggered: root.applyPendingFocus()
  }

  // This overlay takes WlrKeyboardFocus.Exclusive, and Hyprland hands keyboard
  // focus back to the previously focused toplevel when the layer surface
  // unmaps: `closelayer` is followed a few milliseconds later by an
  // activewindow/activewindowv2 naming the window focused before we opened.
  // Focusing the selection while the overlay is still mapped is therefore
  // undone by that restore.
  //
  // Dispatching first and dismissing immediately after only survived when the
  // spawned hyprctl lost the race against the unmap; when it won, the restore
  // clobbered the switch and releasing Alt appeared to do nothing. Dismiss
  // first, then apply the selection once the restore has landed.
  function focusSelected() {
    var window = rows[selectedIndex]
    if (!window) return root.dismiss()
    root.pendingFocus = window
    root.dismiss()
    pendingFocusBackstop.restart()
  }

  function select(delta) {
    if (rows.length === 0) return
    selectedIndex = (selectedIndex + delta + rows.length) % rows.length
    keepSelectionVisible.restart()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var direction = Number(payload.direction) < 0 ? -1 : 1

    // Repeated Alt+Tab summons cycle instead of resetting or closing.
    if (root.opened && payload.mode === "cycle") {
      root.cycleMode = true
      root.select(direction)
      return
    }

    root.openGeneration++
    var generation = root.openGeneration
    root.pendingFocus = null
    pendingFocusBackstop.stop()
    root.resetPreview()
    root.resetOcr()
    root.cycleMode = payload.mode === "cycle"
    root.filterText = ""
    root.selectedIndex = 0

    // Build the initial model and choose the initial row before making the
    // PanelWindow visible. previewLayout can therefore start at its final
    // geometry instead of growing after the first screencopy frame arrives.
    root.refresh()
    if (root.shell && root.shell.appLibrary && typeof root.shell.appLibrary.refreshIcons === "function")
      root.shell.appLibrary.refreshIcons()
    // rows[0] is the focused window by construction, so its neighbour is
    // always a genuine switch target.
    if (root.cycleMode && root.rows.length > 1)
      root.selectedIndex = direction < 0 ? root.rows.length - 1 : 1

    root.geometryAnimationsReady = false
    root.opened = true
    Qt.callLater(function() {
      if (!root.opened || generation !== root.openGeneration) return
      root.geometryAnimationsReady = true
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.openGeneration++
    root.geometryAnimationsReady = false
    root.opened = false
    root.cycleMode = false
    root.resetPreview()
    root.resetOcr()
    root.rows = []
    root.allWindows = []
  }

  // User-initiated dismissal also drops the host's openPanelIds entry.
  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "piyush.omaswitch")
  }

  Connections {
    target: Hyprland.toplevels
    function onObjectRemovedPre(window) {
      root.resetOcr()
      var source = window ? window.wayland : null
      if (root.selectedToplevel === window || root.previewSourceA === source || root.previewSourceB === source)
        root.resetPreview()
    }
    function onObjectInsertedPost() {
      if (root.opened) {
        root.resetOcr()
        root.refresh()
        root.beginOcrIndex()
      }
    }
    function onObjectRemovedPost() {
      if (root.opened) {
        root.refresh()
        root.beginOcrIndex()
      }
    }
  }

  // Keep the list fresh while open (windows open/close/rename).
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name || "") : ""
      if (name === "activewindowv2") {
        var address = event ? String(event.data || "") : ""
        root.mruAddresses = Model.promoteAddress(root.mruAddresses, address)
        if (mruSeedProcess.running)
          root.pendingMruPromotions = Model.promoteAddress(root.pendingMruPromotions, address)
        // The post-unmap focus restore is the cue to apply a pending
        // selection; applying before it would simply be overwritten.
        if (root.pendingFocus) {
          root.applyPendingFocus()
          return
        }
      }
      if (!root.opened) return
      if (name === "activewindow" || name === "closewindow" || name === "openwindow" ||
          name === "workspace" || name === "movewindow" || name.indexOf("windowtitle") === 0) {
        root.refresh()
      }
    }
  }

  Component.onCompleted: root.syncCardGeometry()
  Process {
    id: mruSeedProcess
    command: ["hyprctl", "clients", "-j"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.seedMru(text)
    }
  }

  // Do not bind ListView.currentIndex here. On Qt 6.11, changing that binding
  // while a JavaScript array model is creating delegates can crash Qt. The
  // row already draws its own selected state, so only coalesce scroll requests.
  Timer {
    id: keepSelectionVisible
    interval: 0
    onTriggered: {
      if (root.opened && root.selectedIndex >= 0 && root.selectedIndex < root.rows.length)
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
  }

  Timer {
    id: ocrCaptureTimeout
    interval: 1200
    onTriggered: root.finishOcr(root.ocrAddress, "")
  }

  Process {
    id: ocrProcess
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
        ocrProcess.output = text
        ocrProcess.streamDone = true
        ocrProcess.maybeComplete()
      }
    }
    onExited: {
      exitedDone = true
      maybeComplete()
    }
  }

  // A 1x1 non-interactive host keeps the capture in the scene graph while
  // grabToImage renders the full toplevel offscreen.
  PanelWindow {
    id: ocrHost
    visible: root.opened && root.ocrCaptureSource !== null
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "piyush-omaswitch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.displayedCardWidth
      height: root.displayedCardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent

      transform: Scale {
        origin.x: card.width / 2
        origin.y: card.height / 2
        xScale: root.cardXScale
        yScale: root.cardYScale
      }
      color: root.background
      borderSpec: root.borderSpec

      Row {
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: root.gap

        Column {
          width: root.listWidth
          height: parent.height
          spacing: root.listGap

          Text {
            text: root.filterText === "" ? "Switch window…" :
              "Filter: " + root.filterText + (root.ocrSearching ? " · searching contents…" : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
            width: parent.width
          }

          ListView {
            id: listView
            width: parent.width
            height: root.listHeight
            model: root.rows
            clip: true

            Text {
              parent: listView
              anchors.centerIn: parent
              visible: root.rows.length === 0
              text: root.ocrSearching ? "Searching window contents…" :
                (root.filterText ? "No matching windows" : "No windows")
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            delegate: Item {
              width: listView.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: index === root.selectedIndex ? root.selectedBackground : "transparent"
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                width: parent.width - Style.space(20)
                spacing: Style.space(8)

                Image {
                  width: Style.space(30)
                  height: Style.space(30)
                  anchors.verticalCenter: parent.verticalCenter
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  source: root.iconSource(modelData)
                  asynchronous: true
                }

                Column {
                  width: parent.width - Style.space(38)
                  spacing: 2

                  Text {
                    text: Model.label(modelData)
                    textFormat: Text.PlainText
                    color: index === root.selectedIndex ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: parent.width
                  }
                  Text {
                    text: Model.detail(modelData)
                    textFormat: Text.PlainText
                    color: index === root.selectedIndex ? root.selectedText : root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: { root.selectedIndex = index; root.focusSelected() }
              }
            }
          }
        }

        // Right-side peek pane. Space is reserved while a previewable window is
        // selected; the capture view fades in once frames arrive.
        BorderSurface {
          id: previewPane
          visible: root.previewLayout
          width: root.previewWidth
          height: parent.height
          radius: root.cornerRadius
          color: Qt.rgba(0, 0, 0, 0.25)
          property var previewBorderSpec: Border.surfaceSpec("popups", "border", root.border, Math.max(1, Style.space(1)))
          borderSpec: Border.none()
          clip: false

          // Keep the capture inside the intended border bounds. The actual
          // border is drawn explicitly as the last/highest-z child below, so
          // screencopy rendering can never cover its top edge.
          Item {
            anchors.fill: parent
            anchors.topMargin: Border.top(previewPane.previewBorderSpec)
            anchors.rightMargin: Border.right(previewPane.previewBorderSpec)
            anchors.bottomMargin: Border.bottom(previewPane.previewBorderSpec)
            anchors.leftMargin: Border.left(previewPane.previewBorderSpec)
            clip: true

            ScreencopyView {
              id: previewViewA
              anchors.centerIn: parent
              z: root.activePreview === 0 ? 1 : 0
              opacity: root.activePreview === 0 ? 1 : 0
              captureSource: root.previewSourceA
              live: root.opened && root.previewSourceA !== null
              paintCursor: false
              constraintSize: Qt.size(
                Math.min(root.previewConstraintWidth, parent.width),
                Math.min(root.previewConstraintHeight, parent.height))
              onHasContentChanged: if (hasContent) root.previewReady(0)
            }

            ScreencopyView {
              id: previewViewB
              anchors.centerIn: parent
              z: root.activePreview === 1 ? 1 : 0
              opacity: root.activePreview === 1 ? 1 : 0
              captureSource: root.previewSourceB
              live: root.opened && root.previewSourceB !== null
              paintCursor: false
              constraintSize: Qt.size(
                Math.min(root.previewConstraintWidth, parent.width),
                Math.min(root.previewConstraintHeight, parent.height))
              onHasContentChanged: if (hasContent) root.previewReady(1)
            }

            // Where an OCR-only match was found, from Tesseract's layout boxes.
            Item {
              id: ocrHighlightLayer
              readonly property ScreencopyView view: root.activePreview === 1 ? previewViewB : previewViewA
              clip: true
              x: view.x
              y: view.y
              width: view.width
              height: view.height
              z: 2
              visible: root.previewAvailable && root.activePreview >= 0 && root.previewTarget === view.captureSource

              Repeater {
                model: root.previewHighlights
                Rectangle {
                  required property var modelData
                  x: modelData.x * ocrHighlightLayer.width - 3
                  y: modelData.y * ocrHighlightLayer.height - 2
                  width: modelData.w * ocrHighlightLayer.width + 6
                  height: modelData.h * ocrHighlightLayer.height + 4
                  radius: 3
                  color: Qt.rgba(root.selectedBackground.r, root.selectedBackground.g, root.selectedBackground.b, 0.25)
                  border.color: root.selectedBackground
                  border.width: 2
                }
              }
            }
          }

          BorderOverlay {
            anchors.fill: parent
            radius: previewPane.radius
            borderSpec: previewPane.previewBorderSpec
          }
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      z: 1
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.focusSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
          root.select((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }

      // Best-effort native Alt-Tab behavior. If the compositor delivers the
      // modifier release after granting this overlay focus, commit selection.
      Keys.onReleased: function(event) {
        if (root.cycleMode && (event.key === Qt.Key_Alt || event.key === Qt.Key_Meta)) {
          root.focusSelected()
          event.accepted = true
        }
      }
    }
  }
}
