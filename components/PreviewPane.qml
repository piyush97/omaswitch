import QtQuick
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BorderSurface {
  id: root
  property Toplevel window: null
  property var highlights: []
  property bool captureEnabled: true
  readonly property bool opened: captureEnabled && visible
  property int previewConstraintWidth: 580
  property int previewConstraintHeight: 360

  property bool previewAvailable: false
  property Toplevel previewSourceA: null
  property Toplevel previewSourceB: null
  property int activePreview: -1
  property int pendingPreview: -1
  readonly property Toplevel previewTarget: root.opened ? root.window : null
  onPreviewTargetChanged: {
    if (!previewTarget) {
      root.resetPreview()
      return
    }
    root.queuePreview(previewTarget)
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

  function release(source) {
    if (source && (previewSourceA === source || previewSourceB === source))
      resetPreview()
  }
        radius: Style.cornerRadius
  color: Color.menu.scrim
  property var previewBorderSpec: Border.surfaceSpec("popups", "border", Color.menu.border, Math.max(1, Style.space(1)))
  borderSpec: Border.none()
  clip: false

  // Keep the capture inside the intended border bounds. The actual
  // border is drawn explicitly as the last/highest-z child below, so
  // screencopy rendering can never cover its top edge.
  Item {
    anchors.fill: parent
    anchors.topMargin: Border.top(root.previewBorderSpec)
    anchors.rightMargin: Border.right(root.previewBorderSpec)
    anchors.bottomMargin: Border.bottom(root.previewBorderSpec)
    anchors.leftMargin: Border.left(root.previewBorderSpec)
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
        model: root.highlights
        Rectangle {
          required property var modelData
          x: modelData.x * ocrHighlightLayer.width - 3
          y: modelData.y * ocrHighlightLayer.height - 2
          width: modelData.w * ocrHighlightLayer.width + 6
          height: modelData.h * ocrHighlightLayer.height + 4
          radius: 3
          color: Qt.rgba(Color.menu.selectedBackground.r, Color.menu.selectedBackground.g, Color.menu.selectedBackground.b, 0.25)
          border.color: Color.menu.selectedBackground
          border.width: 2
        }
      }
    }
  }

  BorderOverlay {
    anchors.fill: parent
    radius: root.radius
    borderSpec: root.previewBorderSpec
  }
}
