import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "services"
import "components"

Item {
  id: root

  property var shell: null
  property var manifest: null

  // The plugin host hides us by calling close() after removing us from
  // openPanelIds; we must not fight it, so `opened` is only our UI state.
  property bool opened: false
  property bool geometryAnimationsReady: false
  property bool cycleMode: false
  property string cycleApp: ""
  property var closingAddresses: ({})
  property var mruAddresses: []
  property var pendingMruPromotions: []
  property string filterText: ""
  property int selectedIndex: -1
  property bool helpOpen: false
  property bool settingsOpen: false
  property var targetScreen: null
  readonly property var candidates: cycleApp ? allWindows.filter(window => Model.appId(window) === cycleApp)
    : Model.scopedWindows(allWindows, pluginSettings.values.scope, {
        workspaceId: Hyprland.focusedWorkspace?.id,
        monitorName: Hyprland.focusedMonitor?.name
      })
  onCandidatesChanged: {
    if (!root.opened) return
    root.rebuildRows()
    ocrIndexer.beginOcrIndex()
  }
  readonly property var selectedWindow: rows[selectedIndex]?.window || null
  readonly property var previewHighlights: root.opened && selectedWindow
    ? Model.ocrHighlights(selectedWindow, filterText, ocrIndexer.textByAddress) : []
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
  readonly property HyprlandToplevel selectedToplevel: root.opened && selectedWindow
    ? Model.windowForAddress(Hyprland.toplevels.values, selectedWindow.address) : null
  readonly property Toplevel previewTarget: root.selectedToplevel ? root.selectedToplevel.wayland : null
  readonly property bool previewLayout: root.opened && pluginSettings.values.livePreview && root.previewTarget !== null

  readonly property int cardWidth: Math.min(root.previewLayout ? Style.space(1080) : Style.space(760), panel.width - Style.gapsOut * 2)
  readonly property bool offerSetup: !cycleMode && !settingsOpen && !helpOpen && bindingsSetup.loaded &&
    !pluginSettings.values.setupDismissed && (bindingsSetup.state === null ||
      (!bindingsSetup.state.managed && !bindingsSetup.state.handWritten))
  property bool dismissedSetup: false
  readonly property int setupHeight: offerSetup && !dismissedSetup ? setupBanner.implicitHeight + listGap : 0
  readonly property int footerHeight: cycleMode || helpOpen || settingsOpen ? 0 : Style.space(24)
  readonly property int desiredListHeight: Math.max(root.rowHeight * 2, rows.length * root.rowHeight * (filterText ? 1.35 : 1))
  readonly property int desiredCardHeight: root.contentMargin * 2 + root.headerHeight + root.listGap + root.desiredListHeight + footerHeight + setupHeight
  readonly property int cardHeight: Math.min(
    Math.max(root.previewLayout || root.helpOpen || root.settingsOpen ? Style.space(400) : 0, root.desiredCardHeight),
    panel.height - Style.gapsOut * 2)
  readonly property int contentHeight: Math.max(0, card.height - root.contentMargin * 2)
  readonly property int innerWidth: Math.max(0, card.width - root.contentMargin * 2)
  readonly property int listWidth: root.previewLayout ? Math.max(Style.space(300), Math.round(root.innerWidth * 0.40)) : root.innerWidth
  readonly property int previewWidth: root.previewLayout ? Math.max(0, root.innerWidth - root.listWidth - root.gap) : 0
  readonly property int listHeight: Math.max(0, root.contentHeight - root.setupHeight - root.headerHeight - root.listGap - root.footerHeight - (root.footerHeight ? root.listGap : 0))
  // Positive before the pane appears, so ScreencopyView can obtain its first
  // frame and flip hasContent without depending on a zero-sized parent.
  readonly property int previewConstraintWidth: Math.max(1, Math.min(Style.space(580), panel.width - Style.space(420)))
  readonly property int previewConstraintHeight: Math.max(1, Math.min(Style.space(360), panel.height - Style.gapsOut * 2 - root.contentMargin * 2))

  function rebuildRows() {
    var address = Model.addressKey(selectedWindow)
    var filtered = Model.filteredWindows(candidates, filterText, ocrIndexer.textByAddress)
    rows = Model.displayRows(filtered, { group: !cycleMode && pluginSettings.values.groupByWorkspace })
    var retained = address ? rows.findIndex(row => row.kind === "window" && Model.addressKey(row.window) === address) : -1
    selectedIndex = Model.clampSelection(rows, retained >= 0 ? retained : selectedIndex)
  }

  function setFilter(value) {
    filterText = value
    selectedIndex = -1
    rebuildRows()
  }

  function refresh() {
    allWindows = Model.sortedWindows(Model.managedWindows(Hyprland.toplevels.values), root.mruAddresses).map(Model.windowSnapshot)
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
    var window = selectedWindow
    if (!window) return root.dismiss()
    root.pendingFocus = window
    root.dismiss()
    pendingFocusBackstop.restart()
  }

  function select(delta) {
    selectedIndex = cycleApp ? Model.appCycleIndex(rows, selectedIndex, delta) : Model.stepWindowRow(rows, selectedIndex, delta)
    keepSelectionVisible.restart()
  }

  function closeSelected() {
    var address = Model.closeTarget(selectedWindow)
    if (!address || closingAddresses[address]) return
    var target = selectedToplevel
    if (!target) return
    closingAddresses = Object.assign({}, closingAddresses, { [address]: true })
    if (target.wayland && typeof target.wayland.close === "function") target.wayland.close()
    else Quickshell.execDetached(["hyprctl", "dispatch", "closewindow", "address:" + address])
    closingBackstop.restart()
  }

  Timer {
    id: closingBackstop
    interval: 3000
    onTriggered: root.closingAddresses = ({})
  }

  function moveSelectedHere() {
    var workspace = Hyprland.focusedWorkspace
    if (!workspace || !selectedToplevel) return
    var command = Model.moveHereLua(selectedWindow, workspace.id)
    if (!command) return
    Hyprland.dispatch(command)
    focusSelected()
  }

  function jump(number) {
    var index = Model.windowRowIndex(root.rows, number)
    if (index < 0) return
    root.selectedIndex = index
    root.focusSelected()
  }

  function setSettingsOpen(value) {
    settingsOpen = value
    helpOpen = false
    if (value) {
      bindingsSetup.refresh()
      settingsView.focusFirst()
    }
    else keyCatcher.forceActiveFocus()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var direction = Number(payload.direction) < 0 ? -1 : 1

    // Repeated Alt+Tab summons cycle instead of resetting or closing.
    var appScope = payload.mode === "cycle" && payload.scope === "app"
    if (root.opened && payload.mode === "cycle") {
      root.cycleMode = true
      root.helpOpen = false
      if (root.settingsOpen) root.setSettingsOpen(false)
      root.cycleApp = appScope ? (root.cycleApp || Model.appId(root.selectedWindow)) : ""
      if (appScope) root.filterText = ""
      root.rebuildRows()
      root.select(direction)
      return
    }

    root.openGeneration++
    var generation = root.openGeneration
    root.pendingFocus = null
    pendingFocusBackstop.stop()
    previewPane.resetPreview()
    ocrIndexer.reset()
    root.cycleMode = payload.mode === "cycle"
    root.cycleApp = ""
    root.filterText = ""
    root.helpOpen = false
    root.settingsOpen = false
    var monitorName = Hyprland.focusedMonitor?.name
    root.targetScreen = Quickshell.screens.find(screen => screen.name === monitorName) || null
    if (!root.cycleMode) bindingsSetup.refresh()
    root.selectedIndex = -1

    // Build the initial model and choose the initial row before making the
    // PanelWindow visible. previewLayout can therefore start at its final
    // geometry instead of growing after the first screencopy frame arrives.
    root.refresh()
    if (appScope) {
      root.cycleApp = Model.appId(root.allWindows[0])
      root.rebuildRows()
    }
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
    root.helpOpen = false
    root.settingsOpen = false
    root.cycleMode = false
    root.cycleApp = ""
    root.closingAddresses = ({})
    closingBackstop.stop()
    previewPane.resetPreview()
    ocrIndexer.reset()
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
      ocrIndexer.reset()
      var source = window ? window.wayland : null
      previewPane.release(source)
    }
    function onObjectInsertedPost() {
      if (root.opened) {
        ocrIndexer.reset()
        root.refresh()
        ocrIndexer.beginOcrIndex()
      }
    }
    function onObjectRemovedPost() {
      if (root.opened) {
        root.refresh()
        ocrIndexer.beginOcrIndex()
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
        listView.reveal(root.selectedIndex)
    }
  }

  OcrIndexer {
    id: ocrIndexer
    windows: root.candidates
    query: root.filterText
    enabled: root.opened && pluginSettings.values.contentSearch
    onEnabledChanged: if (!enabled) reset()
    onTextByAddressChanged: root.rebuildRows()
  }

  PluginSettings {
    id: pluginSettings
    pluginId: (root.manifest && root.manifest.id) || "piyush.omaswitch"
    shell: root.shell
    onValuesChanged: if (root.opened) root.rebuildRows()
  }

  BindingsSetup { id: bindingsSetup }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "piyush-omaswitch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    SwitcherCard {
      id: card
      anchors.centerIn: parent
      cardWidth: root.cardWidth
      cardHeight: root.cardHeight
      geometryAnimationsReady: root.geometryAnimationsReady

      SetupBanner {
        id: setupBanner
        visible: root.offerSetup && !root.dismissedSetup
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.contentMargin
        missing: bindingsSetup.missing
        busy: bindingsSetup.busy
        error: bindingsSetup.error
        onSetupRequested: { bindingsSetup.apply(); keyCatcher.forceActiveFocus() }
        onDismissed: {
          root.dismissedSetup = true
          pluginSettings.set("setupDismissed", true)
          keyCatcher.forceActiveFocus()
        }
      }
      Row {
        visible: !root.settingsOpen
        anchors.fill: parent
        anchors.margins: root.contentMargin
        anchors.topMargin: root.contentMargin + root.setupHeight
        spacing: root.gap

        Column {
          width: root.listWidth
          height: parent.height
          spacing: root.listGap

          SearchField {
            width: parent.width
            height: root.headerHeight
            text: root.filterText
            searching: ocrIndexer.searching
            showHelp: !root.cycleMode
            showSettings: !root.cycleMode
            onSettingsRequested: root.setSettingsOpen(true)
            onHelpRequested: { root.helpOpen = !root.helpOpen; keyCatcher.forceActiveFocus() }
          }

          WindowList {
            id: listView
            width: parent.width
            visible: !root.helpOpen || root.previewLayout
            height: visible ? root.listHeight : 0
            rows: root.rows
            closingAddresses: root.closingAddresses
            rowHeight: root.rowHeight
            selectedIndex: root.selectedIndex
            iconSource: root.iconSource
            query: root.filterText
            snippetFor: window => Model.matchSnippet(window, root.filterText, ocrIndexer.textByAddress)
            emptyText: root.candidates.length === 0 ? (root.allWindows.length === 0 ? "No windows" : "No windows in this scope") :
              'No match for "' + root.filterText + '"' + (ocrIndexer.searching ? "\nSearching window contents…" : "")
            onActivated: function(index) { root.selectedIndex = index; root.focusSelected() }
          }
          FooterHints {
            width: parent.width
            height: root.footerHeight
            cycleMode: root.cycleMode
            visible: root.footerHeight > 0
            text: "Enter switch · Ctrl+W close · Ctrl+M move · Alt+1–9 jump · Ctrl+, settings"
          }
        }

        // Right-side peek pane. Space is reserved while a previewable window is
        // selected; the capture view fades in once frames arrive.
        PreviewPane {
          id: previewPane
          visible: root.previewLayout && !root.helpOpen
          width: root.previewWidth
          height: parent.height
          window: root.previewTarget
          highlights: root.previewHighlights
          captureEnabled: root.opened && root.previewLayout && !root.settingsOpen && !root.helpOpen
          previewConstraintWidth: root.previewConstraintWidth
          previewConstraintHeight: root.previewConstraintHeight
        }
      }
      SettingsView {
        id: settingsView
        anchors.fill: parent
        anchors.margins: root.contentMargin
        visible: root.settingsOpen
        values: pluginSettings.values
        ready: pluginSettings.ready
        bindingState: bindingsSetup.state
        bindingsLoaded: bindingsSetup.loaded
        bindingsBusy: bindingsSetup.busy
        bindingsError: bindingsSetup.error
        onSetupRequested: bindingsSetup.apply()
        onRemoveRequested: bindingsSetup.remove()
        onChanged: (key, value) => pluginSettings.set(key, value)
        onClosed: root.setSettingsOpen(false)
      }
      ScrollView {
        visible: root.helpOpen
        anchors.fill: parent
        anchors.margins: root.contentMargin
        anchors.topMargin: root.contentMargin + (root.previewLayout ? 0 : root.headerHeight + root.listGap)
        anchors.leftMargin: root.contentMargin + (root.previewLayout ? root.listWidth + root.gap : 0)
        contentWidth: availableWidth
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Shortcuts\n↑ / ↓ or Tab: Select\nEnter: Switch\nAlt+1–9: Jump\nAlt+Tab / Alt+Shift+Tab: Cycle\nAlt+`: Cycle within app\nCtrl+W: Close window\nCtrl+M: Move here\nCtrl+,: Settings\nEsc: Back"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
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
          if (root.helpOpen) root.helpOpen = false
          else root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Question && (root.helpOpen || !root.filterText)) {
          root.helpOpen = !root.helpOpen
          event.accepted = true
        } else if (!root.cycleMode && event.key === Qt.Key_Comma && event.modifiers === Qt.ControlModifier) {
          root.setSettingsOpen(true)
          event.accepted = true
        } else if (root.helpOpen) {
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 &&
                   (event.modifiers === Qt.AltModifier || (root.cycleMode && event.modifiers === Qt.NoModifier))) {
          root.jump(event.key - Qt.Key_0)
          event.accepted = true
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_W) {
          root.closeSelected()
          event.accepted = true
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_M) {
          root.moveSelectedHere()
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
