import QtQuick
import QtQuick.Layouts
import Linphone
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Conference card (spec §5.3): participant list + per-participant remove + End conference.
Rectangle {
	id: card
	property CallGui call
	// The call list (CallProxy) so each participant row can find its own leg and show
	// its state — a leg can be merged while still ringing (spec §5.3).
	property var calls: null
	readonly property int callCount: calls ? calls.count : 0
	// Address typed in the dialer; target of the per-participant Transfer button
	property string transferTarget: ""

	function legFor(sipAddress) {
		if (!calls || !sipAddress) return null
		var user = sipAddress.split(":")[1]
		user = user ? user.split("@")[0] : ""
		for (var i = 0; i < calls.count; ++i) {
			var gui = calls.getAt(i)
			if (!gui || !gui.core) continue
			var remote = gui.core.remoteAddress
			if (remote === sipAddress) return gui
			// Fall back to a username match: uri params may differ between the two addresses
			var remoteUser = remote.split(":")[1]
			remoteUser = remoteUser ? remoteUser.split("@")[0] : ""
			if (user.length > 0 && remoteUser === user) return gui
		}
		return null
	}
	function isRinging(state) {
		return state === LinphoneEnums.CallState.OutgoingInit
			|| state === LinphoneEnums.CallState.OutgoingProgress
			|| state === LinphoneEnums.CallState.OutgoingRinging
			|| state === LinphoneEnums.CallState.OutgoingEarlyMedia
	}

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
				id: row
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(8)
				// Re-evaluated whenever the call list changes (callCount) so a leg that
				// answers, ends, or is added is picked up.
				readonly property var leg: card.callCount >= 0 ? card.legFor(modelData.core.sipAddress) : null
				readonly property bool ringing: !!(leg && leg.core && card.isRinging(leg.core.state))
				Text {
					Layout.fillWidth: true
					text: modelData.core.displayName
					font: Typography.p2
					color: DefaultStyle.main2_600
					elide: Text.ElideRight
				}
				Text {
					visible: row.ringing
					//: "Ringing…"
					text: qsTr("singleview_participant_ringing")
					font: Typography.p2
					color: DefaultStyle.main2_400
				}
				// Blind transfer of this leg to the address typed in the dialer (spec FR-8);
				// the leg leaves the conference, the rest of the call continues.
				SmallButton {
					visible: !!row.leg
					enabled: card.transferTarget.length > 0 && !row.ringing
					icon.source: AppIcons.transferCall
					icon.width: Utils.getSizeWithScreenRatio(16)
					icon.height: Utils.getSizeWithScreenRatio(16)
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
					style: ButtonStyle.secondary
					//: "Transfer to the entered address"
					Accessible.name: qsTr("singleview_transfer")
					onClicked: row.leg.core.lTransferCall(card.transferTarget)
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
