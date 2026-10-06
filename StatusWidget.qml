import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Bar badge for borgmatic. It reads the user timer and whether borgmatic
// is already running. Click opens the config file. It does not start a backup.
BarWidget {
  id: root
  moduleName: "calledtoconstruct.backup-status"

  property string label: "bak"
  property string state: ""
  property string configPath: ""
  property string next: ""
  property string nextIn: ""
  property string lastResult: ""
  property string lastExit: ""
  property bool configured: false
  property bool running: false
  property string statusError: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function scriptPath() {
    var url = Qt.resolvedUrl("status.sh").toString()
    if (url.indexOf("file://") === 0)
      url = decodeURIComponent(url.substring(7))
    return url
  }

  function refresh() {
    if (statusProc.running)
      return
    statusProc.command = [scriptPath()]
    statusProc.running = true
  }

  function applyStatus(text) {
    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (error) {
      statusError = "status was not JSON"
      return
    }
    label = parsed.label || "?"
    state = parsed.state || ""
    configPath = parsed.configPath || ""
    next = parsed.next || ""
    nextIn = parsed.nextIn || ""
    lastResult = parsed.lastResult || ""
    lastExit = parsed.lastExit || ""
    configured = parsed.configured === true
    running = parsed.running === true
    statusError = ""
  }

  function tooltip() {
    if (statusError !== "")
      return "Backup: " + statusError
    var lines = []
    if (running)
      lines.push("Backup in progress")
    else if (state === "unconfigured")
      lines.push("No borgmatic config in ~/.config/borgmatic")
    else if (state === "unscheduled")
      lines.push("Timer omarchy-backup.timer is not running")
    else if (state === "failed")
      lines.push("Last backup failed")
    else if (state === "due")
      lines.push("Backup is due")
    else if (nextIn !== "")
      lines.push("Next backup in " + nextIn)
    if (next !== "")
      lines.push(next)
    if (lastExit !== "")
      lines.push("Last exit " + lastExit)
    if (configPath !== "")
      lines.push("Click opens the config")
    return lines.join("\n")
  }

  function openConfig() {
    if (configPath === "")
      return
    openProc.command = ["xdg-open", configPath]
    openProc.running = true
  }

  function open() { refresh() }
  function close() {}
  function toggle() { openConfig() }

  Component.onCompleted: refresh()

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: function (exitCode) {
      if (exitCode === 0)
        root.applyStatus(String(statusOut.text || ""))
      else
        root.statusError = "status script failed"
    }
  }

  Process {
    id: openProc
  }

  WidgetButton {
    id: button
    bar: root.bar
    text: root.label
    active: root.running
    dimmed: !root.running && (root.state === "" || root.state === "unconfigured" || root.state === "unscheduled" || root.state === "failed" || root.state === "unknown")
    tooltipText: root.tooltip()
    onPressed: root.openConfig()
  }
}
