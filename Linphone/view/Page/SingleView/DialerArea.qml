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
	// Legs of the active conference (empty when there is none). liblinphone clears the
	// "current call" once legs are merged, so DTMF must target the conference legs instead.
	property var conferenceLegs: []
	property alias enteredText: destField.text
	function isLive(gui) {
		return gui && gui.core && !gui.core.paused
			&& (gui.core.state === LinphoneEnums.CallState.Connected
				|| gui.core.state === LinphoneEnums.CallState.StreamsRunning)
	}
	// Where keypad tones go: the connected current call, else every connected conference leg
	// (a tone meant for a patient IVR reaching the interpreter as well is harmless).
	readonly property var dtmfTargets: isLive(currentCall) ? [currentCall] : conferenceLegs.filter(isLive)
	// DTMF mode iff there is a connected, un-held call to send tones to (spec §5.4, FR-5)
	readonly property bool dtmfMode: dtmfTargets.length > 0
	spacing: Utils.getSizeWithScreenRatio(8)

	function sendDtmf(text) {
		for (var i = 0; i < dtmfTargets.length; ++i) dtmfTargets[i].core.lSendDtmf(text)
	}
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
		// Physical keyboard: while a call can take tones, digits / * / # are sent as DTMF
		// instead of being typed into the field (IVR menus: "press 1 for …").
		Keys.onPressed: (event) => {
			if (!dialerArea.dtmfMode) return
			if (event.text.length === 1 && /[0-9*#]/.test(event.text)) {
				dialerArea.sendDtmf(event.text)
				event.accepted = true
			}
		}
	}
	NumericPad {
		id: pad
		Layout.alignment: Qt.AlignHCenter
		lastRowVisible: false
		// The pad itself sends to (and plays the tone for) the first target; any further
		// conference legs get the tone here.
		currentCall: dialerArea.dtmfMode ? dialerArea.dtmfTargets[0] : null
		onButtonPressed: (text) => {
			if (dialerArea.dtmfMode) {
				for (var i = 1; i < dialerArea.dtmfTargets.length; ++i) dialerArea.dtmfTargets[i].core.lSendDtmf(text)
			} else { destField.text += text; destField.forceActiveFocus() }
		}
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
