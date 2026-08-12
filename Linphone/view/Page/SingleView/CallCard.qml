import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// One row in the call stack (spec §5.2). All state comes from CallCore — no local state.
Rectangle {
	id: card
	property CallGui call
	property bool isCurrent: false
	property string transferTarget: ""   // wired to the dialer field in Task 6

	readonly property int callState: call ? call.core.state : LinphoneEnums.CallState.Idle
	readonly property bool incoming: callState === LinphoneEnums.CallState.IncomingReceived
									 || callState === LinphoneEnums.CallState.IncomingEarlyMedia
	readonly property bool dialing: callState === LinphoneEnums.CallState.OutgoingInit
									|| callState === LinphoneEnums.CallState.OutgoingProgress
									|| callState === LinphoneEnums.CallState.OutgoingRinging
									|| callState === LinphoneEnums.CallState.OutgoingEarlyMedia
	readonly property bool held: call && call.core.paused
	readonly property bool heldByRemote: callState === LinphoneEnums.CallState.PausedByRemote
	readonly property bool connected: callState === LinphoneEnums.CallState.Connected
									  || callState === LinphoneEnums.CallState.StreamsRunning
									  || heldByRemote

	implicitHeight: content.implicitHeight + Utils.getSizeWithScreenRatio(20)
	radius: Utils.getSizeWithScreenRatio(8)
	color: DefaultStyle.grey_0
	border.width: isCurrent && !held ? 2 : 1
	border.color: isCurrent && !held ? DefaultStyle.main1_500_main : DefaultStyle.grey_200
	opacity: held ? 0.6 : 1.0

	function stateLabel() {
		//: "Incoming call"
		if (incoming) return qsTr("singleview_state_incoming")
		//: "Calling…"
		if (dialing) return qsTr("singleview_state_dialing")
		//: "On hold"
		if (held) return qsTr("singleview_state_on_hold")
		//: "Held by remote"
		if (heldByRemote) return qsTr("singleview_state_paused_by_remote")
		//: "Active"
		if (connected) return qsTr("singleview_state_active")
		return ""
	}

	RowLayout {
		id: content
		anchors.fill: parent
		anchors.margins: Utils.getSizeWithScreenRatio(10)
		spacing: Utils.getSizeWithScreenRatio(6)

		ColumnLayout {
			Layout.fillWidth: true
			spacing: Utils.getSizeWithScreenRatio(2)
			Text {
				Layout.fillWidth: true
				text: card.call ? (card.call.core.remoteName.length > 0 ? card.call.core.remoteName
																	   : card.call.core.remoteAddress) : ""
				font: Typography.p1s
				color: DefaultStyle.main2_600
				elide: Text.ElideRight
			}
			Text {
				text: (card.incoming || card.dialing ? "" : UtilsCpp.formatElapsedTime(card.call ? card.call.core.duration : 0) + " · ")
					  + card.stateLabel()
				font: Typography.p3
				color: card.held ? DefaultStyle.warning_700 : card.connected ? DefaultStyle.success_700 : DefaultStyle.main2_400
			}
		}

		// Incoming: Answer / Decline replace the normal controls (spec §5.2)
		SmallButton {
			visible: card.incoming
			icon.source: AppIcons.phone
			icon.width: Utils.getSizeWithScreenRatio(16)
			icon.height: Utils.getSizeWithScreenRatio(16)
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
			style: ButtonStyle.phoneGreen
			//: "Answer"
			Accessible.name: qsTr("singleview_answer")
			onClicked: card.call.core.lAccept(false)
		}
		SmallButton {
			visible: card.incoming
			icon.source: AppIcons.endCall
			icon.width: Utils.getSizeWithScreenRatio(16)
			icon.height: Utils.getSizeWithScreenRatio(16)
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
			style: ButtonStyle.phoneRed
			//: "Decline"
			Accessible.name: qsTr("singleview_decline")
			onClicked: card.call.core.lDecline()
		}

		// Normal controls
		SmallButton {
			visible: !card.incoming && (card.connected || card.held)
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
			visible: !card.incoming && (card.connected || card.held)
			icon.source: card.held ? AppIcons.play : AppIcons.pause
			icon.width: Utils.getSizeWithScreenRatio(16)
			icon.height: Utils.getSizeWithScreenRatio(16)
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
			style: ButtonStyle.secondary
			//: "Hold / Resume"
			Accessible.name: qsTr("singleview_hold_resume")
			onClicked: card.call.core.lSetPaused(!card.call.core.paused)
		}
		SmallButton {
			visible: !card.incoming
			icon.source: AppIcons.endCall
			icon.width: Utils.getSizeWithScreenRatio(16)
			icon.height: Utils.getSizeWithScreenRatio(16)
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
			style: ButtonStyle.phoneRed
			//: "Hang up"
			Accessible.name: qsTr("singleview_hangup")
			onClicked: card.call.core.lTerminate()
		}
	}
}
