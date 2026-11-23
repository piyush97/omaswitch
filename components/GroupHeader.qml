import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
  textFormat: Text.PlainText
  color: Commons.Color.menu.text
  font.family: Style.font.menuFamily
  font.pixelSize: Style.font.caption
  font.bold: true
  verticalAlignment: Text.AlignVCenter
  elide: Text.ElideRight
}
