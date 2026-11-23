import QtQuick
import qs.Commons
import "../Model.js" as Model

Item {
  id: root
  required property var row
  property bool selected: false
  property url icon
  property var jump: null
  property var snippet: null
  property string query

  function escapeText(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function marked(parts, fallback) {
    if (!parts) return escapeText(fallback)
    return escapeText(parts.before) + "<b><u>" + escapeText(parts.match) + "</u></b>" + escapeText(parts.after)
  }
  signal activated()
  readonly property color foreground: selected ? Color.menu.selectedText : Color.menu.text

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.selected ? Color.menu.selectedBackground : "transparent"
  }
  Rectangle {
    visible: root.selected
    width: Style.space(3)
    height: parent.height - Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    radius: width / 2
    color: root.foreground
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
      width: Math.max(0, parent.width - appIcon.width - jumpNumber.width - parent.spacing * 2)
      Text {
        width: parent.width
        text: root.marked(Model.titleMatch(root.row, root.query), Model.label(root.row))
        textFormat: Text.StyledText
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
      Text {
        visible: root.snippet !== null
        width: parent.width
        text: root.marked(root.snippet, "")
        textFormat: Text.StyledText
        elide: Text.ElideRight
        color: root.foreground
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      id: jumpNumber
      visible: root.jump !== null
      width: visible ? Style.space(20) : 0
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: visible ? String(root.jump) : ""
      color: root.foreground
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }
  MouseArea { anchors.fill: parent; onClicked: root.activated() }
}
