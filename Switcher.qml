import QtQuick
import Quickshell
import Quickshell.Hyprland
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
// highlighted window via a single ScreencopyView bound to that window's
// Wayland toplevel handle. One live stream, not one per window. If the
// compositor lacks the hyprland-toplevel-export protocol (or the view gets
// no frames), hasContent stays false and the list simply stays full-width —
// the same layout as the plain list version.

Item {
  id: root

  property var shell: null
  property var manifest: null

  // The plugin host hides us by calling close() after removing us from
  // openPanelIds; we must not fight it, so `opened` is only our UI state.
  property bool opened: false
  property bool cycleMode: false
  property bool previewAvailable: false
  property string filterText: ""
  property int selectedIndex: 0

  // Raw toplevels (live objects from the Hyprland singleton) + filtered rows.
  property var allWindows: []
  property var rows: []

  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int listGap: Style.space(4)
  readonly property int gap: Style.space(12)

  // Guard the index: assigning a shorter rows array notifies bindings before
  // rebuildRows() gets to clamp selectedIndex.
  readonly property var selectedToplevel: selectedIndex >= 0 && selectedIndex < rows.length ? rows[selectedIndex] : null
  readonly property bool previewWanted: root.opened && root.selectedToplevel !== null && !!root.selectedToplevel.wayland
  // Keep the preview layout stable after the first frame arrives. Changing
  // captureSource briefly clears hasContent; collapsing the pane during that
  // gap makes the whole switcher visibly flash on every cycle.
  readonly property bool previewActive: root.previewWanted && (root.previewAvailable || previewView.hasContent)

  onSelectedToplevelChanged: {
    if (!root.previewWanted) {
      root.previewAvailable = false
      previewFallbackTimer.stop()
    } else if (root.previewAvailable) {
      // Preserve the current geometry while the new capture source starts,
      // but still allow the list-only fallback if it produces no frame.
      previewFallbackTimer.restart()
    }
  }

  Timer {
    id: previewFallbackTimer
    interval: 300
    onTriggered: {
      if (!previewView.hasContent) root.previewAvailable = false
    }
  }

  readonly property int cardWidth: Math.min(root.previewActive ? Style.space(1080) : Style.space(760), panel.width - Style.gapsOut * 2)
  readonly property int desiredListHeight: Math.max(root.rowHeight, rows.length * root.rowHeight)
  readonly property int desiredCardHeight: root.contentMargin * 2 + root.headerHeight + root.listGap + root.desiredListHeight
  readonly property int cardHeight: Math.min(
    Math.max(root.previewActive ? Style.space(400) : 0, root.desiredCardHeight),
    panel.height - Style.gapsOut * 2)
  readonly property int contentHeight: Math.max(0, root.cardHeight - root.contentMargin * 2)
  readonly property int innerWidth: Math.max(0, root.cardWidth - root.contentMargin * 2)
  readonly property int listWidth: root.previewActive ? Math.max(Style.space(300), Math.round(root.innerWidth * 0.40)) : root.innerWidth
  readonly property int previewWidth: root.previewActive ? Math.max(0, root.innerWidth - root.listWidth - root.gap) : 0
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

  function rebuildRows() {
    rows = Model.filteredWindows(allWindows, filterText)
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
    if (selectedIndex < 0 && rows.length > 0) selectedIndex = 0
  }

  function setFilter(value) {
    filterText = value
    selectedIndex = 0
    rebuildRows()
  }

  // Addresses of windows we have seen focused, most recent first.
  //
  // Ranking straight off lastIpcObject.focusHistoryID is not reliable: that
  // object is a cached snapshot which is not refreshed when focus moves, so it
  // can name a stale window as rank 0. A window's Wayland `activated` flag is
  // no help either, since it reads false for every toplevel while this overlay
  // holds exclusive keyboard focus. Tracking the compositor's own
  // activewindowv2 events keeps the order correct; focusHistoryID stays the
  // seed for windows we have not yet seen focused (it is accurate at startup).
  property var mru: []

  function noteFocus(rawAddress) {
    var address = Model.normalizeAddress(rawAddress)
    if (!address || (root.mru.length > 0 && root.mru[0] === address)) return
    var next = [address]
    for (var i = 0; i < root.mru.length; i++)
      if (root.mru[i] !== address) next.push(root.mru[i])
    root.mru = next
  }

  function mruRank(window) {
    var address = Model.normalizeAddress(window && window.address)
    var index = address ? root.mru.indexOf(address) : -1
    return index >= 0 ? index : 1000000 + Model.historyRank(window)
  }

  function refresh() {
    allWindows = Model.sortedWindows(Hyprland.toplevels.values, root.mruRank)
    rebuildRows()
  }

  // Selection waiting to be applied once this overlay is gone. See focusSelected().
  property var pendingFocus: null

  function applyPendingFocus() {
    var window = root.pendingFocus
    if (!window) return
    root.pendingFocus = null
    pendingFocusBackstop.stop()
    var command = Model.focusCommand(window)
    if (command) {
      Quickshell.execDetached(["sh", "-c", command])
    } else if (window.wayland && typeof window.wayland.activate === "function") {
      window.wayland.activate()
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

    root.opened = true
    root.cycleMode = payload.mode === "cycle"
    root.previewAvailable = false
    root.filterText = ""
    root.selectedIndex = 0
    root.refresh()
    // rows[0] is the focused window by construction, so its neighbour is
    // always a genuine switch target.
    if (root.cycleMode && root.rows.length > 1)
      root.selectedIndex = direction < 0 ? root.rows.length - 1 : 1
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.cycleMode = false
    root.previewAvailable = false
  }

  // User-initiated dismissal also drops the host's openPanelIds entry.
  function dismiss() {
    root.opened = false
    root.cycleMode = false
    root.previewAvailable = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "piyush.omaswitch")
  }

  // Keep the list fresh while open (windows open/close/rename).
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name || "") : ""
      if (name === "activewindowv2") {
        // Tracked even while closed -- that is what keeps the order correct.
        root.noteFocus(event.data)
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
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
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
            text: root.filterText === "" ? "Switch window…" : "Filter: " + root.filterText
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
            currentIndex: root.selectedIndex
            clip: true

            Text {
              parent: listView
              anchors.centerIn: parent
              visible: root.rows.length === 0
              text: root.filterText ? "No matching windows" : "No windows"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            delegate: Item {
              required property var modelData
              required property int index
              width: listView.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: index === root.selectedIndex ? root.selectedBackground : "transparent"
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                width: parent.width - Style.space(20)
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

              MouseArea {
                anchors.fill: parent
                onClicked: { root.selectedIndex = index; root.focusSelected() }
              }
            }
          }
        }

        // Right-side peek pane. Only visible once the view actually has a
        // frame; width collapses to 0 and the list takes the whole card when
        // the compositor cannot export windows.
        BorderSurface {
          visible: root.previewActive
          width: root.previewWidth
          height: parent.height
          radius: root.cornerRadius
          color: Qt.rgba(0, 0, 0, 0.25)
          borderSpec: Border.surfaceSpec("popups", "border", root.border, Math.max(1, Style.space(1)))
          clip: true

          ScreencopyView {
            id: previewView
            anchors.centerIn: parent
            captureSource: root.previewWanted ? root.selectedToplevel.wayland : null
            live: root.previewWanted
            paintCursor: false
            constraintSize: Qt.size(root.previewConstraintWidth, root.previewConstraintHeight)
            onHasContentChanged: {
              if (hasContent) {
                root.previewAvailable = true
                previewFallbackTimer.stop()
              }
            }
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
