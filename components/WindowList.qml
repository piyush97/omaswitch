import QtQuick
import qs.Commons
import "../Model.js" as Model

ListView {
  id: root
  property var rows: []
  property var closingAddresses: ({})
  property int selectedIndex: -1
  property int rowHeight: 48
  property var iconSource
  property var snippetFor
  property string query
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

  delegate: Loader {
    id: entry
    required property var modelData
    required property int index
    width: root.width
    sourceComponent: modelData.kind === "header" ? header : windowRow
    Component {
      id: header
      GroupHeader { height: Style.space(26); text: entry.modelData.label }
    }
    Component {
      id: windowRow
      WindowRow {
        row: entry.modelData.window
        jump: entry.modelData.jump
        selected: entry.index === root.selectedIndex
        icon: root.iconSource(row)
        snippet: root.snippetFor(row)
        query: root.query
        closing: !!root.closingAddresses[Model.closeTarget(row)]
        height: root.rowHeight + (snippet ? Style.space(20) : 0)
        onActivated: root.activated(entry.index)
      }
    }
  }
}
