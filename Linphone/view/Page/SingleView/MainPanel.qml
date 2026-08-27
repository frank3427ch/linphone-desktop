import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

// The application's single view (spec §5): header / call stack / merge bar / dialer / footer.
Item {
	id: mainPanel

	// Physical keyboard always composes into the dialer, wherever focus sits;
	// the on-screen pad keeps its DTMF-when-connected modality.
	Keys.onPressed: (event) => {
		if (event.text.length === 1 && "0123456789*#+".indexOf(event.text) !== -1) {
			dialerArea.enteredText += event.text
			dialerArea.focusInput()
			event.accepted = true
		} else if (event.key === Qt.Key_Backspace) {
			dialerArea.enteredText = dialerArea.enteredText.slice(0, -1)
			dialerArea.focusInput()
			event.accepted = true
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			dialerArea.launchCall()
			event.accepted = true
		}
	}

	AccountProxy { id: accounts }
	readonly property AccountGui account: accounts.defaultAccount
	readonly property int regState: account ? account.core.registrationState : LinphoneEnums.RegistrationState.None

	CallProxy { id: callsModel; sourceModel: AppCpp.calls }
	readonly property CallGui currentCall: callsModel.currentCall
	// Tracks which call (any leg) carries the active conference — independent of currentCall,
	// so the ConferenceCard stays visible even if a non-conference call becomes current (spec §5.3).
	property CallGui conferenceCall: null
	readonly property bool haveConference: conferenceCall !== null
	property alias dialedText: dialerArea.enteredText

	// Re-derive the tracked conference leg from the live rows. CallList repopulates via
	// model resets, so per-delegate bookkeeping goes stale (a destroyed delegate can't
	// reliably clear the reference) — a full sweep is the only robust source of truth.
	function retrackConference() {
		for (var i = 0; i < callsModel.count; ++i) {
			var gui = callsModel.getAt(i)
			if (gui && gui.core && gui.core.conference) {
				if (!conferenceCall || conferenceCall.core !== gui.core) conferenceCall = gui
				return
			}
		}
		conferenceCall = null
	}
	Connections {
		target: callsModel
		function onCountChanged() { mainPanel.retrackConference() }
	}
	// Change-detector per row: fires the sweep when a leg enters/leaves a conference
	Repeater {
		model: callsModel
		delegate: Item {
			visible: false
			readonly property bool inConference: !!(modelData && modelData.core && modelData.core.conference)
			onInConferenceChanged: mainPanel.retrackConference()
			Component.onCompleted: mainPanel.retrackConference()
			Component.onDestruction: Qt.callLater(mainPanel.retrackConference)
		}
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// REGION 1: header / status strip
		Rectangle {
			Layout.fillWidth: true
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(44)
			color: DefaultStyle.grey_0
			RowLayout {
				anchors.fill: parent
				anchors.leftMargin: Utils.getSizeWithScreenRatio(16)
				anchors.rightMargin: Utils.getSizeWithScreenRatio(16)
				spacing: Utils.getSizeWithScreenRatio(8)
				Rectangle {
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(9)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(9)
					radius: width / 2
					color: mainPanel.regState === LinphoneEnums.RegistrationState.Ok
						   ? DefaultStyle.account_status_green
						   : (mainPanel.regState === LinphoneEnums.RegistrationState.Progress
							  || mainPanel.regState === LinphoneEnums.RegistrationState.Refreshing)
							 ? DefaultStyle.account_status_yellow
							 : mainPanel.regState === LinphoneEnums.RegistrationState.Failed
							   ? DefaultStyle.account_status_red
							   : DefaultStyle.account_status_grey
				}
				Text {
					Layout.fillWidth: true
					text: mainPanel.account ? mainPanel.account.core.identityAddress
											//: "No account provisioned"
											: qsTr("singleview_no_account")
					font: Typography.p1
					color: DefaultStyle.main2_600
					elide: Text.ElideRight
				}
				Text {
					text: mainPanel.account ? mainPanel.account.core.humaneReadableRegistrationState : ""
					font: Typography.p3
					color: DefaultStyle.main2_400
				}
				SmallButton {
					visible: mainPanel.regState === LinphoneEnums.RegistrationState.Failed
					//: "Retry"
					text: qsTr("singleview_retry_register")
					style: ButtonStyle.secondary
					onClicked: mainPanel.account.core.lSetRegisterEnabled(true)
				}
			}
			Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: DefaultStyle.grey_200 }
		}

		// REGION 2: call stack
		ListView {
			id: callStack
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.margins: Utils.getSizeWithScreenRatio(12)
			spacing: 0
			clip: true
			model: callsModel
			delegate: Item {
				width: callStack.width
				height: card.visible ? card.implicitHeight + Utils.getSizeWithScreenRatio(10) : 0
				CallCard {
					id: card
					width: parent.width
					call: modelData
					// A leg merged into the conference is represented by the ConferenceCard instead
					visible: !modelData.core.conference
					isCurrent: !!(mainPanel.currentCall && modelData.core === mainPanel.currentCall.core)
					transferTarget: mainPanel.dialedText
				}
			}
			Text {
				anchors.centerIn: parent
				visible: callsModel.count === 0
				//: "No active calls"
				text: qsTr("singleview_no_active_calls")
				font: Typography.p1
				color: DefaultStyle.grey_400
			}
		}

		// REGION 3: merge bar → conference card once merged (spec §5.3); end-all beside it
		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(8)
			visible: callsModel.count > 0
			spacing: Utils.getSizeWithScreenRatio(8)
			MediumButton {
				Layout.fillWidth: true
				visible: callsModel.count >= 2 && !mainPanel.haveConference
				icon.source: AppIcons.arrowsMerge
				//: "Merge calls into conference"
				text: qsTr("singleview_merge_calls")
				style: ButtonStyle.main
				onClicked: callsModel.lMergeAll()
			}
			MediumButton {
				Layout.fillWidth: true
				style: ButtonStyle.phoneRed
				//: "End all calls"
				text: qsTr("singleview_end_all_calls")
				onClicked: {
					var gui = mainPanel.conferenceCall || callsModel.getAt(0)
					if (gui && gui.core) gui.core.lTerminateAllCalls()
				}
			}
		}
		ConferenceCard {
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(8)
			visible: mainPanel.haveConference
			call: mainPanel.conferenceCall
			calls: callsModel
		}

		// REGION 4: dialer
		Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: DefaultStyle.grey_200 }
		DialerArea {
			id: dialerArea
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(16)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(16)
			Layout.topMargin: Utils.getSizeWithScreenRatio(6)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(12)
			currentCall: mainPanel.currentCall
		}

		// REGION 5: footer — current output device, opens the device picker (the app's only modal)
		Rectangle {
			Layout.fillWidth: true
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(40)
			color: DefaultStyle.grey_100
			Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: DefaultStyle.grey_200 }
			RowLayout {
				anchors.fill: parent
				anchors.leftMargin: Utils.getSizeWithScreenRatio(16)
				anchors.rightMargin: Utils.getSizeWithScreenRatio(16)
				spacing: Utils.getSizeWithScreenRatio(6)
				EffectImage {
					imageSource: AppIcons.speaker
					colorizationColor: DefaultStyle.main2_400
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(15)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(15)
					imageWidth: Utils.getSizeWithScreenRatio(15)
					imageHeight: Utils.getSizeWithScreenRatio(15)
				}
				Text {
					Layout.fillWidth: true
					text: SettingsCpp.playbackDevice["display_name"] ?? ""
					font: Typography.p3
					color: DefaultStyle.main2_400
					elide: Text.ElideRight
				}
				SmallButton {
					icon.source: AppIcons.settings
					style: ButtonStyle.noBackground
					//: "Audio devices"
					Accessible.name: qsTr("singleview_audio_devices")
					onClicked: devicePicker.open()
				}
			}
		}
	}

	Control.Popup {
		id: devicePicker
		modal: true
		anchors.centerIn: parent
		width: mainPanel.width - Utils.getSizeWithScreenRatio(40)
		padding: Utils.getSizeWithScreenRatio(16)
		contentItem: ColumnLayout {
			spacing: Utils.getSizeWithScreenRatio(10)
			Text {
				//: "Audio devices"
				text: qsTr("singleview_audio_devices")
				font: Typography.h4
				color: DefaultStyle.main2_600
			}
			Flickable {
				Layout.fillWidth: true
				Layout.preferredHeight: Math.min(multimediaSettings.implicitHeight, mainPanel.height - Utils.getSizeWithScreenRatio(200))
				contentHeight: multimediaSettings.implicitHeight
				clip: true
				MultimediaSettings {
					id: multimediaSettings
					width: parent.width
					ringerDevicesVisible: true
					call: mainPanel.currentCall   // live-apply while in call; combos persist via SettingsCpp
					backgroundVisible: false
				}
			}
			MediumButton {
				Layout.alignment: Qt.AlignHCenter
				//: "Close"
				text: qsTr("singleview_close")
				style: ButtonStyle.secondary
				onClicked: devicePicker.close()
			}
		}
		background: Rectangle {
			radius: Utils.getSizeWithScreenRatio(10)
			color: DefaultStyle.grey_0
			border.color: DefaultStyle.grey_200
		}
	}
}
