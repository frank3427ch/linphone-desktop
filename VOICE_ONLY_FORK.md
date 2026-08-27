# NP Phone — Voice-Only Linphone Fork — Complete Change Documentation

This document records every change made to turn stock **linphone-desktop** into
**NP Phone**, a voice-only corporate softphone for Apple Silicon Macs, in
enough detail to reproduce the fork from a clean upstream checkout.

- **Upstream baseline (app):** linphone-desktop `master` @ `9bee5060d`
  (BelledonneCommunications master merged 2026-08-27; previously `92320d862`),
  app version 6.3.0-alpha
- **Upstream baseline (SDK):** linphone-sdk submodule @ `4bb4159ac` (5.5.16;
  previously `393b0a1f33` / 5.5.9)
- **Shipped branch:** `simple` (single-view softphone, built on top of this
  voice-only fork). Everything in this file is already committed there; the
  single-view layer on top is described in `single-view-softphone-spec.md` and
  `docs/single-view/README.md`, which also holds the **from-scratch build and
  deployment procedure**.
- **Upstream-merge notes (2026-08-27):** merging `origin/master` produced one
  conflict, `Linphone/core/App.cpp` (`currentCallChanged` handler): upstream
  changed `smartShowWindow(win)` → `showCallsWindow(win)` in a block the
  `simple` branch replaced wholesale (calls are routed to the main window and
  no `CallsWindow` is ever created — commit `ca58ae5ea`). Resolution: keep the
  `simple` side. Upstream also added a **private** submodule
  `external/feature-specs` (`gitlab.linphone.org:BC/private/linphone-test-specs`,
  Squish BDD specs only) — it cannot be cloned without BC credentials and is
  not needed to build; see §6.2.
- **Product goals:** SIP audio calling only; no chat, no video, no meetings UI;
  simplified UI (dialer, call history, contacts); mandatory SRTP; numbers and
  contact names shown instead of SIP URIs; in-call usability additions
  (embedded call list + DTMF dialer, one-click merge); branded "NP Phone" with
  custom icon and Catapult Health navy color theme

---

## 1. Voice-only policy — factory configuration

**File: `Linphone/data/config/linphonerc-factory`**
(installed into the app bundle at `Contents/Resources/share/linphone/linphonerc-factory`
and loaded as factory config at core creation — `CoreModel.cpp` `createCore(...)`)

Add to the `[ui]` section:

```ini
# Voice-only deployment: hide all chat/messaging UI and drop incoming messages.
# The /readonly entries take precedence over any value in the user's linphonerc
# and cannot be changed from the app.
disable_chat_feature/readonly=1
disable_meetings_feature/readonly=1
# Show usernames/numbers instead of full SIP addresses throughout the UI
hide_sip_addresses=1
# Catapult Health brand theme (navy from catapulthealth.com)
theme_main_color=catapult
# Lock chat room creation off
standard_chat_enabled/readonly=0
secure_chat_enabled/readonly=0
```

Add to the `[sip]` section:

```ini
# Voice-only deployment: require SRTP media encryption on all calls
media_encryption=srtp
media_encryption_mandatory=1
```

Add to the `[video]` section:

```ini
# Voice-only deployment: disable video capture/display so all camera
# controls and previews are hidden and calls are audio-only
capture=0
display=0
show_local=0
# Never offer or accept video escalation on calls
automatically_initiate=0
automatically_accept=0
```

What this achieves (all UI gating already exists upstream):
- `disable_chat_feature` hides the Conversations tab, chat panels/buttons, and
  short-circuits incoming-message handling in `CoreModel.cpp` (no
  notifications, no stored history).
- `disable_meetings_feature` hides the Meetings tab, group-call button, and
  meeting settings.
- `hide_sip_addresses` makes every list/detail view show `2147852200` instead
  of `sip:2147852200@domain` (search suggestions, contact cards, history,
  call views).
- `[video] capture/display=0` makes `core->videoEnabled()` false, which hides
  every camera control, preview, and video-call button (all bound to
  `SettingsCpp.videoEnabled`). The "Enable video" settings switch is already
  `visible: false` upstream, so there is no UI path to re-enable it.
- SRTP keys enforce encrypted media; **the PBX must support SRTP** or calls
  will be rejected (see §8 Caveats).

## 2. Branding — "NP Phone"

### 2.1 `CMakeLists.txt`

```cmake
set(LINPHONEAPP_APPLICATION_NAME "NP Phone" CACHE STRING "Application name" )
```

The executable name stays `linphone` **on purpose**: the bundle ID
(`com.belledonnecommunications.linphone`) and all user data paths
(`~/Library/Preferences/linphone/`, Application Support) are derived from it,
so existing installs keep their accounts/history across the rename.

### 2.2 `cmake/install/install.cmake` — bundle/application name split fix

Upstream bug exposed by the rename: the executable bundle target installs as
`${EXECUTABLE_NAME}.app` while every other component installs into
`${APPLICATION_NAME}.app`. Upstream this only works because "Linphone.app" and
"linphone.app" are the *same directory* on macOS's case-insensitive
filesystem. With a real rename the two trees split and the final app keeps a
stale `Info.plist`/executable. Add directly after the `install(TARGETS ...)`
block:

```cmake
if(APPLE)
	# The bundle target installs as ${EXECUTABLE_NAME}.app while every other component
	# installs into ${APPLICATION_NAME}.app. When the two names differ (beyond case),
	# merge the bundle (executable + Info.plist) into the application tree.
	string(TOLOWER "${APPLICATION_NAME}" _app_name_lower)
	string(TOLOWER "${EXECUTABLE_NAME}" _exe_name_lower)
	if(NOT _app_name_lower STREQUAL _exe_name_lower)
		install(CODE "
			file(COPY \"${CMAKE_INSTALL_PREFIX}/${EXECUTABLE_NAME}.app/Contents\" DESTINATION \"${CMAKE_INSTALL_PREFIX}/${APPLICATION_NAME}.app\")
			file(REMOVE_RECURSE \"${CMAKE_INSTALL_PREFIX}/${EXECUTABLE_NAME}.app\")
		")
	endif()
endif()
```

> When renaming an *existing* build tree, also pass
> `-DLINPHONEAPP_APPLICATION_NAME="NP Phone"` at reconfigure (it's a CACHE
> variable — editing the default alone does not update an existing cache), and
> expect one forced relink (`touch Linphone/main.cpp`) so the bundle picks up
> the regenerated `Info.plist`. Fresh builds need none of this.

### 2.3 App icon — `cmake/install/macos/linphone.icns`

Replaced with custom artwork: the circular nurse illustration from
`NursePhone.png` (kept at repo root as the source asset), composited onto a
red (`#C8102E`) rounded-square plate in standard macOS Big Sur icon geometry
(1024 canvas, 824 plate, 185 corner radius; badge ≈ 660px), exported at all
required sizes (16–1024 @1x/@2x) and packed with `iconutil -c icns`.
Regeneration script outline (Python/Pillow): auto-detect the illustration's
bounding box, crop to a circle, paste onto the rounded-rect plate, emit an
`.iconset`, run `iconutil`. The install pipeline copies this file into the
bundle as `Resources/linphone.icns` (referenced by `CFBundleIconFile`).

### 2.4 Runtime Dock icon — `Linphone/data/image/logo.svg`

The bundle `.icns` only covers Finder and the Dock while the app is closed:
at startup the app calls `setWindowIcon(QIcon(":/data/image/logo.svg"))`
(`App.cpp`), which repaints the running Dock tile with the embedded Linphone
logo. `logo.svg` is replaced with an SVG wrapper embedding the same
nurse-on-red artwork as a base64 PNG
(`<svg ...><image href="data:image/png;base64,..."/></svg>`), so the running
Dock tile, notifications, and in-app logo usages all match the bundle icon.

### 2.5 Brand color theme — `Linphone/view/Style/Themes.qml`

The left navigation bar and all primary accents derive from the app's theme
system: `[ui] theme_main_color` selects a palette in `Themes.qml`, and
`DefaultStyle.main1_*` map to its shades. Added a `catapult` palette built
around Catapult Health's brand navy `#1B365D` (the catapulthealth.com
"Request a Demo" button color — their CSS overrides Bootstrap's
`.btn-outline-primary` with it):

```qml
// Catapult Health brand navy (catapulthealth.com "Request a Demo" button)
"catapult": {
    "main100": "#D8E2EF",
    "main200": "#9FB3CE",
    "main300": "#6C87AD",
    "main500": "#1B365D",
    "main600": "#142946",
    "main700": "#0E1E33"
},
```

Selected via `theme_main_color=catapult` in the factory config (§1). The
brand's secondary sky blue `#3799CA` is the natural alternative if the navy
reads too dark.

## 3. App code changes (C++)

### 3.1 `Linphone/model/setting/SettingsModel.cpp` — honor `/readonly` locks

The chat/meetings feature flags ignored the config `/readonly` mechanism, so a
user-writable `linphonerc` could re-enable them. Replace the macro-generated
accessors for `disable_chat_feature` with explicit ones, and update the
meetings accessors:

```cpp
bool SettingsModel::getDisableChatFeature() const {
    mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
    return !!mConfig->getBool(UiSection, getEntryFullName(UiSection, "disable_chat_feature"), false);
}
void SettingsModel::setDisableChatFeature(const bool &data) {
    if (isReadOnly(UiSection, "disable_chat_feature")) return;
    if (getDisableChatFeature() != data) {
        mConfig->setBool(UiSection, "disable_chat_feature", data);
        emit disableChatFeatureChanged(data);
    }
}
```

(The `DEFINE_GETSET_CONFIG(SettingsModel, bool, Bool, disableChatFeature, ...)`
line is removed.) Same treatment for meetings:

```cpp
void SettingsModel::setDisableMeetingsFeature(bool value) {
    if (isReadOnly(UiSection, "disable_meetings_feature")) return;
    mConfig->setBool(UiSection, "disable_meetings_feature", value);
    emit disableMeetingsFeatureChanged();
}
bool SettingsModel::getDisableMeetingsFeature() const {
    return !!mConfig->getInt(UiSection, getEntryFullName(UiSection, "disable_meetings_feature"), 0);
}
```

### 3.2 `Linphone/model/tool/ToolModel.cpp` — two changes

**a) Never negotiate video.** In `ToolModel::createCall`, audio-only calls
used `RecvOnly` video direction, which still permits inbound video
negotiation. When core video is disabled, use `Inactive`:

```cpp
auto videoDirection = localVideoEnabled      ? linphone::MediaDirection::SendRecv
                      : core->videoEnabled() ? linphone::MediaDirection::RecvOnly
                                             : linphone::MediaDirection::Inactive;
```

**b) Match contacts saved as phone numbers.** `findFriendByAddress` only
matched contacts by exact SIP address, so a contact stored with a phone number
(vCard TEL — the common case) was never recognized, and calls displayed the
bare number instead of the contact name. In
`ToolModel::findFriendByAddress(const std::shared_ptr<const linphone::Address>&)`,
after `core->findFriend(linphoneAddr)` fails:

```cpp
if (!f) {
    // Contacts saved with only a phone number never match by SIP address:
    // try the username as a phone number before giving up
    auto username = linphoneAddr->getUsername();
    if (!username.empty() && username.find_first_not_of("+0123456789") == std::string::npos) {
        f = CoreModel::getInstance()->getCore()->findFriendByPhoneNumber(username);
    }
}
```

Every name-display path funnels through this helper, so contact names now
appear in the call window, avatar, history, and conference tiles.

### 3.3 `Linphone/core/participant/ParticipantDeviceCore.cpp` — conference tile names

Conference participant tiles were labeled with the *device* contact address
(behind a PBX this is a meaningless `sip:<pbx-ip>:5060`). Prefer the
participant identity, which resolves to contact-list name → SIP display name →
dialed number. In the constructor:

```cpp
auto participant = device->getParticipant();
auto participantAddress = participant ? participant->getAddress() : nullptr;
mDisplayName = Utils::coreStringToAppString(participantAddress ? participantAddress->getDisplayName() : "");
if (mDisplayName.isEmpty()) {
    // Prefer the participant identity (contact name or dialed number) over the device
    // contact address, which may be a meaningless PBX address
    mDisplayName = ToolModel::getDisplayName(participantAddress ? participantAddress : deviceAddress);
}
```

### 3.4 `Linphone/core/participant/ParticipantDeviceProxy.cpp` — local tile duplicated in conference grid

Upstream bug: the conference grid expects the local ("me") device sorted to
index 0, where it overlays the local camera preview and account label. The
sort comparator keyed the "me" test on the *right* operand, producing a
self-contradictory ordering ("me" both first and last), so "me" landed in a
random slot: a remote participant's tile got masked by the local "9102"
overlay and the local device appeared a second time. In
`ParticipantDeviceProxy::SortFilterList::lessThan`:

```cpp
	// "me" must always sort first: the grid overlays the local preview on index 0.
	// (Keying this off the right operand made the ordering self-contradictory and
	// left "me" in a random slot, duplicating the local tile.)
	return l->isMe() || (!r->isMe() && sourceLeft.row() < sourceRight.row());
```

(upstream had `r->isMe() || ...`).

## 4. App UI changes (QML)

### 4.1 `Linphone/view/Control/Display/Sticker.qml` — remove SIP-URI line

In the in-call center display (the ColumnLayout that shows the caller name
below the avatar), **delete the second `Text` element** that renders
`mainItem.call.core.remoteAddress` (the `sip:number@domain` line). The name
line above it remains.

### 4.2 `Linphone/view/Control/Display/Contact/Avatar.qml` — full phone number in avatar

Numeric display names rendered as a single initial (e.g. "9"). Show
phone-number names in full, on one line, auto-shrunk to fit any circle size.
In the `initials` component's `Rectangle`:

```qml
Rectangle {
    id: initialItem
    property string shownName: mainItem.displayNameVal
    // Phone-number names are displayed in full instead of as a single initial
    property bool isPhoneNumber: /^\+?\d[\d\s.()-]*$/.test(shownName)
    property string initials: mainItem.isConference
        ? ""
        : isPhoneNumber
            ? shownName
            : (shownName && shownName[0] === "+") ? "" : UtilsCpp.getInitials(shownName)
    ...
    Text {
        anchors.fill: parent
        anchors.margins: initialItem.isPhoneNumber ? initialItem.width / 8 : 0
        ...
        // Plain text and no wrapping for phone numbers: fit them on a single line
        textFormat: initialItem.isPhoneNumber ? Text.PlainText : Text.RichText
        wrapMode: Text.NoWrap
        fontSizeMode: initialItem.isPhoneNumber ? Text.Fit : Text.FixedSize
        minimumPixelSize: 6
        ...
    }
}
```

(`Text.PlainText` matters: `RichText` word-wraps regardless of `wrapMode`,
which broke numbers across three lines in small list avatars.)

Also change the mid-call rename handler so it flows through the same logic:

```qml
Connections {
    target: mainItem.call?.core ? mainItem.call.core : null
    onRemoteNameChanged: initialItem.shownName = mainItem.call.core.remoteName
}
```

### 4.3 `Linphone/view/Page/Window/Call/CallsWindow.qml` — in-call workflow

Four changes:

**a) Screen-sharing button gated on video** (it only checked for a conference):

```qml
visible: !!mainWindow.conference && SettingsCpp.videoEnabled
```

**b) Embedded sidebar: call list + DTMF dialer inside the in-call view.**
Replace the `inCallItem` component's body. `CallLayout` anchors to the sidebar
when visible; the sidebar is a 300px `ColumnLayout` in the top-right with a
`CallListView` card and a `NumericPad` card below it:

```qml
Component {
    id: inCallItem
    Loader {
        objectName: "inCallItem"
        asynchronous: true
        sourceComponent: Item {
            CallLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: embeddedSidebar.visible ? embeddedSidebar.left : parent.right
                anchors.leftMargin: Utils.getSizeWithScreenRatio(20)
                anchors.rightMargin: rightPanel.visible || embeddedSidebar.visible ? 0 : Utils.getSizeWithScreenRatio(10)
                anchors.topMargin: Utils.getSizeWithScreenRatio(10)
                call: mainWindow.call
                callTerminatedByUser: mainWindow.callTerminatedByUser
            }
            // Call list and dialer embedded in the in-call view
            ColumnLayout {
                id: embeddedSidebar
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Utils.getSizeWithScreenRatio(10)
                anchors.rightMargin: Utils.getSizeWithScreenRatio(10)
                width: Utils.getSizeWithScreenRatio(300)
                visible: !rightPanel.visible
                spacing: Utils.getSizeWithScreenRatio(10)
                RoundedPane {
                    id: embeddedCallListPane
                    Layout.fillWidth: true
                    visible: embeddedCallList.contentHeight > 0
                    leftPadding: Utils.getSizeWithScreenRatio(16)
                    rightPadding: Utils.getSizeWithScreenRatio(6)
                    topPadding: Utils.getSizeWithScreenRatio(15)
                    bottomPadding: Utils.getSizeWithScreenRatio(16)
                    contentItem: CallListView { id: embeddedCallList }
                }
                // DTMF dialer, always at hand during a call
                RoundedPane {
                    id: embeddedDialerPane
                    Layout.fillWidth: true
                    leftPadding: Utils.getSizeWithScreenRatio(16)
                    rightPadding: Utils.getSizeWithScreenRatio(16)
                    topPadding: Utils.getSizeWithScreenRatio(15)
                    bottomPadding: Utils.getSizeWithScreenRatio(16)
                    contentItem: Item {
                        implicitHeight: embeddedNumPad.height
                        NumericPad {
                            id: embeddedNumPad
                            anchors.horizontalCenter: parent.horizontalCenter
                            currentCall: callsModel.currentCall
                            lastRowVisible: false
                        }
                    }
                }
            }
        }
    }
}
```

**c) Merge button replaces the call-list toggle** in the bottom button bar
(the embedded list made the toggle redundant). Replace the `callListButton`
`CheckableButton` with:

```qml
// Merge calls button
CheckableButton {
    id: mergeCallsButton
    Layout.preferredWidth: Utils.getSizeWithScreenRatio(55)
    Layout.preferredHeight: Utils.getSizeWithScreenRatio(55)
    // callsModel filters out the current call (showCurrentCall is false), so add it back when counting
    enabled: (callsModel.count + (callsModel.currentCall ? 1 : 0)) >= 2 && !callsModel.haveNonAdminMeeting
    icon.source: AppIcons.arrowsMerge
    icon.width: Utils.getSizeWithScreenRatio(32)
    icon.height: Utils.getSizeWithScreenRatio(32)
    //: call_action_merge_calls
    ToolTip.text: qsTr("Merger tous les appels")
    Accessible.name: qsTr("Merger tous les appels")
    onClicked: callsModel.lMergeAll()
    KeyNavigation.tab: mainWindow.startingCall ? nextItemInFocusChain() : endCallButton
}
```

Update the two references to the old id: the `KeyNavigation.backtab` chain that
pointed at `callListButton` now points at `mergeCallsButton`, and the
`callListButton.checked = false` sync line in `rightPanel`'s `onItemChanged`
handler is deleted.

> Note the enabled-count workaround: the window-level `CallProxy` (`callsModel`)
> excludes the current call from `count` because `showCurrentCall` defaults to
> false. The upstream merge popup used `callsModel.count >= 2` and therefore
> effectively required *three* calls — a latent upstream bug.

**d) DTMF dialer button** added to `connectedCallButtons` (before the pause
button) — kept even with the embedded dialer, opens the full-size dialer panel:

```qml
// Dialer (DTMF) button
CheckableButton {
    id: dialerButton
    Layout.preferredWidth: Utils.getSizeWithScreenRatio(55)
    Layout.preferredHeight: Utils.getSizeWithScreenRatio(55)
    checkable: true
    icon.source: AppIcons.dialer
    icon.width: Utils.getSizeWithScreenRatio(32)
    icon.height: Utils.getSizeWithScreenRatio(32)
    //: "Afficher le pavé numérique"
    ToolTip.text: qsTr("call_action_show_dialer")
    Accessible.name: qsTr("call_action_show_dialer")
    onToggled: {
        if (checked) {
            rightPanel.visible = true
            rightPanel.replace(dialerPanel)
        } else {
            rightPanel.visible = false
        }
    }
}
```

Plus its checked-state sync in `rightPanel`'s `onItemChanged`:

```qml
if (!rightPanel.contentLoader.item || rightPanel.contentLoader.item.objectName !== "dialerPanel") dialerButton.checked = false
```

## 5. SDK patch (linphone-sdk submodule)

**File: `external/linphone-sdk/liblinphone/src/conference/server-conference.cpp`**

**Problem:** merging two calls that traverse the same PBX/B2BUA fails. Both
legs present the identical Contact header (e.g. `sip:<pbx-ip>:5060`, no user
part). The conference dedupes participant devices by Contact URI, decides the
second call is the first device "reconnecting", and **terminates the first
call** (log: "…Terminating the latter").

**Fix:** in `addParticipant`, after `findParticipantDevice(remoteContactAddress)`,
only treat the match as a reconnection if the remote *identity* also matches:

```cpp
if (participantDevice) {
    // A PBX/B2BUA may present the same Contact address for unrelated call legs. Only treat the found
    // device as a reconnection of the same device if the remote identity also matches, otherwise
    // consider the new session as a distinct device of a distinct participant.
    const auto &deviceParticipant = participantDevice->getParticipant();
    const auto &callRemoteAddress = call->getRemoteAddress();
    if (deviceParticipant && callRemoteAddress &&
        !deviceParticipant->getAddress()->weakEqual(callRemoteAddress)) {
        lInfo() << "Found " << *participantDevice << " matching contact address " << *remoteContactAddress
                << " but it belongs to another participant, therefore considering session " << *session
                << " as a distinct participant device";
        participantDevice = nullptr;
    }
}
if (participantDevice) {
    // ... existing terminate-and-replace logic unchanged ...
```

⚠️ This lives in the **submodule**, so any `git submodule update` silently
discards it. It is carried in this repo as
**`patches/sdk-server-conference-pbx-contact.patch`** (commit `d4dd5d787`) and
must be re-applied after every submodule update, **before** building:

```bash
git -C external/linphone-sdk/liblinphone apply ../../../patches/sdk-server-conference-pbx-contact.patch
git -C external/linphone-sdk status --short   # expect: M liblinphone/src/conference/server-conference.cpp
```

Verified to apply cleanly on SDK 5.5.16 (`4bb4159ac`).

## 6. Build environment (Apple Silicon macOS)

Tested on macOS 26 / arm64 with **Command Line Tools only** (no full Xcode —
enabled by the toolchain patch below).

```bash
# Tools
brew install cmake ninja nasm yasm doxygen meson ccache

# SDK code generators need these in the Python that CMake's FindPython3 picks
# (usually Homebrew's):
/opt/homebrew/bin/python3 -m pip install --break-system-packages pystache six

# Qt 6.10+ for macOS (arm64), no Qt account needed:
python3 -m venv ~/.linphone-build-venv
~/.linphone-build-venv/bin/pip install aqtinstall
~/.linphone-build-venv/bin/aqt install-qt mac desktop 6.10.3 clang_64 \
    -m qtnetworkauth qtshadertools -O ~/Qt
```

### 6.1 `cmake/toolchains/toolchain-mac-common.cmake` — CLT fallback

Upstream hard-requires `xcrun --show-sdk-platform-path`, which only full Xcode
provides. Replace that block with a fallback to the CLT SDK path:

```cmake
execute_process(COMMAND xcrun --sdk macosx --show-sdk-platform-path
	RESULT_VARIABLE XCRUN_SHOW_SDK_PATH_RESULT
	OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
	OUTPUT_STRIP_TRAILING_WHITESPACE
	ERROR_QUIET
)
if(${XCRUN_SHOW_SDK_PATH_RESULT} EQUAL 0)
	set(CMAKE_OSX_SYSROOT "${CMAKE_OSX_SYSROOT}/Developer/SDKs/MacOSX.sdk")
else()
	# Command Line Tools without full Xcode have no platform path; use the SDK path directly
	execute_process(COMMAND xcrun --sdk macosx --show-sdk-path
		RESULT_VARIABLE XCRUN_SHOW_SDK_PATH_RESULT
		OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
		OUTPUT_STRIP_TRAILING_WHITESPACE
	)
	if(NOT ${XCRUN_SHOW_SDK_PATH_RESULT} EQUAL 0)
		message(FATAL_ERROR "xcrun failed: ${XCRUN_SHOW_SDK_PATH_RESULT}. You may need to install Xcode.")
	endif()
endif()
```

### 6.2 Build

The authoritative, step-by-step from-scratch procedure (including the
single-view layer and the fleet release) is in
**`docs/single-view/README.md` → "Reproducing the app and deployment from
scratch"**. Summary of the fork-specific points:

```bash
git clone https://github.com/frank3427ch/linphone-desktop.git && cd linphone-desktop
git checkout simple
# bc_compute_full_version needs a 6.3.x tag reachable from HEAD; the fork's own
# tags stop at 6.2.0-beta:
git fetch https://github.com/BelledonneCommunications/linphone-desktop.git \
    refs/tags/6.3.0-alpha:refs/tags/6.3.0-alpha
# external/feature-specs is a PRIVATE BC submodule (Squish specs only): skip it.
git submodule update --init --recursive -- external/linphone-sdk
# gitlab.linphone.org is flaky; re-run until clean, then force-checkout —
# interrupted clones can leave submodule worktrees EMPTY while reporting clean:
git submodule update --init --recursive --force -- external/linphone-sdk
git submodule foreach --recursive --quiet 'test -n "$(ls)" || echo "EMPTY: $displaypath"'
# SDK patch (§5) — AFTER every submodule update, BEFORE building:
git -C external/linphone-sdk/liblinphone apply "$PWD/patches/sdk-server-conference-pbx-contact.patch"

export Qt6_DIR="$HOME/Qt/6.10.3/macos/lib/cmake/Qt6"
export PATH="$HOME/Qt/6.10.3/macos/bin:$PATH"

mkdir build && cd build
cmake .. -DLINPHONEAPP_MACOS_ARCHS=arm64 \
         -DCMAKE_BUILD_PARALLEL_LEVEL=10 \
         -DCMAKE_BUILD_TYPE=RelWithDebInfo \
         -DENABLE_APP_PACKAGING=OFF
cmake --build . --parallel 10 --config RelWithDebInfo
```

- `-DLINPHONEAPP_MACOS_ARCHS=arm64` skips the x86_64 half (default is a
  universal build; each arch rebuilds the entire SDK).
- `-DENABLE_APP_PACKAGING=OFF`: the CPack DragNDrop DMG step drives Finder via
  AppleScript and dies headless (AppleEvent timeout -1712). The fleet is
  deployed as a bare `.app` via Ansible, so the DMG is not needed. (With
  packaging ON the `.app` is still complete before the DMG step fails.)
- First build compiles the whole SDK (~2 h); later builds are incremental.
- Output: app bundle at **`build/OUTPUT/macos/NPPhone.app`** (bundle folder is
  the space-stripped `LINPHONEAPP_BUNDLE_NAME` — libvpx's Makefile build
  word-splits install paths with spaces; Finder/Dock show "NP Phone" via
  `CFBundleDisplayName`).
- Optional hardening: add `-DENABLE_VIDEO=OFF` to compile video support out of
  the SDK entirely (cascades to `ENABLE_OPENH264`, `ENABLE_SCREENSHARING`).

### 6.3 Deploy

Local test install:

```bash
rm -rf /Applications/NPPhone.app && cp -R build/OUTPUT/macos/NPPhone.app /Applications/
```

Fleet: the bundle is committed as `bins/NPPhone.app` in the
`ansible-npstations` repo and pushed by `playbook2.yml --tags linphone`, which
also renders the per-station `linphonerc` (SIP account + `[ui] speed_dial_N`).
See `docs/single-view/README.md` for the release steps.

The build is **ad-hoc signed** — the playbook clears the quarantine xattr on
each station. For distribution outside the managed fleet: sign with a Developer
ID Application certificate
(`-DLINPHONE_BUILDER_SIGNING_IDENTITY="Developer ID Application: ..."`),
notarize (`xcrun notarytool submit --wait`), staple, then push via MDM.

## 7. Deliberately NOT changed

- Executable name, bundle ID, and user data paths (`linphone`) — kept so the
  rebrand does not orphan existing accounts/history (§2.1).
- Chat/meeting QML files are still compiled into the binary — hidden by
  feature flags, not removed from the build.
- Video codecs remain in the SDK binary unless `-DENABLE_VIDEO=OFF` is used.
- `ToolModel::createConference` still requests video/chat capabilities;
  liblinphone auto-downgrades both for locally hosted conferences (harmless
  log warnings).

## 8. Caveats & operational notes

1. **SRTP is mandatory** — the PBX must accept SRTP or every call is aborted
   after the SDP answer ("Remote offered no encryption but the local core can
   only support encrypted calls"). To prefer-but-not-require, drop
   `media_encryption_mandatory=1`. With SDES-SRTP over UDP signaling, keys
   travel in cleartext SDP — use SIP-over-TLS for real confidentiality.
2. **Factory settings are defaults** for keys without `/readonly`: an existing
   user `linphonerc` (`~/Library/Preferences/linphone/linphonerc`) overrides
   them. The chat/meetings locks use `/readonly` and always win; the `[video]`,
   `[sip]`, and `hide_sip_addresses` keys do not. On machines with prior
   Linphone use, clear the old user config.
3. Known bad user-config state seen in the field:
   `media_encryption=none` + `media_encryption_mandatory=1` rejects **all**
   calls. The settings UI can produce this combination.
4. The old call-list side panel and its translations still exist; only its
   bottom-bar toggle was replaced by the merge button.
5. `lastActiveTabIndex` is stored in QSettings (not linphonerc); a stale index
   is guarded by a fallback to tab 0 in `MainLayout.qml`.

## 9. File-by-file summary

| File | Change |
|---|---|
| `CMakeLists.txt` | Application name "NP Phone" (executable stays `linphone`) |
| `cmake/install/install.cmake` | Merge executable bundle into application tree when names differ (case-insensitivity bug) |
| `cmake/install/macos/linphone.icns` | Custom app icon: NursePhone badge on red rounded square |
| `Linphone/data/image/logo.svg` | Runtime Dock/notification logo replaced with same artwork |
| `Linphone/view/Style/Themes.qml` | `catapult` palette (brand navy #1B365D ramp) |
| `NursePhone.png` (repo root) | Source artwork for the app icon |
| `cmake/toolchains/toolchain-mac-common.cmake` | Build with Command Line Tools (no full Xcode) |
| `Linphone/data/config/linphonerc-factory` | Voice-only policy: chat/meetings locked off (readonly), SIP addresses hidden, video disabled, SRTP mandatory |
| `Linphone/model/setting/SettingsModel.cpp` | `disable_chat_feature` / `disable_meetings_feature` honor `/readonly` locks |
| `Linphone/model/tool/ToolModel.cpp` | Video direction `Inactive` when video disabled; contacts matched by phone number, not just SIP address |
| `Linphone/core/participant/ParticipantDeviceCore.cpp` | Conference tiles named by participant identity, not PBX device address |
| `Linphone/core/participant/ParticipantDeviceProxy.cpp` | Fixed self-contradictory sort so the local tile appears exactly once (index 0) in conference grid |
| `Linphone/view/Control/Display/Sticker.qml` | Removed `sip:` URI line from in-call display |
| `Linphone/view/Control/Display/Contact/Avatar.qml` | Full phone number (single line, auto-fit) in avatar circle for numeric names |
| `Linphone/view/Page/Window/Call/CallsWindow.qml` | Screenshare gated on video; embedded call list + DTMF dialer sidebar; merge button (with count fix) replaces call-list toggle; dialer button in bottom bar |
| `external/linphone-sdk` → `liblinphone/src/conference/server-conference.cpp` | Don't kill an existing call when a PBX reuses one Contact address for multiple legs |
