import QtQuick
import QtQuick.Controls
import qs.Commons
import "../Settings.js" as Settings
import "../Bindings.js" as Bindings

ScrollView {
  id: root
  required property var values
  property var bindingState: null
  property bool ready: false
  property bool bindingsLoaded: false
  property bool bindingsBusy: false
  property string bindingsError: ""
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
    Text {
      text: "Alt+Tab bindings"
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
    Text {
      width: parent.width
      visible: root.bindingsError !== "" || (root.bindingsLoaded && root.bindingState === null)
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: root.bindingsError || "Add the bindings from the README to ~/.config/hypr/bindings.lua."
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
    Button {
      visible: root.bindingState !== null && !root.bindingState.managed && !root.bindingState.handWritten
      enabled: !root.bindingsBusy
      text: root.bindingsBusy ? "Checking bindings…" : "Set up Alt+Tab"
      onClicked: root.setupRequested()
    }
    Button {
      visible: !!root.bindingState?.managed
      enabled: !root.bindingsBusy
      text: root.bindingsBusy ? "Checking bindings…" : "Remove OmaSwitch bindings"
      onClicked: root.removeRequested()
    }
    Button {
      visible: root.bindingsError !== "" || (root.bindingsLoaded && root.bindingState === null)
      text: "Manual setup steps"
      onClicked: Qt.openUrlExternally("https://github.com/piyush97/omaswitch#setup")
    }
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: !!root.bindingState?.handWritten && !root.bindingState.hasAppScope
      Text {
        text: "Add this line for same-app cycling:"
        color: Color.menu.text
      }
      TextEdit {
        id: appBinding
        width: parent.width
        wrapMode: TextEdit.WrapAnywhere
        readOnly: true
        selectByMouse: true
        color: Color.menu.text
        text: Bindings.appScopeLine()
      }
      Button {
        text: "Copy"
        onClicked: { appBinding.selectAll(); appBinding.copy(); appBinding.deselect() }
      }
    }
  }
}
