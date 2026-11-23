import QtQuick
import qs.Commons

Text {
  property bool cycleMode: false
  property bool settingsOpen: false
  visible: !cycleMode && !settingsOpen && text !== ""
  color: Color.menu.text
  font.family: Style.font.menuFamily
  font.pixelSize: Style.font.caption
  elide: Text.ElideRight
}
