import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
  property bool cycleMode: false
  property bool settingsOpen: false
  visible: !cycleMode && !settingsOpen && text !== ""
  color: Commons.Color.menu.text
  font.family: Style.font.menuFamily
  font.pixelSize: Style.font.caption
  elide: Text.ElideRight
}
