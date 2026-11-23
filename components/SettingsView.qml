import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
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

    Ui.Button {
      id: backButton
      text: "Back to windows"
      focusable: true
      bordered: true
      onClicked: root.closed()
    }
    Text {
      text: "OmaSwitch settings"
      color: Commons.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.title
    }
    Column {
      width: Math.min(parent.width, Style.space(360))
      spacing: Style.space(4)
      enabled: root.ready
      Ui.Dropdown {
        width: parent.width
        label: "Window scope"
        Accessible.name: "Window scope"
        value: root.values.scope
        options: [
          { value: "all", label: "All workspaces" },
          { value: "workspace", label: "Current workspace" },
          { value: "monitor", label: "Current monitor" }
        ]
        onChanged: function(value) { root.changed("scope", value) }
      }
      Repeater {
        model: [
          { key: "groupByWorkspace", label: "Group by workspace" },
          { key: "livePreview", label: "Live preview" },
          { key: "contentSearch", label: "Search window contents" }
        ]
        delegate: Ui.Toggle {
          required property var modelData
          width: parent.width
          label: modelData.label
          Accessible.name: modelData.label
          checked: !!root.values[modelData.key]
          onClicked: root.changed(modelData.key, !checked)
        }
      }
    }
    Text {
      text: "Alt+Tab bindings"
      color: Commons.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
    Text {
      width: parent.width
      visible: root.bindingsError !== "" || (root.bindingsLoaded && root.bindingState === null)
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: root.bindingsError || "Add the bindings from the README to ~/.config/hypr/bindings.lua."
      color: Commons.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
    Ui.Button {
      focusable: true
      bordered: true
      visible: root.bindingState !== null && !root.bindingState.managed && !root.bindingState.handWritten
      enabled: !root.bindingsBusy
      text: root.bindingsBusy ? "Checking bindings…" : "Set up Alt+Tab"
      onClicked: root.setupRequested()
    }
    Ui.Button {
      focusable: true
      bordered: true
      visible: !!root.bindingState?.managed
      enabled: !root.bindingsBusy
      text: root.bindingsBusy ? "Checking bindings…" : "Remove OmaSwitch bindings"
      onClicked: root.removeRequested()
    }
    Ui.Button {
      focusable: true
      bordered: true
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
        color: Commons.Color.menu.text
      }
      TextEdit {
        id: appBinding
        width: parent.width
        wrapMode: TextEdit.WrapAnywhere
        readOnly: true
        selectByMouse: true
        color: Commons.Color.menu.text
        text: Bindings.appScopeLine()
      }
      Ui.Button {
        focusable: true
        bordered: true
        text: "Copy"
        onClicked: { appBinding.selectAll(); appBinding.copy(); appBinding.deselect() }
      }
    }
  }
}
