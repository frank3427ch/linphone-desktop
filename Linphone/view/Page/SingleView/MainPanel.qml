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
	property string dialedText: ""   // becomes `property alias dialedText: dialerArea.enteredText` in Task 4

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

		// REGION 2: call stack (Task 3)
		Item {
			Layout.fillWidth: true
			Layout.fillHeight: true
			Text {
				anchors.centerIn: parent
				//: "No active calls"
				text: qsTr("singleview_no_active_calls")
				font: Typography.p1
				color: DefaultStyle.grey_400
			}
		}

		// REGION 3: merge bar / conference card (Task 5)

		// REGION 4: dialer (Task 4)

		// REGION 5: footer (Task 7)
	}
}
