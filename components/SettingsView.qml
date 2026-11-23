import QtQuick
import QtQuick.Controls
import qs.Commons
import "../Settings.js" as Settings

ScrollView {
  id: root
  required property var values
  property var bindingState: null
  property bool ready: false
  signal changed(string key, var value)
  signal setupRequested()
  signal removeRequested()
  signal closed()

  contentWidth: availableWidth
  Keys.onEscapePressed: root.closed()
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Comma && event.modifiers === Qt.ControlModifier) {
      root.closed()
      event.accepted = true
    }
  }

  function focusFirst() { backButton.forceActiveFocus() }

  Column {
    width: root.availableWidth
    spacing: Style.space(8)

    Button {
      id: backButton
      text: "Back to windows"
      onClicked: root.closed()
    }
    Text {
      text: "OmaSwitch settings"
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.title
    }
    Column {
      spacing: Style.space(4)
      enabled: root.ready
      Text {
        text: "Window scope"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
      }
      ComboBox {
        Accessible.name: "Window scope"
        model: ["All workspaces", "Current workspace", "Current monitor"]
        currentIndex: Settings.scopes.indexOf(root.values.scope)
        onActivated: root.changed("scope", Settings.scopes[index])
      }
      Repeater {
        model: [
          { key: "groupByWorkspace", label: "Group by workspace" },
          { key: "livePreview", label: "Live preview" },
          { key: "contentSearch", label: "Search window contents" }
        ]
        delegate: CheckBox {
          required property var modelData
          text: modelData.label
          checked: root.values[modelData.key]
          onToggled: root.changed(modelData.key, checked)
        }
      }
    }
  }
}
