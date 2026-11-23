import QtQuick
import qs.Commons

ListView {
  id: root
  property var rows: []
  property int selectedIndex: -1
  property int rowHeight: 48
  property var iconSource
  property var snippetFor
  property string emptyText
  signal activated(int index)
  signal hovered(int index)

  model: rows
  clip: true
  function reveal(index) { positionViewAtIndex(index, ListView.Contain) }

  Text {
    anchors.centerIn: parent
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    visible: root.count === 0
    text: root.emptyText
    textFormat: Text.PlainText
    color: Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }

  delegate: WindowRow {
    required property var modelData
    required property int index
    width: root.width
    height: root.rowHeight
    row: modelData
    selected: index === root.selectedIndex
    icon: root.iconSource(modelData)
    onActivated: root.activated(index)
  }
}
