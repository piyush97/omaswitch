import QtQuick
import qs.Commons
import "../Model.js" as Model

Item {
  id: root
  required property var row
  property bool selected: false
  property url icon
  signal activated()
  readonly property color foreground: selected ? Color.menu.selectedText : Color.menu.text

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.selected ? Color.menu.selectedBackground : "transparent"
  }
  Row {
    anchors.verticalCenter: parent.verticalCenter
    x: Style.space(10)
    width: Math.max(0, parent.width - x * 2)
    spacing: Style.space(8)
    Image {
      id: appIcon
      width: Style.space(30)
      height: width
      anchors.verticalCenter: parent.verticalCenter
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: root.icon
      asynchronous: true
    }
    Column {
      width: Math.max(0, parent.width - appIcon.width - parent.spacing)
      Text {
        width: parent.width
        text: Model.label(root.row)
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: Model.detail(root.row)
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
  MouseArea { anchors.fill: parent; onClicked: root.activated() }
}
