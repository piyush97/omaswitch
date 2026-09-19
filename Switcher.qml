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
// highlighted window via two alternating ScreencopyViews. The current frame
// stays visible while the standby view starts the next capture, then swaps only
// after the new frame is ready.
// Wayland toplevel handle. One live stream, not one per window. If the
// compositor lacks the hyprland-toplevel-export protocol (or the view gets
// no frames), the preview pane stays reserved for stable geometry but remains
// empty until a frame becomes available.

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
  property bool previewAvailable: false
  property var previewSourceA: null
  property var previewSourceB: null
  property int activePreview: -1
  property int pendingPreview: -1
  readonly property var previewTarget: root.opened && root.selectedToplevel && root.selectedToplevel.wayland
    ? root.selectedToplevel.wayland : null
  // Reserve the preview pane as soon as a capturable window is selected.
  // This keeps card geometry stable while the first screencopy frame arrives.
  readonly property bool previewActive: root.opened && root.previewTarget !== null

  onPreviewTargetChanged: {
    if (!previewTarget) {
      root.previewAvailable = false
      root.pendingPreview = -1
      return
    }
    root.queuePreview(previewTarget)
  }

  readonly property int cardWidth: Math.min(root.previewActive ? Style.space(1080) : Style.space(760), panel.width - Style.gapsOut * 2)
  readonly property int desiredListHeight: Math.max(root.rowHeight, rows.length * root.rowHeight)
  readonly property int desiredCardHeight: root.contentMargin * 2 + root.headerHeight + root.listGap + root.desiredListHeight
  readonly property int cardHeight: Math.min(
    Math.max(root.previewActive ? Style.space(400) : 0, root.desiredCardHeight),
    panel.height - Style.gapsOut * 2)
  readonly property int contentHeight: Math.max(0, root.displayedCardHeight - root.contentMargin * 2)
  readonly property int innerWidth: Math.max(0, root.displayedCardWidth - root.contentMargin * 2)
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
      root.pendingPreview = -1
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
    root.previewAvailable = true
  }

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

  function refresh() {
    allWindows = Model.sortedWindows(Hyprland.toplevels.values)
    rebuildRows()
  }

  function focusSelected() {
    var window = rows[selectedIndex]
    if (!window) return root.dismiss()
    var command = Model.focusCommand(window)
    if (command) {
      Quickshell.execDetached(["sh", "-c", command])
    } else if (window.wayland && typeof window.wayland.activate === "function") {
      window.wayland.activate()
    }
    root.dismiss()
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

    root.previewAvailable = false
    root.previewSourceA = null
    root.previewSourceB = null
    root.activePreview = -1
    root.pendingPreview = -1
    root.cycleMode = payload.mode === "cycle"
    root.filterText = ""
    root.selectedIndex = 0

    // Build the initial model and choose the initial row before making the
    // PanelWindow visible. previewActive can therefore start at its final
    // geometry instead of growing after the first screencopy frame arrives.
    root.refresh()
    if (root.cycleMode && root.rows.length > 1 && Model.isCurrent(root.rows[0]))
      root.selectedIndex = direction < 0 ? root.rows.length - 1 : 1

    root.geometryAnimationsReady = false
    root.opened = true
    Qt.callLater(function() {
      root.geometryAnimationsReady = true
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.geometryAnimationsReady = false
    root.opened = false
    root.cycleMode = false
  }

  // User-initiated dismissal also drops the host's openPanelIds entry.
  function dismiss() {
    root.geometryAnimationsReady = false
    root.opened = false
    root.cycleMode = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "piyush.omaswitch")
  }

  // Keep the list fresh while open (windows open/close/rename).
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened) return
      var name = event ? String(event.name || "") : ""
      if (name === "activewindow" || name === "closewindow" || name === "openwindow" ||
          name === "workspace" || name === "movewindow" || name.indexOf("windowtitle") === 0) {
        root.refresh()
      }
    }
  }

  Component.onCompleted: root.syncCardGeometry()

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
          id: previewPane
          visible: root.previewActive
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
