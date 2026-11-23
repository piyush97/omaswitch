import QtQuick
import qs.Commons

Item {
  id: root
  property alias text: query.text
  property bool searching: false
  signal settingsRequested()
  signal helpRequested()

  Text {
    anchors.fill: parent
    verticalAlignment: Text.AlignVCenter
    text: query.text ? "Filter: " + query.text + (root.searching ? " · searching contents…" : "") : "Switch window…"
    textFormat: Text.PlainText
    color: Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.title
    elide: Text.ElideRight
  }
  Text { id: query; visible: false }
}
