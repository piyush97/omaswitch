import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Column {
  id: root
  property bool missing: false
  property bool busy: false
  property string error: ""
  signal setupRequested()
  signal dismissed()
  spacing: Style.space(4)

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: root.error || (root.missing ? "Add the bindings from the README to ~/.config/hypr/bindings.lua." : "Alt+Tab still opens Omarchy's switcher.")
    color: Commons.Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }
  Flow {
    width: parent.width
    spacing: Style.space(4)
    Ui.Button {
      bordered: true
      visible: !root.missing
      enabled: !root.busy
      text: root.busy ? "Checking bindings…" : "Use OmaSwitch for Alt+Tab"
      onClicked: root.setupRequested()
    }
    Ui.Button {
      bordered: true
      visible: root.missing || root.error !== ""
      text: "Manual setup steps"
      onClicked: Qt.openUrlExternally("https://github.com/piyush97/omaswitch#setup")
    }
    Ui.Button {
      bordered: true
      text: "Not now"
      enabled: !root.busy
      onClicked: root.dismissed()
    }
  }
}
