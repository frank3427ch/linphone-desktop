import QtQuick
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Right-edge strip of the single view: opens / closes the docked call history card.
// Closed: vertical "HISTORY" label plus a red badge with the missed calls not yet seen.
// Open: vertical "HIDE" label.
// No layout here on purpose: a rotated Text inside a ColumnLayout polish-loops (the layout
// measures the unrotated box), so the label and badge are placed by hand.
Rectangle {
	id: strip
	property bool open: false
	property int missedCount: 0
	signal toggled()

	implicitWidth: Utils.getSizeWithScreenRatio(22)
	color: strip.open ? DefaultStyle.main2_600 : DefaultStyle.main1_500_main

	Text {
		id: label
		//: "HIDE" (vertical label on the history strip, panel open)
		//: "HISTORY" (vertical label on the history strip, panel closed)
		text: strip.open ? qsTr("singleview_history_strip_hide") : qsTr("singleview_history_strip_show")
		font: Typography.p4
		color: DefaultStyle.grey_0
		anchors.centerIn: parent
		rotation: 90   // rotates about the centre; visual height == implicitWidth
	}
	Rectangle {
		id: badge
		visible: !strip.open && strip.missedCount > 0
		anchors.horizontalCenter: parent.horizontalCenter
		// sit just above the rotated label's visual top
		y: parent.height / 2 - label.implicitWidth / 2 - height - Utils.getSizeWithScreenRatio(8)
		width: Math.max(height, badgeText.implicitWidth + Utils.getSizeWithScreenRatio(6))
		height: Utils.getSizeWithScreenRatio(16)
		radius: height / 2
		color: DefaultStyle.danger_500_main
		Text {
			id: badgeText
			anchors.centerIn: parent
			text: strip.missedCount > 99 ? "99+" : strip.missedCount
			font: Typography.p4
			color: DefaultStyle.grey_0
		}
	}
	MouseArea {
		anchors.fill: parent
		cursorShape: Qt.PointingHandCursor
		onClicked: strip.toggled()
	}
	Accessible.role: Accessible.Button
	//: "Show call history" / "Hide call history"
	Accessible.name: strip.open ? qsTr("singleview_history_hide_accessible") : qsTr("singleview_history_show_accessible")
}
