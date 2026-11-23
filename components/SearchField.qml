import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: root
  property alias text: query.text
  property bool searching: false
  property bool showHelp: false
  property bool showSettings: false
  signal settingsRequested()
  signal helpRequested()

  Text {
    anchors.left: parent.left
    anchors.right: controls.left
    anchors.verticalCenter: parent.verticalCenter
    verticalAlignment: Text.AlignVCenter
    text: query.text ? "Filter: " + query.text + (root.searching ? " · searching contents…" : "") : "Switch window…"
    textFormat: Text.PlainText
    color: Commons.Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.title
    elide: Text.ElideRight
  }
  Text { id: query; visible: false }
  Row {
    id: controls
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)
    Repeater {
      model: (root.showSettings ? [{ label: "Settings", glyph: "⚙" }] : []).concat(root.showHelp ? [{ label: "Shortcuts", glyph: "?" }] : [])
      delegate: Rectangle {
        required property var modelData
        width: Style.space(32)
        height: width
        radius: Style.cornerRadius
        color: mouse.containsMouse ? Commons.Color.menu.selectedBackground : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label
        Accessible.onPressAction: activate()
        function activate() {
          if (modelData.label === "Settings") root.settingsRequested()
          else root.helpRequested()
        }
        Text {
          anchors.centerIn: parent
          text: parent.modelData.glyph
          color: mouse.containsMouse ? Commons.Color.menu.selectedText : Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
        }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.activate() }
      }
    }
  }
}
