import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "io.github.dtpietrzak.right-side-bar-spacing"

  readonly property color barForeground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property real thin: 1 / Math.max(1, Screen.devicePixelRatio)
  readonly property int beforeGap: setting("before", Math.round(setting("gap", Style.space(6)) / 2))
  readonly property int afterGap: setting("after", Math.round(setting("gap", Style.space(6)) / 2))

  // A divider can give either side more room without shifting the other.
  implicitWidth: vertical ? barSize : beforeGap + afterGap
  implicitHeight: vertical ? beforeGap + afterGap : barSize

  Rectangle {
    width: root.vertical ? Style.space(12) : root.thin
    height: root.vertical ? root.thin : Style.space(12)
    x: root.vertical ? (root.width - width) / 2 : root.beforeGap
    y: root.vertical ? root.beforeGap : (root.height - height) / 2
    color: Qt.alpha(root.barForeground, 0.3)
  }
}
