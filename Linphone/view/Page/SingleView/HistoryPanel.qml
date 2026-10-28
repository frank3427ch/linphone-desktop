import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Page/SingleView/historyHelper.js" as History

// Docked call history card (right of the single view): every call, newest first, missed in
// red, one-tap call back. Row classification lives in historyHelper.js (unit-tested).
Rectangle {
	id: panel
	property var model          // CallHistoryProxy owned by MainPanel (lives while the card is hidden)
	property int missedCount: 0 // missed calls since the card was last opened

	color: DefaultStyle.grey_100

	function kindLabel(kind) {
		//: "Missed"
		if (kind === "missed") return qsTr("singleview_history_kind_missed")
		//: "Incoming"
		if (kind === "incoming") return qsTr("singleview_history_kind_incoming")
		//: "Outgoing"
		if (kind === "outgoing") return qsTr("singleview_history_kind_outgoing")
		//: "Declined"
		if (kind === "declined") return qsTr("singleview_history_kind_declined")
		//: "No answer"
		return qsTr("singleview_history_kind_unanswered")
	}

	ColumnLayout {
		anchors.fill: parent
		anchors.margins: Utils.getSizeWithScreenRatio(10)
		spacing: Utils.getSizeWithScreenRatio(8)

		RowLayout {
			Layout.fillWidth: true
			spacing: Utils.getSizeWithScreenRatio(8)
			Text {
				Layout.fillWidth: true
				//: "Call history"
				text: qsTr("singleview_history_title")
				font: Typography.h4
				color: DefaultStyle.main2_600
				elide: Text.ElideRight
			}
			Rectangle {
				visible: panel.missedCount > 0
				implicitWidth: missedText.implicitWidth + Utils.getSizeWithScreenRatio(12)
				implicitHeight: Utils.getSizeWithScreenRatio(20)
				radius: height / 2
				color: DefaultStyle.danger_500_main
				Text {
					id: missedText
					anchors.centerIn: parent
					//: "%1 missed"
					text: qsTr("singleview_history_missed_count").arg(panel.missedCount)
					font: Typography.p4
					color: DefaultStyle.grey_0
				}
			}
		}

		ListView {
			id: list
			Layout.fillWidth: true
			Layout.fillHeight: true
			clip: true
			spacing: Utils.getSizeWithScreenRatio(5)
			model: panel.model
			delegate: Rectangle {
				id: row
				width: list.width
				readonly property var entry: modelData.core
				readonly property string kind: History.classify(entry.status, entry.isOutgoing, LinphoneEnums.CallStatus)
				readonly property bool missed: History.isMissed(kind)
				implicitHeight: rowContent.implicitHeight + Utils.getSizeWithScreenRatio(14)
				radius: Utils.getSizeWithScreenRatio(8)
				color: missed ? Qt.alpha(DefaultStyle.danger_500_main, 0.10) : DefaultStyle.grey_0
				border.width: 1
				border.color: missed ? Qt.alpha(DefaultStyle.danger_500_main, 0.5) : DefaultStyle.grey_200

				RowLayout {
					id: rowContent
					anchors.fill: parent
					anchors.margins: Utils.getSizeWithScreenRatio(7)
					spacing: Utils.getSizeWithScreenRatio(6)
					EffectImage {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(16)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(16)
						imageWidth: Utils.getSizeWithScreenRatio(16)
						imageHeight: Utils.getSizeWithScreenRatio(16)
						imageSource: row.kind === "outgoing" || row.kind === "unanswered" ? AppIcons.arrowUpRight
									 : row.kind === "declined" ? AppIcons.arrowElbow : AppIcons.arrowDownLeft
						colorizationColor: row.missed || row.kind === "declined" || row.kind === "unanswered"
										   ? DefaultStyle.danger_500_main
										   : row.kind === "outgoing" ? DefaultStyle.info_500_main : DefaultStyle.success_500_main
					}
					ColumnLayout {
						Layout.fillWidth: true
						spacing: Utils.getSizeWithScreenRatio(1)
						Text {
							Layout.fillWidth: true
							text: row.entry.displayName.length > 0 ? row.entry.displayName : row.entry.remoteAddress
							font: Typography.p1s
							color: row.missed ? DefaultStyle.danger_700 : DefaultStyle.main2_600
							elide: Text.ElideRight
						}
						Text {
							Layout.fillWidth: true
							text: History.subtitle([panel.kindLabel(row.kind),
													UtilsCpp.formatDate(row.entry.date, true, false),
													History.durationLabel(row.kind, row.entry.duration, function(sec) { return UtilsCpp.formatElapsedTime(sec) })])
							font: Typography.p3
							color: DefaultStyle.main2_400
							elide: Text.ElideRight
						}
					}
					SmallButton {
						icon.source: AppIcons.phone
						style: ButtonStyle.phoneGreen
						//: "Call %1 back"
						Accessible.name: qsTr("singleview_history_call_back_accessible").arg(row.entry.displayName)
						onClicked: UtilsCpp.createCall(row.entry.remoteAddress)
					}
				}
			}
			Text {
				anchors.centerIn: parent
				visible: list.count === 0
				//: "No calls yet"
				text: qsTr("singleview_history_empty")
				font: Typography.p1
				color: DefaultStyle.grey_400
			}
		}
	}
}
