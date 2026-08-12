# Single-View Softphone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the multi-page linphone-desktop shell with a single fixed ~400×720 window containing header/call-stack/merge-bar/dialer/footer, per `single-view-softphone-spec.md` and `single_view_softphone_mockup.html`.

**Architecture:** All work is in `Linphone/view/` QML plus three small C++ choke points; the MVVM `core/`/`model/` bridge layers are reused untouched. A new `view/Page/SingleView/` directory holds the panel and its cards; `MainWindow.qml` routes straight to it; the secondary CallsWindow is neutralized at `App::getOrCreateCallsWindow` so every existing caller lands on the main window.

**Tech Stack:** Qt 6.10 QML, liblinphone SDK via existing `CallProxy`/`AccountProxy`/`SettingsCpp` bridges, CMake (`qt6_add_qml_module`).

## Global Constraints

- Window: width fixed at 400 (scaled by `Utils.getSizeWithScreenRatio`), initial height 720, minimum height 600, **vertically resizable only** (spec §2).
- One hardcoded theme: the existing `catapult` palette in `Linphone/view/Style/Themes.qml`; no light/dark or theme switching (spec §5).
- UI state derives **only** from liblinphone callbacks via `CallCore`/`AccountCore` properties — never optimistic local state (spec §6).
- Only modal allowed: the audio-device picker (spec FR-11 / AC-6).
- `Linphone/core/` and `Linphone/model/` stay untouched except the CallsWindow choke points in Task 8 (spec §8: "Reuse, don't rewrite").
- Keep diffs small for upstream rebases: prune at QML level; do NOT delete unused C++ classes or QML pages from the build (spec §8.6).
- This branch (`simple`) builds on the voice-only fork: chat/meetings/video are already config-disabled, SRTP mandatory, `lMergeAll` merge exists (see `VOICE_ONLY_FORK.md`).
- **Verification model:** this repo has no QML unit-test harness. Every task verifies by: (a) incremental build succeeds, (b) app launches with no QML errors on stderr, (c) a stated manual smoke check. Build command and app path are in "Build & run" below. TDD test-first steps are replaced by explicit expected-failure/expected-success build+launch checks.
- Every new QML file MUST be added to `_LINPHONEAPP_QML_FILES` in `Linphone/view/CMakeLists.txt` (paths relative to `Linphone/`, e.g. `view/Page/SingleView/MainPanel.qml`) or the loader fails at runtime with "Type … unavailable".
- All user-visible strings use `qsTr()`.
- Commit after each task on branch `simple`; end commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Build & run (used by every task's verify steps)

```bash
cd /Users/administrator/Documents/GitHub/linphone-desktop
export Qt6_DIR="$HOME/Qt/6.10.3/macos/lib/cmake/Qt6"
export PATH="$HOME/Qt/6.10.3/macos/bin:$PATH"
cmake --build build --parallel 10 2>&1 | tail -20        # incremental; SDK already built
# Run the freshly built binary directly so stderr (QML errors) lands in the terminal:
./build/OUTPUT/macos/NPPhone.app/Contents/MacOS/linphone --verbose 2>&1 | grep -iE "qml|error|warning" &
```

Notes: the app bundle is `build/OUTPUT/macos/NPPhone.app` (space-free name, commit `80b953baa`). Editing `Linphone/view/CMakeLists.txt` triggers automatic reconfigure on the next build. If the binary name differs, `ls build/OUTPUT/macos/NPPhone.app/Contents/MacOS/`. Quit the app with Cmd-Q between runs. A SIP account may already be provisioned on this machine (`~/Library/Preferences/linphone/linphonerc`), so registration state should go green shortly after launch.

## File Structure

| File | Responsibility |
|---|---|
| Create `Linphone/view/Page/SingleView/MainPanel.qml` | The single view: composes the 5 regions, owns `CallProxy`/`AccountProxy`, merge bar, footer, device-picker modal |
| Create `Linphone/view/Page/SingleView/CallCard.qml` | One call: identity, duration, state badge, per-state controls |
| Create `Linphone/view/Page/SingleView/ConferenceCard.qml` | Conference: participant list, per-participant remove, End conference |
| Create `Linphone/view/Page/SingleView/DialerArea.qml` | Text field + NumericPad + Call button + DTMF/compose modality + mode label |
| Modify `Linphone/view/Page/Window/Main/MainWindow.qml` | Route `mainPage` → MainPanel, always open main page, defang navigation functions, fixed geometry |
| Modify `Linphone/view/CMakeLists.txt` | Register the 4 new QML files |
| Modify `Linphone/core/App.cpp` | `getOrCreateCallsWindow` returns main window; outgoing-call handler raises main window |
| Modify `Linphone/view/Style/DefaultStyle.qml` | Hardcode `catapult` palette |
| Modify `Linphone/data/config/linphonerc-factory` | Remote-provisioning URI template |
| Create `docs/single-view/README.md` | Config path, log path, logging toggle, build flags, deploy notes |

Interfaces between the new files (single source of truth — later tasks must match exactly):

```
MainPanel.qml
  readonly property CallGui  currentCall     // callsModel.currentCall
  readonly property bool     haveConference  // currentCall && !!currentCall.core.conference
  property alias             dialedText      // → dialerArea.enteredText (used by CallCard transfer)
CallCard.qml
  property CallGui call
  property bool    isCurrent
  property string  transferTarget            // panel.dialedText
ConferenceCard.qml
  property CallGui call
DialerArea.qml
  property CallGui currentCall
  property alias   enteredText               // destField.text
  readonly property bool dtmfMode
```

---

### Task 1: MainPanel skeleton + shell rerouting (header/status strip)

**Files:**
- Create: `Linphone/view/Page/SingleView/MainPanel.qml`
- Modify: `Linphone/view/CMakeLists.txt` (add to `_LINPHONEAPP_QML_FILES`, alphabetically near the other `view/Page/` entries)
- Modify: `Linphone/view/Page/Window/Main/MainWindow.qml`

**Interfaces:**
- Consumes: `AccountProxy` (auto-wires, no sourceModel — `AccountProxy.cpp:26`), `AppCpp.calls`, `CallProxy`, `LinphoneEnums.RegistrationState.{None,Progress,Ok,Cleared,Failed,Refreshing}`, `DefaultStyle.account_status_{green,yellow,red,grey}` (`DefaultStyle.qml:55-62`), `account.core.identityAddress`, `account.core.humaneReadableRegistrationState` (note the upstream typo "humane" — that IS the property name, `AccountCore.hpp`), `account.core.lSetRegisterEnabled(true)` (always calls `refreshRegister()` when enabling — `AccountModel.cpp:213-218` — so it doubles as "Retry").
- Produces: `MainPanel` QML type with `currentCall`, `haveConference`, `dialedText` (see interface table); placeholder region comments `// REGION: call stack` etc. that Tasks 3–7 replace.

- [ ] **Step 1: Write MainPanel.qml**

```qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

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
```

Add `import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle` to the import block (SmallButton's `style` needs it).

- [ ] **Step 2: Register in the build**

In `Linphone/view/CMakeLists.txt`, inside the `_LINPHONEAPP_QML_FILES` list, add (keeping the list's ordering style):

```cmake
    view/Page/SingleView/MainPanel.qml
```

- [ ] **Step 3: Reroute MainWindow.qml**

In `Linphone/view/Page/Window/Main/MainWindow.qml`:

a) Replace the `mainPage` component (lines 345-360) with:

```qml
	Component {
		id: mainPage
		MainPanel {
			objectName: "mainPage"   // openMainPage() checks this
		}
	}
```

b) Replace `initStackViewItem()` (lines 78-85) with:

```qml
	function initStackViewItem() {
		// Single-view app: no login/welcome routes — account arrives via provisioning.
		openMainPage()
	}
```

c) Defang every navigation function so C++ invocations (`Utils.cpp:1772/2093/2098`, tray, shortcuts) can't error: replace the bodies of `goToCallHistory`, `goToNewCall`, `displayContactPage(contactAddress)`, `displayCreateContactPage(name, contactAddress)`, `displayChatPage(contactAddress)`, `openChat(chat)`, `scheduleMeeting(subject, addresses)`, and `goToLogin()` with a single line each: `openMainPage()`. Keep `transferCallSucceed()` as is (its popup is still wanted). In `openMainPage()` keep only the first line (drop the "Connexion réussie" popup block and the `connectionSucceed` parameter usage — keep the parameter so `App.cpp:456/892` invocations still bind).

d) Delete the components and blocks that are now unreachable: `welcomePage` (213-221), `ssoPage` (222-260) **and** its Loader (168-172), `loginPage` (261-271), `sipLoginPage` (272-286), `registerPage` (287-306), `checkingPage` (307-332), `securityModePage` (333-344), the `Connections { target: LoginPageCpp ... }` block (134-142), and inside `Connections { target: SettingsCpp }` the `onAssistantGoDirectlyToThirdPartySipAccountLoginChanged` handler (keep `onIsSavedChanged`). In `reauthenticateAccount()` delete the two-line `objectName === "loginPage"` early-return (113-115). Keep: splash screen, `authenticationPopupComp`, `accountProxyLoader`, `mainStackViewComp` (the H264 repeater inside it is dead but harmless — leave it, small-diff rule).

- [ ] **Step 4: Build and launch — expect the single view**

Run the Build & run block. Expected: build succeeds; app opens showing the header strip with a colored dot + your SIP identity + "Registered" (or grey "No account provisioned"), "No active calls" hint below, no tab bar, no login page. Console shows no `qrc:...MainPanel.qml` errors. If the window is still huge, that's expected — geometry is Task 2.

- [ ] **Step 5: Commit**

```bash
git add Linphone/view/Page/SingleView/MainPanel.qml Linphone/view/CMakeLists.txt Linphone/view/Page/Window/Main/MainWindow.qml
git commit -m "feat(singleview): single-view panel skeleton, reroute shell past login/tabs"
```

---

### Task 2: Fixed window geometry (400 wide, vertical resize only)

**Files:**
- Modify: `Linphone/view/Page/Window/Main/MainWindow.qml` (top of file, lines ~16-31)

**Interfaces:**
- Consumes: `AbstractWindow.qml:16-17` default width/height bindings (overridden here).
- Produces: nothing new.

- [ ] **Step 1: Set the geometry**

In `MainWindow.qml`, replace the existing `minimumWidth`/`minimumHeight` lines (24-25) and add explicit size overrides right below `color: DefaultStyle.grey_0`:

```qml
	// Single-view: fixed width, vertically resizable only (spec §2)
	width: Utils.getSizeWithScreenRatio(400)
	height: Utils.getSizeWithScreenRatio(720)
	minimumWidth: Utils.getSizeWithScreenRatio(400)
	maximumWidth: Utils.getSizeWithScreenRatio(400)
	minimumHeight: Utils.getSizeWithScreenRatio(600)
```

- [ ] **Step 2: Build, launch, check**

Expected: window opens ~400×720; dragging the left/right edges does nothing; dragging the bottom edge resizes vertically; the green maximize control doesn't widen it (macOS may zoom vertically — acceptable).

- [ ] **Step 3: Commit**

```bash
git add Linphone/view/Page/Window/Main/MainWindow.qml
git commit -m "feat(singleview): fixed 400-wide window, vertical resize only"
```

---

### Task 3: Call stack with call cards (FR-3, FR-4, FR-5 minus DTMF)

**Files:**
- Create: `Linphone/view/Page/SingleView/CallCard.qml`
- Modify: `Linphone/view/Page/SingleView/MainPanel.qml` (REGION 2)
- Modify: `Linphone/view/CMakeLists.txt` (add `view/Page/SingleView/CallCard.qml`)

**Interfaces:**
- Consumes: `CallGui.core` properties `remoteName`, `remoteAddress`, `state`, `duration`, `paused`, `microphoneMuted`, `conference`; commands `lAccept(false)`, `lDecline()`, `lTerminate()`, `lSetPaused(bool)`, `lSetMicrophoneMuted(bool)` (all on `CallCore.hpp:284-303`); `UtilsCpp.formatElapsedTime(seconds)` (usage: `CallsWindow.qml:451`); `LinphoneEnums.CallState.*` (`LinphoneEnums.hpp:126-150`); icons `AppIcons.endCall`, `AppIcons.pause`, `AppIcons.play`, `AppIcons.microphone`, `AppIcons.microphoneSlash`, `AppIcons.phone`.
- Produces: `CallCard { call, isCurrent, transferTarget }` — `transferTarget` is declared now (empty default) and wired in Task 6.

- [ ] **Step 1: Write CallCard.qml**

```qml
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
			style: ButtonStyle.phoneGreen
			//: "Answer"
			Accessible.name: qsTr("singleview_answer")
			onClicked: card.call.core.lAccept(false)
		}
		SmallButton {
			visible: card.incoming
			icon.source: AppIcons.endCall
			style: ButtonStyle.phoneRed
			//: "Decline"
			Accessible.name: qsTr("singleview_decline")
			onClicked: card.call.core.lDecline()
		}

		// Normal controls
		SmallButton {
			visible: !card.incoming && (card.connected || card.held)
			icon.source: card.call && card.call.core.microphoneMuted ? AppIcons.microphoneSlash : AppIcons.microphone
			style: ButtonStyle.secondary
			//: "Mute"
			Accessible.name: qsTr("singleview_mute")
			onClicked: card.call.core.lSetMicrophoneMuted(!card.call.core.microphoneMuted)
		}
		SmallButton {
			visible: !card.incoming && (card.connected || card.held)
			icon.source: card.held ? AppIcons.play : AppIcons.pause
			style: ButtonStyle.secondary
			//: "Hold / Resume"
			Accessible.name: qsTr("singleview_hold_resume")
			onClicked: card.call.core.lSetPaused(!card.call.core.paused)
		}
		SmallButton {
			visible: !card.incoming
			icon.source: AppIcons.endCall
			style: ButtonStyle.phoneRed
			//: "Hang up"
			Accessible.name: qsTr("singleview_hangup")
			onClicked: card.call.core.lTerminate()
		}
	}
}
```

Note for the implementer: `SmallButton` derives from `view/Control/Button/Button.qml`; set `icon.width`/`icon.height` to `Utils.getSizeWithScreenRatio(16)` and `Layout.preferredWidth/Height` to `Utils.getSizeWithScreenRatio(34)` on each SmallButton to match the mockup's 34px square buttons — copy the exact property names used by a SmallButton instance in `ParticipantListView.qml:96-108`.

- [ ] **Step 2: Bind the call stack in MainPanel**

Replace REGION 2's placeholder `Item` with:

```qml
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
```

(The list model's single role is `$modelData` → delegates read `modelData` as a `CallGui`; ordering follows `CallList` insertion order = creation order, satisfying spec §5.2.)

- [ ] **Step 3: Register CallCard.qml in `Linphone/view/CMakeLists.txt`** (`view/Page/SingleView/CallCard.qml`).

- [ ] **Step 4: Build, launch, smoke-test**

Expected: builds clean; with no calls, the hint shows. If a test SIP peer is available: dial the account from another phone → a card appears with Answer/Decline; Answer connects (audio both ways), duration ticks, Hold greys the card and shows "On hold", Mute toggles the icon, Hang up removes the card. If no peer is available, verify at minimum: app launches, no QML errors referencing CallCard/MainPanel.

- [ ] **Step 5: Commit**

```bash
git add Linphone/view/Page/SingleView/CallCard.qml Linphone/view/Page/SingleView/MainPanel.qml Linphone/view/CMakeLists.txt
git commit -m "feat(singleview): call stack with per-call cards (answer/decline/hold/mute/hangup)"
```

---

### Task 4: Dialer with DTMF/compose modality (FR-2, FR-5 DTMF)

**Files:**
- Create: `Linphone/view/Page/SingleView/DialerArea.qml`
- Modify: `Linphone/view/Page/SingleView/MainPanel.qml` (REGION 4 + `dialedText` alias)
- Modify: `Linphone/view/CMakeLists.txt` (add `view/Page/SingleView/DialerArea.qml`)

**Interfaces:**
- Consumes: `NumericPad` (`view/Control/Input/NumericPad.qml`) — its **internal** `onButtonPressed` (lines 18-21) already sends DTMF via `currentCall.core.lSendDtmf(text)` when `currentCall` is set, else plays a local tone; our use-site handler additionally appends to the field when composing. `TextField` (`view/Control/Input/TextField.qml`). `UtilsCpp.createCall(QString)` (`Utils.hpp:72`). `ButtonStyle.phoneGreen`.
- Produces: `DialerArea { currentCall, enteredText (alias), dtmfMode (readonly) }`; MainPanel gains `property alias dialedText: dialerArea.enteredText`.

- [ ] **Step 1: Write DialerArea.qml**

```qml
import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
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
	}
	NumericPad {
		id: pad
		Layout.alignment: Qt.AlignHCenter
		lastRowVisible: false
		currentCall: dialerArea.dtmfMode ? dialerArea.currentCall : null
		onButtonPressed: (text) => { if (!dialerArea.dtmfMode) destField.text += text }
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
```

Implementer notes: NumericPad's default 60px buttons with 40px column spacing are ~260px wide total — fits the 400px window; if it overflows, shrink via the `implicitWidth` pattern is NOT available — instead accept the default and reduce `Layout.margins` in MainPanel. `TextField` in this codebase may name its placeholder property differently — check `view/Control/Input/TextField.qml` for `placeholderText` vs a custom alias and use what it defines.

- [ ] **Step 2: Mount in MainPanel**

Replace REGION 4's placeholder comment with:

```qml
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
```

and change `property string dialedText: ""` to `property alias dialedText: dialerArea.enteredText`.

- [ ] **Step 3: Register DialerArea.qml in `Linphone/view/CMakeLists.txt`.**

- [ ] **Step 4: Build, launch, smoke-test**

Expected: pad clicks append digits to the field (mode label: compose); Call button dials via `UtilsCpp.createCall` (registration failure popup appears if unregistered — fine); during a connected call the label flips to the DTMF wording and pad clicks no longer touch the field (tones audible to the far end / IVR — AC-5). Putting the call on hold flips back to compose so the expert can be dialed (core workflow, spec §2).

- [ ] **Step 5: Commit**

```bash
git add Linphone/view/Page/SingleView/DialerArea.qml Linphone/view/Page/SingleView/MainPanel.qml Linphone/view/CMakeLists.txt
git commit -m "feat(singleview): dialer with DTMF/compose modality"
```

---

### Task 5: Merge bar + conference card (FR-6, FR-7)

**Files:**
- Create: `Linphone/view/Page/SingleView/ConferenceCard.qml`
- Modify: `Linphone/view/Page/SingleView/MainPanel.qml` (REGION 3)
- Modify: `Linphone/view/CMakeLists.txt` (add `view/Page/SingleView/ConferenceCard.qml`)

**Interfaces:**
- Consumes: `callsModel.lMergeAll()` (upstream merge — `CallList.cpp:86-127`: reuses/creates conference, adds all current calls); `ParticipantProxy { currentCall, showMe }` with `removeParticipant(ParticipantCore*)` (`ParticipantProxy.hpp`, reference use `ParticipantListView.qml:41-44,107`); `modelData.core.displayName` on participants; `call.core.lTerminateAllCalls()` (ends every leg — spec FR-7 wants exactly this; note `ConferenceCore` exposes no terminate command signal, so this is the supported path); `AppIcons.arrowsMerge`, `AppIcons.closeX`.
- Produces: `ConferenceCard { call }`.
- **Known bug to avoid:** do NOT copy the enabled-predicate from `CallsWindow.qml:1637` (`callsModel.count + (currentCall ? 1 : 0) >= 2`) — a bare `CallProxy` defaults `showCurrentCall` to **true** (`CallProxy.cpp:29`), so `count` already includes the current call and the correct predicate is simply `callsModel.count >= 2`.

- [ ] **Step 1: Write ConferenceCard.qml**

```qml
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
			SmallButton {
				//: "End conference"
				text: qsTr("singleview_end_conference")
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
```

Implementer notes: verify `showMe` exists on `ParticipantProxy` (`Linphone/core/participant/ParticipantProxy.hpp`); if the property is absent, drop that line and instead hide the local participant in the delegate with `visible: !modelData.core.isMe`. `Typography.p2` — if that role doesn't exist in `Typography.qml`, use `p1` (check the file).

- [ ] **Step 2: Mount merge bar + card in MainPanel**

Replace REGION 3's placeholder comment with:

```qml
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
```

- [ ] **Step 3: Register ConferenceCard.qml in `Linphone/view/CMakeLists.txt`.**

- [ ] **Step 4: Build, launch, smoke-test (needs two peers or PBX test numbers)**

Expected: with 2 live calls the merge bar appears (with exactly 2, not 3 — the count-bug regression check); clicking it merges (the SDK PBX-contact patch on this branch prevents the same-Contact terminate bug); leg cards disappear (their `core.conference` is set), the conference card lists both participants; both remote parties hear each other (AC-2); removing one participant leaves the other leg connected (AC-3); End conference drops everything. Cannot be verified without live calls — if unavailable, verify build + no QML errors and mark the runtime checks for the pilot checklist.

- [ ] **Step 5: Commit**

```bash
git add Linphone/view/Page/SingleView/ConferenceCard.qml Linphone/view/Page/SingleView/MainPanel.qml Linphone/view/CMakeLists.txt
git commit -m "feat(singleview): merge bar and conference card with participant management"
```

---

### Task 6: Blind transfer (FR-8)

**Files:**
- Modify: `Linphone/view/Page/SingleView/CallCard.qml` (add transfer button)
- Modify: `Linphone/view/Page/SingleView/MainPanel.qml` (pass `transferTarget`)

**Interfaces:**
- Consumes: `call.core.lTransferCall(QString address)` (blind transfer → `CallModel::transferTo`, `CallCore.hpp:284-303`); `AppIcons.transferCall`; `MainPanel.dialedText` (Task 4 alias).
- Produces: nothing new.

- [ ] **Step 1: Add the transfer button to CallCard.qml**

Insert between the Hold/Resume and Hang up buttons:

```qml
		SmallButton {
			// Blind transfer to the address typed in the dialer (spec FR-8)
			visible: !card.incoming && (card.connected || card.held)
			enabled: card.transferTarget.length > 0
			icon.source: AppIcons.transferCall
			style: ButtonStyle.secondary
			//: "Transfer to the entered address"
			Accessible.name: qsTr("singleview_transfer")
			onClicked: card.call.core.lTransferCall(card.transferTarget)
		}
```

- [ ] **Step 2: Wire `transferTarget` in MainPanel's delegate**

In the `CallCard` delegate inside `callStack` (Task 3), add:

```qml
				transferTarget: mainPanel.dialedText
```

- [ ] **Step 3: Build, launch, smoke-test**

Expected: transfer button is greyed until the dialer field has text; with an active call and a target typed, clicking it transfers the call (far end gets REFER, local card ends shortly after; `transferCallSucceed()` toast may appear via `MainWindow`). Without a live peer: build + button enable/disable behavior with field text.

- [ ] **Step 4: Commit**

```bash
git add Linphone/view/Page/SingleView/CallCard.qml Linphone/view/Page/SingleView/MainPanel.qml
git commit -m "feat(singleview): blind transfer to dialed address"
```

---

### Task 7: Footer + audio-device picker modal (FR-9, spec §5.5)

**Files:**
- Modify: `Linphone/view/Page/SingleView/MainPanel.qml` (REGION 5 + the modal)

**Interfaces:**
- Consumes: `SettingsCpp.playbackDevice` (QVariantMap with keys `id`, `display_name` — `ToolModel.cpp:663-671`); `MultimediaSettings` (`view/Control/Form/Settings/MultimediaSettings.qml`) with `ringerDevicesVisible: true` (ringer combo, FR-9) and `call:` set so device changes apply live in-call (its internal `Connections` fire `SettingsCpp.lSet*Device`, lines 96-102/147-153; the `ComboSetting` still persists via `propertyOwner`, giving restart persistence); it also contains the mic level meter (spec §5.5 "optional" — included for free); `AppIcons.speaker`, `AppIcons.settings`.
- Produces: nothing consumed later.

- [ ] **Step 1: Footer + modal in MainPanel**

Replace REGION 5's placeholder comment with:

```qml
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
```

And add the modal as a direct child of `mainPanel` (outside the ColumnLayout):

```qml
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
```

Implementer notes: `Control.Popup` needs `import QtQuick.Controls.Basic as Control` (already imported in Task 1). `MultimediaSettings` sets 40px internal spacing and its own RoundedPane background — if it overflows the 400px window vertically, wrap it in a `Flickable` (`view/Control/Display/Flickable.qml`) with `Layout.preferredHeight: Math.min(implicitHeight, mainPanel.height - 200)`. `SettingsCpp.playbackDevice["display_name"]` binding refreshes on `playbackDeviceChanged` automatically.

- [ ] **Step 2: Build, launch, smoke-test**

Expected: footer shows the current output device name (e.g. "Core Audio: MacBook Pro Speakers"); the gear opens a centered modal with ringer/speaker/mic combos + mic meter; picking a different device updates the footer text; the choice survives an app restart (FR-9); Close dismisses. Unplugging a USB headset mid-call falls back without dropping (AC-4 — SDK behavior, spot-check if hardware available).

- [ ] **Step 3: Commit**

```bash
git add Linphone/view/Page/SingleView/MainPanel.qml
git commit -m "feat(singleview): footer with device name and audio-device picker modal"
```

---

### Task 8: Neutralize the secondary call window (FR-11, AC-6)

**Files:**
- Modify: `Linphone/core/App.cpp` (`getOrCreateCallsWindow` ~line 1325; outgoing-call handler ~lines 780-792)

**Interfaces:**
- Consumes: `App::getMainWindow()` (returns `QQuickWindow*`, same type as the current return), `Utils::smartShowWindow`.
- Produces: every existing caller — `Utils::openCallsWindow/getOrCreateCallsWindow/setupConference` (`Utils.cpp:228-251`), `NotificationReceivedCall.qml:121-126` (Accept), headset handling (`CallCore.cpp:487-500`) — now lands on the main window. `mCallsWindow` stays null forever, so `closeCallsWindow()` (1370) and `setCallsWindowProperty` (1366) become natural no-ops (they already null-check — verify).

- [ ] **Step 1: Short-circuit window creation**

In `Linphone/core/App.cpp`, replace the body of `App::getOrCreateCallsWindow` (~1325-1364) with:

```cpp
QQuickWindow *App::getOrCreateCallsWindow(QVariant callGui) {
	// Single-view app: all call UI lives in the main window; never create CallsWindow.
	Q_UNUSED(callGui)
	return getMainWindow();
}
```

Note: callers may `setProperty("call", ...)` on the returned window — on the QML MainWindow this creates a harmless dynamic property.

- [ ] **Step 2: Outgoing calls raise the main window**

In the `CallList::currentCallChanged` lambda (~780-792), keep the `CallDir::Incoming` early return, and replace the `getOrCreateCallsWindow(...)` + `smartShowWindow(...)` + `invokeMethod(mainwin, "callCreated")` lines with:

```cpp
							    Utils::smartShowWindow(getMainWindow());
```

(Leave the `signal callCreated()` declaration in MainWindow.qml — other C++ may reference it; unemitted is fine.)

- [ ] **Step 3: Verify remaining references are null-safe**

Run: `grep -n "mCallsWindow" Linphone/core/App.cpp | head -30` and read each hit — every use must be guarded by a null check (upstream already guards; fix any that aren't with an early `if (!mCallsWindow) return;`).

- [ ] **Step 4: Build, launch, smoke-test**

Expected: dialing from the panel no longer opens a second window — the main window just raises; answering from the incoming-call desktop notification raises the main window and connects the call (card goes Active); at no point does a 1020px CallsWindow appear (AC-6). `grep` the run log for `CallsWindow.qml` — it must not be instantiated.

- [ ] **Step 5: Commit**

```bash
git add Linphone/core/App.cpp
git commit -m "feat(singleview): route all call UI to the main window, never create CallsWindow"
```

---

### Task 9: Hardcode the theme (spec §5)

**Files:**
- Modify: `Linphone/view/Style/DefaultStyle.qml` (lines 8-10)

**Interfaces:**
- Consumes: `Themes.themes["catapult"]` (`Themes.qml`, added by the fork).
- Produces: `DefaultStyle.main1_*` permanently bound to the catapult navy ramp.

- [ ] **Step 1: Hardcode the palette**

Replace lines 8-10 of `Linphone/view/Style/DefaultStyle.qml`:

```qml
	property var currentTheme: Themes.themes.hasOwnProperty(SettingsCpp.themeMainColor)
							  ? Themes.themes[SettingsCpp.themeMainColor]
							  : Themes.themes["orange"]
```

with:

```qml
	// Single-view fork: one hardcoded company theme; config/theme switching is intentionally dead (spec §5).
	readonly property var currentTheme: Themes.themes["catapult"]
```

If the `SettingsCpp` import in this file becomes unused after the change, leave it (other properties may use it — check before removing). Deeper theme-plumbing removal (settings keys, unused palettes in `Themes.qml`) is deferred per the small-diff rule (spec §8.6).

- [ ] **Step 2: Build, launch, check**

Expected: accents (active-card border, merge button, mode label) render Catapult navy `#1B365D` even if `theme_main_color` is removed from the user's linphonerc.

- [ ] **Step 3: Commit**

```bash
git add Linphone/view/Style/DefaultStyle.qml
git commit -m "feat(singleview): hardcode catapult theme palette"
```

---

### Task 10: Provisioning template + operations doc (spec §9, FR-10, FR-12)

**Files:**
- Modify: `Linphone/data/config/linphonerc-factory`
- Create: `docs/single-view/README.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: documentation only.

- [ ] **Step 1: Add the remote-provisioning template to `linphonerc-factory`**

Append:

```ini
[misc]
# Remote provisioning (spec §9): point at the internal HTTPS endpoint serving the
# per-agent SIP account, transports=TLS, media encryption, codec order and ICE/STUN/TURN.
# Injected/overridden at deploy time by Ansible; no secrets ship in this file.
# config-uri=https://provisioning.example.internal/npphone/default.xml
```

(Leave it commented: the real URI is deploy-time config. FR-10's codec/ICE/encryption settings live in the provisioned file, not the UI — nothing to code.)

- [ ] **Step 2: Write `docs/single-view/README.md`**

Content requirements (write real values, verifying each by grep before writing):
- Config paths: factory config inside the bundle (`Contents/Resources/share/linphone/linphonerc-factory`), user config `~/Library/Preferences/linphone/linphonerc`.
- Log path and verbose-logging toggle (FR-12): grep `Linphone/model/setting/SettingsModel.cpp` for `logs_enabled` / log folder keys (`grep -n "logs" Linphone/model/setting/SettingsModel.cpp | head -20`) and document the exact `[section] key=value` an admin sets in `linphonerc`, plus the default log directory (grep `Paths` / `getLogsDirectory` under `Linphone/tool/` if needed).
- Build: the Build & run block from this plan, plus spec §8.7 flags for packaging builds: `-DENABLE_APP_PDF_VIEWER=NO -DENABLE_APP_WEBVIEW=NO -DENABLE_UPDATE_CHECK=NO -DENABLE_BUILD_APP_PLUGINS=NO` (verify each option exists: `grep -rn "ENABLE_APP_PDF_VIEWER\|ENABLE_APP_WEBVIEW\|ENABLE_UPDATE_CHECK\|ENABLE_BUILD_APP_PLUGINS" CMakeLists.txt cmake/ Linphone/CMakeLists.txt`; document only the ones that exist, note any that don't).
- Pointer to `VOICE_ONLY_FORK.md` for the voice-only policy and to `single-view-softphone-spec.md` §11 for the acceptance checklist (AC-1…AC-7) to run during pilot.

- [ ] **Step 3: Build (config file is bundled at install — verify it copies)**

`cmake --build build --parallel 10` then `grep -n "config-uri" "build/OUTPUT/macos/NPPhone.app/Contents/Resources/share/linphone/linphonerc-factory"` — expect the commented line present (if the bundle path differs, `find build/OUTPUT -name linphonerc-factory`).

- [ ] **Step 4: Commit**

```bash
git add Linphone/data/config/linphonerc-factory docs/single-view/README.md
git commit -m "docs(singleview): provisioning template and operations notes"
```

---

## Spec coverage self-review (done at planning time)

| Spec item | Task |
|---|---|
| FR-1 register on launch + live state | 1 (header; registration itself is existing core behavior) |
| FR-2 outbound dial | 4 |
| FR-3 incoming answer/decline in-view | 3 (+ existing desktop notification, now raising the main window: 8) |
| FR-4 call cards (identity/duration/state) | 3 |
| FR-5 hold/mute/hangup + DTMF modality | 3, 4 |
| FR-6 merge ≥2 calls | 5 |
| FR-7 participant list / remove / end-all | 5 |
| FR-8 blind transfer (attended = phase 2, out of scope) | 6 |
| FR-9 device selection persists, ringer, hot-plug | 7 |
| FR-10 codecs/ICE/encryption via provisioning | 10 (config; SRTP already mandatory on this fork) |
| FR-11 no navigation, single modal | 1, 7, 8 |
| FR-12 config-file logging | 10 |
| §5 five regions + theme | 1, 3, 4, 5, 7, 9 |
| §8.7 build flags | 10 (documented; packaging/CI/Windows installer are deployment work outside this branch's code scope) |
| §9 provisioning | 10 |
| §10 packaging/CI, §12 M5-M6 | **Out of scope** for this plan: infra/Windows-runner work, flagged for a follow-up plan |

Known risks for the executor: `currentCall.core.conference` as the conference-detection predicate and leg-card hiding (Task 3/5) match upstream `CallsWindow` usage but MUST be confirmed with a live two-call merge; if after `lMergeAll` the leg cards don't hide, inspect `modelData.core.conference` per leg and fall back to hiding via `modelData.core.isConference`.
