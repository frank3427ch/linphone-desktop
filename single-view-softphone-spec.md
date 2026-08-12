# Single-View Softphone — Product & Technical Specification

**Base:** Fork of `linphone-desktop` (Linphone 6.x, Qt6/QML + liblinphone SDK)
**Version:** Draft 0.1
**Audience:** Support agents who dial a client and an expert, then merge the calls

---

## 1. Purpose

A purpose-built desktop softphone with exactly one window, one fixed theme, and one view. No navigation, no chat, no contacts directory, no meetings, no settings maze. The agent can register, dial, manage up to N concurrent calls, and merge them into a local audio conference in under three clicks.

## 2. Goals

- Single fixed window (~400×720 px, resizable vertically only) containing all functionality.
- One hardcoded theme (company palette), no light/dark switching.
- Support the core workflow: call client → place on hold → call expert → merge into 3-way conference → manage → tear down.
- Zero-configuration for the agent: SIP account and media settings arrive via remote provisioning.
- Deployable and updatable through existing endpoint tooling (Ansible / standard Windows installer).

## 3. Non-Goals

- No instant messaging, presence, video, meetings/scheduling, contact management, call recording UI, or multi-account support.
- No user-editable settings beyond audio device selection and mic/speaker test.
- No server-side conferencing (the merge is a local liblinphone conference on the agent machine). Revisit if scale or recording requirements change.

## 4. Functional Requirements

| ID | Requirement |
|----|-------------|
| FR-1 | App registers a single SIP account on launch using provisioned credentials; shows live registration state. |
| FR-2 | Agent can place an outbound call by entering a number/SIP URI or tapping the dial pad. |
| FR-3 | Incoming calls ring and can be answered or declined from the same view. |
| FR-4 | Each active call is shown as a card with caller identity, duration, and state (active / on hold / ringing / paused by remote). |
| FR-5 | Per-call controls: hold/resume, mute, send DTMF (dial pad routes to active call while a call exists), hang up. |
| FR-6 | With ≥2 calls, a "Merge calls" action creates a local conference containing all current calls. |
| FR-7 | In conference: show participant list; allow removing one participant or ending the conference (which ends all legs). |
| FR-8 | Blind transfer of a single call to an entered address. (Attended transfer optional, phase 2.) |
| FR-9 | Audio input/output/ringer device selection persists across restarts; hot-plug (headset unplug) is handled gracefully. |
| FR-10 | Codec priorities, STUN/TURN/ICE, and encryption (TLS + SRTP/ZRTP) come from provisioning, not the UI. |
| FR-11 | Window cannot navigate away from the main view; only modal is the audio-device picker. |
| FR-12 | Verbose logging toggleable via config file (not UI) for troubleshooting; logs land in a known path for collection. |

## 5. UI Specification (matches approved mockup)

One vertical column, five fixed regions, top to bottom:

1. **Header / status strip** — registration dot (green registered, amber registering, red failed), account identity, nothing clickable except a retry on failure.
2. **Call stack** — zero or more call cards. Empty state shows a subtle "No active calls" hint. Cards ordered by creation. Active call has an accent border; held calls are visually muted. Incoming call renders as a card with Answer / Decline replacing the normal controls.
3. **Merge bar** — appears only when ≥2 calls exist and no conference is active. Becomes the conference card (participant list + per-participant remove + "End conference") once merged.
4. **Dialer** — text field + 12-key pad + Call button. Behavior is modal on state: with a connected call focused, keys send DTMF; otherwise they compose a new destination. A small label indicates the current mode to avoid surprises.
5. **Footer** — current audio device name, opens the device picker modal; mic level meter optional.

Theme: hardcoded palette in the QML style singleton; monochrome SVG icons recolored to the palette; single font family. Remove all theme-switch plumbing rather than defaulting it.

## 6. Call State Model

Per call: `Idle → OutgoingRinging | IncomingRinging → Connected → (Paused ⇄ Connected) → Terminated`. Conference is a separate object owning N calls; entering it forces all member calls to the conference's media session. UI derives entirely from liblinphone state callbacks — never from optimistic local state — so the cards can't desync from the stack.

## 7. Control → liblinphone API Mapping

All calls go through the app's existing `core/` bridge classes (which marshal to the SDK thread); the underlying SDK operations are:

| UI control | liblinphone operation |
|---|---|
| Register on launch | `Core::addAccount()` from provisioned `AccountParams`; observe `Account` registration state callbacks |
| Call button | `Core::createAddress()` → `Core::inviteAddressWithParams()` |
| Answer / Decline | `Call::accept()` / `Call::decline(Reason::Declined)` |
| Hang up | `Call::terminate()` |
| Hold / Resume | `Call::pause()` / `Call::resume()` |
| Mute | `Call::setMicrophoneMuted(bool)` (per-call; core-level `Core::setMicEnabled` mutes everything) |
| DTMF key | `Call::sendDtmf(char)` on the focused connected call |
| Merge calls | `Core::createConferenceWithParams()` (audio-only `ConferenceParams`) → `Conference::addParticipant(call)` for each call, or the convenience `Core::addAllToConference()` |
| Remove participant | `Conference::removeParticipant()` |
| End conference | `Conference::terminate()` |
| Blind transfer | `Call::transferTo(address)` |
| Attended transfer (P2) | `Call::transferToAnother(otherCall)` |
| Device picker | `Core::getExtendedAudioDevices()`; set via `Core::setDefaultInputAudioDevice` / `setDefaultOutputAudioDevice` and per-call `Call::setOutputAudioDevice()` |

Verify exact signatures against the SDK version pinned by the fork's submodule — the C++ wrapper occasionally renames between minor versions. Treat the app's `core/call/` and `core/conference/` classes as the reference for current usage patterns.

## 8. Implementation Plan (against the fork)

**Reuse, don't rewrite.** The MVVM split means the `model/` and `core/` layers need almost no changes — the work is concentrated in `view/`.

1. **New main page.** Create `view/Page/SingleView/MainPanel.qml` composing existing `Item/` widgets (buttons, avatars, call timer, status dot). Bind the call stack to the existing call-list core model.
2. **Replace the shell.** In the `App/` window-management QML, replace the StackView/navigation shell with a fixed loader of `MainPanel.qml`. Delete route handling for chat, meetings, contacts, and settings pages. Disable creation of secondary windows (call pop-out, chat windows).
3. **Dialer modality.** Small QML state machine: `hasFocusedConnectedCall ? sendDtmf(key) : appendToDestination(key)`.
4. **Merge/conference card.** Reuse the existing conference UI fragments if the current app has a usable audio-conference view; otherwise a simple ListView over the conference participant model.
5. **Theme.** Hardcode palette in the style/DesignSystem singleton under `view/`; strip theme-switch settings and the unused icon color variants.
6. **Prune at QML level first.** Leave unused C++ core classes in place initially (they cost little); remove them only in a later cleanup pass if size or startup time matters. This keeps early diffs small and rebases against upstream feasible.
7. **Build flags:** `-DENABLE_APP_PDF_VIEWER=NO -DENABLE_APP_WEBVIEW=NO -DENABLE_UPDATE_CHECK=NO -DENABLE_BUILD_APP_PLUGINS=NO`.

## 9. Provisioning & Configuration

- Ship a minimal factory `linphonerc` in the package with only UI-invariant defaults and the remote-provisioning URI.
- Host the real provisioning file (SIP account template, transports=TLS, media encryption, codec order: OPUS > PCMU/PCMA, ICE/STUN/TURN servers) on an internal HTTPS endpoint; per-agent credentials injected at deploy time via Ansible template or fetched with per-user auth.
- No secrets in the installer. Config path and log path documented for support tooling.

## 10. Packaging & Deployment

- Windows: `-DENABLE_APP_PACKAGING=YES`, sign the installer, deploy via existing endpoint management.
- Pin fork to an upstream release tag; schedule upstream rebases ~2×/year for SDK security fixes. Keep the diff surface small (mostly `view/`) to make rebases cheap.
- CI: build on a Windows runner with cached SDK build (the SDK superbuild is the long pole; cache it aggressively).

## 11. Acceptance Criteria

- AC-1: Fresh install on a clean Windows machine registers within 10 s using only the provisioning URL.
- AC-2: Client call → hold → expert call → merge completes in ≤3 clicks after the second call connects, and both remote parties hear each other.
- AC-3: Removing the expert from the conference leaves the client leg connected with two-way audio.
- AC-4: Pulling the USB headset mid-call falls back to another device without dropping the call.
- AC-5: DTMF sent from the pad is received by an IVR test number during an active call.
- AC-6: No user path exists to any screen other than the main view and the device-picker modal.
- AC-7: App survives 8-hour registration with keep-alives and re-registers automatically after network loss.

## 12. Milestones

| Milestone | Scope | Estimate |
|---|---|---|
| M0 | Stock build green on target OS, registered against prod-like SIP server | 1–2 days |
| M1 | Architecture map + this spec signed off | 2–3 days |
| M2 | Single view functional: dial, answer, hold, mute, hang up | 1 week |
| M3 | Merge/conference + transfer + DTMF modality | 3–5 days |
| M4 | Theme hardcoded, navigation fully removed, device picker | 3 days |
| M5 | Provisioning + packaging + signed installer + CI | 3–5 days |
| M6 | Pilot with 2–3 agents, fix list, GA | 1–2 weeks |

## 13. Risks

- **SDK API drift** between the pinned tag and docs — mitigate by reading the app's own `core/` usage as ground truth.
- **Local-conference audio quality** depends on the agent machine and network; if agents are on marginal links, server-side mixing becomes necessary and this design should be revisited before M3.
- **License:** GPLv3 for internal use is fine; any distribution outside the company requires publishing the fork's source or a Belledonne commercial license. Flag to compliance owner before any external ship.
- **Upstream rebase cost** grows with diff size — enforce the "prune QML, keep core" discipline.
