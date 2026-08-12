import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls.Basic
import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

AbstractWindow {
	id: mainWindow
    // height: Utils.getSizeWithScreenRatio(982)
    title: applicationName
	// TODO : handle this bool when security mode is implemented
	property bool firstConnection: true
    property int initialWidth
    property int initialHeight
    Component.onCompleted: {
        initialWidth = width
        initialHeight = height
    }

	color: DefaultStyle.grey_0
	// Single-view: fixed width, vertically resizable only (spec §2)
	width: Utils.getSizeWithScreenRatio(400)
	height: Utils.getSizeWithScreenRatio(720)
	minimumWidth: Utils.getSizeWithScreenRatio(400)
	maximumWidth: Utils.getSizeWithScreenRatio(400)
	minimumHeight: Utils.getSizeWithScreenRatio(600)

	signal callCreated()
	property var accountProxy

	// TODO : use this to make the border transparent
	flags: Qt.Window
	// menuBar: Rectangle {
	// 	width: parent.width
    // 	height: Utils.getSizeWithScreenRatio(40)
	// 	color: DefaultStyle.grey_100
	// }

	function openMainPage(connectionSucceed){
		if (!mainStackViewLoader.item || !mainStackViewLoader.item.currentItem || mainStackViewLoader.item.currentItem.objectName !== "mainPage") mainStackViewLoader.item.replace(mainPage, StackView.Immediate)
	}
	function goToCallHistory() {
		openMainPage()
	}
	function goToNewCall() {
		openMainPage()
	}
	function displayContactPage(contactAddress) {
		openMainPage()
	}
	function displayCreateContactPage(name, contactAddress) {
		openMainPage()
	}
	function displayChatPage(contactAddress) {
		openMainPage()
	}
	function openChat(chat) {
		openMainPage()
	}
	function transferCallSucceed() {
		openMainPage()
        //: "Appel transféré"
        mainWindow.showInformationPopup(qsTr("call_transfer_successful_toast_title"),
                                        //: "Votre correspondant a été transféré au contact sélectionné"
                                        qsTr("call_transfer_successful_toast_message"))
	}
	function initStackViewItem() {
		// Single-view app: no login/welcome routes — account arrives via provisioning.
		openMainPage()
	}
	
	function goToLogin() {
		openMainPage()
	}

	function scheduleMeeting(subject, addresses) {
		openMainPage()
	}

	property bool authenticationPopupOpened: false
	Component {
		id: authenticationPopupComp
		AuthenticationDialog{
			onOpened: mainWindow.authenticationPopupOpened = true
			onClosed: {
				mainWindow.authenticationPopupOpened = false
				destroy()
			}
		}
	}

	function reauthenticateAccount(identity, domain, callback){
		if (authenticationPopupOpened) return
		console.log("Showing authentication dialog")
		var popup = authenticationPopupComp.createObject(mainWindow, {"identity": identity, "domain": domain, "callback":callback})	// Callback ownership is not passed
		popup.open()
		popup.announce()
	}

	Connections {
		target: SettingsCpp
		function onIsSavedChanged(saved) {
            if (saved) UtilsCpp.showInformationPopup(qsTr("information_popup_success_title"),
                                                                   //: "Les changements ont été sauvegardés"
                                                                   qsTr("information_popup_changes_saved"), true, mainWindow)
        }
	}

	Loader {
		id: accountProxyLoader
		active: AppCpp.coreStarted
		sourceComponent: AccountProxy {
            onInitializedChanged: if (isInitialized) {
				mainWindow.accountProxy = this
				mainWindow.initStackViewItem()
            }
		}
	}

	Loader {
		id: mainStackViewLoader
		active: AppCpp.coreStarted
		anchors.fill: parent
		sourceComponent: mainStackViewComp
	}

	Loader {
		anchors.fill: parent
		active: !AppCpp.coreStarted
		sourceComponent: splashScreen
	}

	Component {
		id: mainStackViewComp
		StackView {
			id: mainWindowStackView
			// H264 Cisco codec download
			PayloadTypeProxy {
				id: downloadableVideoPayloadTypeProxy
				filterType: PayloadTypeProxy.Video | PayloadTypeProxy.Downloadable
			}
			Repeater {
				id: codecDownloader
				model: null
				Item {
					Component.onCompleted: {
						if (modelData.core.mimeType == "H264")
							Utils.openCodecOnlineInstallerDialog(mainWindow, modelData.core)
					}
				}
			}
			function proposeH264CodecsDownload() {
				codecDownloader.model = downloadableVideoPayloadTypeProxy
			}
		}
	}

	Component {
		id: splashScreen
		Rectangle {
			color: DefaultStyle.grey_0
			Image {
				anchors.centerIn: parent
				source: AppIcons.splashscreenLogo
                sourceSize.width: Utils.getSizeWithScreenRatio(395)
                sourceSize.height: Utils.getSizeWithScreenRatio(395)
                width: Utils.getSizeWithScreenRatio(395)
                height: Utils.getSizeWithScreenRatio(395)
			}
		}
	}
	Component {
		id: mainPage
		MainPanel {
			objectName: "mainPage"   // openMainPage() checks this
		}
	}

}
