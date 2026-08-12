import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Dialer region (spec §5.4): modal on call state — DTMF to the connected call, else compose.
ColumnLayout {
	id: dialerArea
	property CallGui currentCall
	property alias enteredText: destField.text
	// DTMF mode iff a call is focused, connected, and not held (spec §5.4, FR-5)
	readonly property bool dtmfMode: currentCall && !currentCall.core.paused
		&& (currentCall.core.state === LinphoneEnums.CallState.Connected
			|| currentCall.core.state === LinphoneEnums.CallState.StreamsRunning)
	spacing: Utils.getSizeWithScreenRatio(8)

	function launchCall() {
		if (destField.text.length === 0) return
		UtilsCpp.createCall(destField.text)
		destField.text = ""
	}
	function focusInput() { destField.forceActiveFocus() }

	// Provisioned speed dials ([ui] speed_dial_1..3 = Label|number); hidden when none configured
	RowLayout {
		visible: SettingsCpp.speedDials.length > 0
		Layout.fillWidth: true
		spacing: Utils.getSizeWithScreenRatio(6)
		Repeater {
			model: SettingsCpp.speedDials
			MediumButton {
				Layout.fillWidth: true
				text: modelData.label
				style: ButtonStyle.secondary
				//: "Call %1"
				Accessible.name: qsTr("singleview_speed_dial_accessible").arg(modelData.label)
				onClicked: UtilsCpp.createCall(modelData.number)
			}
		}
	}

	Text {
		Layout.alignment: Qt.AlignHCenter
		//: "Keypad sends tones to the active call" / "Enter a number or address to call"
		text: dialerArea.dtmfMode ? qsTr("singleview_dialer_mode_dtmf") : qsTr("singleview_dialer_mode_compose")
		font: Typography.p4
		color: dialerArea.dtmfMode ? DefaultStyle.main1_500_main : DefaultStyle.main2_400
	}
	TextField {
		id: destField
		Layout.fillWidth: true
		//: "Number or SIP address"
		placeholderText: qsTr("singleview_dialer_placeholder")
		onAccepted: dialerArea.launchCall()
		Component.onCompleted: forceActiveFocus()
	}
	NumericPad {
		id: pad
		Layout.alignment: Qt.AlignHCenter
		lastRowVisible: false
		currentCall: dialerArea.dtmfMode ? dialerArea.currentCall : null
		onButtonPressed: (text) => { if (!dialerArea.dtmfMode) { destField.text += text; destField.forceActiveFocus() } }
	}
	Button {
		Layout.fillWidth: true
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(40)
		style: ButtonStyle.phoneGreen
		icon.source: AppIcons.phone
		//: "Call"
		text: qsTr("singleview_call_button")
		enabled: destField.text.length > 0
		onClicked: dialerArea.launchCall()
	}
}
