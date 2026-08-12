import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

// The application's single view (spec §5): header / call stack / merge bar / dialer / footer.
Item {
	id: mainPanel

	AccountProxy { id: accounts }
	readonly property AccountGui account: accounts.defaultAccount
	readonly property int regState: account ? account.core.registrationState : LinphoneEnums.RegistrationState.None

	CallProxy { id: callsModel; sourceModel: AppCpp.calls }
	readonly property CallGui currentCall: callsModel.currentCall
	readonly property bool haveConference: currentCall && !!currentCall.core.conference
	property alias dialedText: dialerArea.enteredText

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
			spacing: Utils.getSizeWithScreenRatio(10)
			clip: true
			model: callsModel
			delegate: CallCard {
				width: callStack.width
				call: modelData
				// A leg merged into the conference is represented by the ConferenceCard instead
				visible: !modelData.core.conference
				height: visible ? implicitHeight : 0
				isCurrent: mainPanel.currentCall && modelData.core === mainPanel.currentCall.core
				transferTarget: mainPanel.dialedText
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

		// REGION 3: merge bar → conference card once merged (spec §5.3)
		MediumButton {
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(8)
			visible: callsModel.count >= 2 && !mainPanel.haveConference
			icon.source: AppIcons.arrowsMerge
			//: "Merge calls into conference"
			text: qsTr("singleview_merge_calls")
			style: ButtonStyle.main
			onClicked: callsModel.lMergeAll()
		}
		ConferenceCard {
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(8)
			visible: mainPanel.haveConference
			call: mainPanel.currentCall
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
			MultimediaSettings {
				Layout.fillWidth: true
				ringerDevicesVisible: true
				call: mainPanel.currentCall   // live-apply while in call; combos persist via SettingsCpp
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
