import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BorderSurface {
  id: root
  property real cardWidth: 0
  property real cardHeight: 0
  property bool geometryAnimationsReady: false
  property bool geometrySyncQueued: false
  property real displayedCardWidth: 0
  property real displayedCardHeight: 0
  property real cardXScale: 1
  property real cardYScale: 1
  width: displayedCardWidth
  height: displayedCardHeight
  radius: Style.cornerRadius
  color: Commons.Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
  transform: Scale {
    origin.x: root.width / 2
    origin.y: root.height / 2
    xScale: root.cardXScale
    yScale: root.cardYScale
  }
  Component.onCompleted: root.syncCardGeometry()

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

    if (!root.geometryAnimationsReady || Style.reduceMotion) {
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
}
