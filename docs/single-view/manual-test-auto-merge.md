# NP Phone — Manual Test: Interpreter-First Auto-Merge

**Build under test:** NP Phone `6.3.0-alpha.70+b03740182` (linphone-desktop branch
`simple`), deployed 2026-08-28 to pilot stations **np-025** (ext 1525n),
**r-np-007** (ext 1607n), **np-050** (ext 1550n) and **np-051** (ext 1551n).

Fixes since the first pilot build (`.63`):
- `.65` — auto-merge did not fire (Propio went on hold, Merge had to be pressed). *(np-025)*
- `.66` — keyboard digits were typed into the dial field instead of being sent
  as tones, and tones stopped working once calls were merged (section 7b). *(np-025)*
- `.70` — same app code as `.66`, now **signed with a stable certificate**
  ("NP Phone Signing") instead of ad-hoc. Root cause of the r-np-007
  "voicemail could not hear me" report: each ad-hoc build re-asked for
  microphone access and a *Don't Allow* silenced the mic. **Expect the
  microphone prompt exactly once more** on first launch of this build (the
  signature changed); click **Allow** (step 0.1a). Later builds keep the grant.

**Feature under test:** when a call is already up and the agent dials another
number, the new leg is conferenced automatically while it is still ringing
(`[ui] singleview_auto_merge=1`, shipped default). Also covers the two
supporting additions in the same build: the **Ringing…** label on the
conference card and the conference **mute** button.

Record results in the Pass/Fail column of each test. Anything other than the
expected result is a Fail — note exactly what you saw.

---

## 0. Setup (once per station)

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 0.1 | Log in as the NP user (`catanp`) and open **NP Phone** from the Dock. | Single-view window (fixed width). Footer shows the audio device. No error banner at the top. |  |
| 0.1a | **Microphone prompt.** On the first launch of every new build macOS asks *"NP Phone would like to access the microphone"*. Click **Allow**. | Prompt accepted. If it was ever answered *Don't Allow*, the far end hears **silence** on every call (voicemail says "you have not left a message") — fix in *System Settings → Privacy & Security → Microphone → NP Phone: on*, or re-run the deploy (`--tags linphone`), which resets a denied grant so the prompt reappears. |  |
| 0.2 | Check the top of the panel. | Registration is **not** shown as failed (no red "registration failed" text). |  |
| 0.3 | Look above the number pad. | Two speed-dial buttons: **Propio** and **Patient Support**. (If they are missing, stop — provisioning did not land; see "Troubleshooting".) |  |
| 0.4 | Confirm the build. In Finder: `/Applications/NPPhone.app` → right-click → *Get Info* → Version. | `6.3.0-alpha.70+b03740182` |  |
| 0.5 | Have ready: (a) a headset on the station, (b) a **test "patient" phone** — a mobile with voicemail enabled whose number you know, (c) a second person or a second phone to act as an **incoming caller** for test 6. | — |  |

> The "interpreter" leg in these tests is the real Propio line (speed dial 1,
> 2147317178). If you'd rather not consume interpreter minutes, substitute any
> phone that will answer and stay on the line (e.g. a colleague's desk phone)
> and treat it as "the interpreter" throughout.

---

## 1. Core flow — interpreter first, then patient (patient answers)

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 1.1 | Press the **Propio** speed dial. | A call card appears for Propio; state goes Ringing → Connected. You hear the interpreter line. |  |
| 1.2 | With the interpreter connected, type the test patient's number on the keypad and press the green call button (or press Enter). | **No Merge press needed.** Within ~1 s the single Propio card is replaced by a **Conference** card listing two rows: *Propio* and *the patient number*. |  |
| 1.3 | Look at the patient's row. | A grey **Ringing…** label is shown next to the patient's name/number. Propio's row has no label. |  |
| 1.4 | Listen (and ask the interpreter what they hear). | You hear the patient's ringback. **The interpreter also hears the ringback** — they are *not* on hold and hear no hold music/silence. |  |
| 1.5 | Answer the test patient phone. | *Ringing…* disappears immediately. All three parties can hear each other **at once** — say "hello" from the patient phone the moment you answer; both the agent and the interpreter must hear it. |  |
| 1.6 | Check the buttons on the Conference card. | Header has a **mic** button and **End conference**. Each row has a **✕**. Below the card is **End all calls**. There is **no Merge button** visible. |  |
| 1.7 | Press **End conference**. | All legs hang up; the panel returns to the empty dialer. |  |

## 2. Core flow — patient goes to voicemail (the key scenario)

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 2.1 | Press **Propio** speed dial; wait for Connected. | Interpreter connected. |  |
| 2.2 | Dial the test patient number. **Do not answer** the patient phone. | Conference card with *Ringing…* on the patient row, as in test 1. |  |
| 2.3 | Let it ring through to voicemail. | The moment voicemail picks up, *Ringing…* disappears. **The interpreter hears the voicemail greeting from its first word** — confirm with the interpreter ("did you hear the greeting start?"). |  |
| 2.4 | After the beep, have the interpreter leave a short message in the target language; the agent also speaks a few words. | Both are recorded. |  |
| 2.5 | Hang up with **End all calls**. Then play back the voicemail on the patient phone. | The recording contains **both** the agent and the interpreter, with the interpreter audible from the start of the message (no cut-off beginning). |  |

## 3. Manual keypad dial vs. speed dial

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 3.1 | Dial the interpreter **manually on the keypad** (2147317178) instead of the speed dial; wait for Connected. | Connected. |  |
| 3.2 | Press the **Patient Support** speed dial (8555091211) as the "second party". | Auto-merge happens exactly as in 1.2–1.4: conference card, *Ringing…*, interpreter hears ringback. |  |
| 3.3 | Hang up with **End all calls** as soon as Patient Support answers (do not tie up their line). | Clean hang-up, empty dialer. |  |

## 4. Conference mute button

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 4.1 | Set up a conference (Propio + test patient, patient answered). | 3-way audio. |  |
| 4.2 | Press the **mic** button in the Conference card header. | Icon changes to the slashed mic. The agent's voice is **not** heard by the interpreter or the patient. The agent still hears both of them. |  |
| 4.3 | Press it again. | Icon returns to the normal mic; everyone hears the agent again. |  |
| 4.4 | End the conference. | Empty dialer. |  |

## 5. Remove one party, add another

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 5.1 | Set up a conference (Propio + test patient, answered). | 3-way audio. |  |
| 5.2 | Press the **✕** on the **patient's** row. | The patient's leg hangs up. The conference card remains with only *Propio*. Agent and interpreter still hear each other. |  |
| 5.3 | Dial the test patient again (or any second number). | **Auto-merge triggers again**: the new leg joins the existing conference with *Ringing…*; interpreter hears ringback. |  |
| 5.4 | Answer, confirm 3-way audio, then **End all calls**. | Empty dialer. |  |

## 6. Incoming call during a conference is NOT auto-merged

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 6.1 | Set up a conference (Propio + test patient, answered). | 3-way audio. |  |
| 6.2 | From the second phone, **call the station's extension** (1525n on np-025 / 1607n on r-np-007 / 1550n on np-050 / 1551n on np-051). | A separate **incoming call card** appears (Answer / Decline) **outside** the conference card. The conference is untouched — it does **not** gain a third row and the caller does **not** hear the conference. |  |
| 6.3 | Press **Decline** on the incoming card. | Incoming card disappears; conference audio was never interrupted. |  |
| 6.4 | Repeat 6.2, but press **Answer**. | The incoming caller is connected to the agent; the conference legs are placed on hold (the conference card stays visible). The new call has its own card with mute/hold/transfer/hang-up. |  |
| 6.5 | Hang up the answered call with its own red button. | Conference card remains; press **End all calls** to finish. |  |

## 7. Ringing leg that is never answered / is declined

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 7.1 | Propio connected → dial the test patient → **reject the call** from the patient phone (or let it time out **without** voicemail, e.g. a number with voicemail disabled). | The patient's row disappears from the conference card. *Propio* remains; agent and interpreter still hear each other. No error popup. |  |
| 7.2 | Press **End conference**. | Empty dialer. |  |

## 7b. Keypad tones (DTMF) — IVR menus

Propio's greeting asks for a language choice, so this is exercised on every
real call. Requires build `6.3.0-alpha.66` or later (fix `e0cb291a0`).

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 7b.1 | Press **Propio**; when the IVR asks for a choice, press the digit on the **physical keyboard** (number row, not the numeric keypad). | The label above the dial field reads the DTMF-mode text. The digit is **not** typed into the dial field; the IVR accepts it and moves on. |  |
| 7b.2 | On the next prompt, click the digit on the **on-screen pad** instead. | Same: IVR accepts it, nothing typed into the field. |  |
| 7b.3 | Dial the test patient (auto-merge). Once the patient has answered, from the patient phone say "press 5" — press **5** on the keyboard and then on the on-screen pad. | Both send a tone: the person on the patient phone hears a DTMF beep each time (the tone is sent to every leg, so the interpreter hears it too — that is expected). Nothing is typed into the field. |  |
| 7b.4 | Press **Hold** on… (not available in conference — skip) / For a *single* call: put the call on hold, press a digit. | On hold the dialer switches to compose mode and the digit **is** typed into the field (no tone). Resume → DTMF mode again. |  |
| 7b.5 | If an IVR still misreads digits: note whether the station uses the **built-in speakers and mic** rather than a headset. | Record it — the local key-tone playback can be picked up by an open mic and double-detected by the IVR; a headset avoids that. |  |

## 8. Regression — single calls still behave normally

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 8.1 | Dial the test patient only (no interpreter). Answer. | A normal single **call card** (mute / hold / transfer / hang-up). **No** conference card, no auto-merge. |  |
| 8.2 | Press **Hold**, then **Resume**. | Works as before. |  |
| 8.3 | Hang up. | Empty dialer. |  |
| 8.4 | Quit and relaunch NP Phone. | Registers again; speed dials still present. |  |

## 9. (Optional) Kill switch — manual merge behaviour

Only if a site needs the old behaviour; requires editing the station config.

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 9.1 | Quit NP Phone. Edit `~/Library/Preferences/linphone/linphonerc` and add `singleview_auto_merge=0` under `[ui]`. Relaunch. | App starts normally. |  |
| 9.2 | Propio connected → dial the patient. | **No** auto-merge: two separate call cards, Propio on hold, and a **Merge** button appears between them. |  |
| 9.3 | Press **Merge** while the patient is still ringing. | Conference card appears with *Ringing…*; behaves like test 1 from here. |  |
| 9.4 | Restore: remove the line (or set `=1`), relaunch. | Auto-merge is back (re-run 1.2). |  |

---

## Troubleshooting / what to capture on a failure

- **Speed dials missing (0.3):** provisioning didn't land. On the station,
  `~/Library/Preferences/linphone/linphonerc` must contain `[ui]` →
  `speed_dial_1=Propio|2147317178`. Re-run
  `ansible-playbook playbook2.yml --tags linphone_speeddial --limit <host>`.
- **No auto-merge (1.2):** check the same file for `singleview_auto_merge=0`
  (the user config overrides the factory default). Remove it and relaunch.
- **Interpreter on hold / hears silence (1.4):** means the merge happened
  late or not at all. Capture logs (below) and note the exact timing.
- **Logs:** enable in Settings (or add `logs_enabled=1` under `[ui]`), reproduce,
  then collect `~/Library/Application Support/linphone/logs/linphone1.log`.
  The merge shows up as `lMergeAll` / `local_group_call` lines followed by
  `addParticipant`; a ringing leg being accepted shows as
  `ServerConference … OutgoingRinging`.
- Always record: station name, build version (0.4), the numbers used, and the
  time of the failing step, so the log can be matched to it.

## Sign-off

| Station | Tester | Date | Tests 1–8 (incl. 7b) all Pass? | Notes |
|---|---|---|---|---|
| np-025 |  |  |  |  |
| r-np-007 |  |  |  |  |
| np-050 |  |  |  |  |
| np-051 |  |  |  |  |
