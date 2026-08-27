import QtQuick
import QtQuick.Layouts
import Linphone
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Conference card (spec §5.3): participant list + per-participant remove + End conference.
Rectangle {
	id: card
	property CallGui call

	implicitHeight: confContent.implicitHeight + Utils.getSizeWithScreenRatio(20)
	radius: Utils.getSizeWithScreenRatio(8)
	color: DefaultStyle.grey_0
	border.width: 2
	border.color: DefaultStyle.main1_500_main

	ColumnLayout {
		id: confContent
		anchors.fill: parent
		anchors.margins: Utils.getSizeWithScreenRatio(10)
		spacing: Utils.getSizeWithScreenRatio(8)

		RowLayout {
			Layout.fillWidth: true
			Text {
				Layout.fillWidth: true
				//: "Conference"
				text: qsTr("singleview_conference_title")
				font: Typography.p1s
				color: DefaultStyle.main2_600
			}
			// Local mic mute for the whole conference (the per-call cards, which carry
			// the per-leg mute, are hidden while their leg is in a conference).
			SmallButton {
				icon.source: card.call && card.call.core.microphoneMuted ? AppIcons.microphoneSlash : AppIcons.microphone
				icon.width: Utils.getSizeWithScreenRatio(16)
				icon.height: Utils.getSizeWithScreenRatio(16)
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
				style: ButtonStyle.secondary
				//: "Mute"
				Accessible.name: qsTr("singleview_mute")
				onClicked: card.call.core.lSetMicrophoneMuted(!card.call.core.microphoneMuted)
			}
			SmallButton {
				//: "End conference"
				text: qsTr("singleview_end_conference")
				Accessible.name: qsTr("singleview_end_conference")
				style: ButtonStyle.phoneRed
				// Ends all legs (FR-7). ConferenceCore has no terminate signal; this is the supported path.
				onClicked: card.call.core.lTerminateAllCalls()
			}
		}

		Repeater {
			model: ParticipantProxy {
				id: participants
				currentCall: card.call
				showMe: false
			}
			RowLayout {
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(8)
				Text {
					Layout.fillWidth: true
					text: modelData.core.displayName
					font: Typography.p2
					color: DefaultStyle.main2_600
					elide: Text.ElideRight
				}
				SmallButton {
					icon.source: AppIcons.closeX
					style: ButtonStyle.secondary
					//: "Remove participant"
					Accessible.name: qsTr("singleview_remove_participant")
					onClicked: participants.removeParticipant(modelData.core)
				}
			}
		}
	}
}
