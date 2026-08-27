# Single-View Softphone — Operations Notes

This fork ("NP Phone") builds `linphone-desktop` into a single-view,
voice-only softphone. See `VOICE_ONLY_FORK.md` (repo root) for the full
voice-only policy (video/chat/meetings disabled at the config level) and
`single-view-softphone-spec.md` (repo root) for the product spec, including
the acceptance checklist in §11 (AC-1…AC-7) to run during pilot rollout.

## Config paths

| What | Path |
|---|---|
| Factory (shipped) config | `Contents/Resources/share/linphone/linphonerc-factory` inside the app bundle |
| User config (writable, overrides factory) | `~/Library/Preferences/linphone/linphonerc` |
| Log directory | `~/Library/Application Support/linphone/logs/` |

The user-config and log paths above were confirmed against a build on this
machine: `~/Library/Preferences/linphone/linphonerc` exists with a `[ui]`
section, and `~/Library/Application Support/linphone/logs/` contains
`linphone1.log` / `linphone2.log`. The `linphone` directory name comes from
`EXECUTABLE_NAME`, which is set to `linphone` and is explicitly used to seed
Qt's standard paths (`Linphone/core/path/Paths.cpp:270-273`, using
`Constants::PathLogs = "/logs/"` at `Linphone/tool/Constants.hpp:147`;
`QCoreApplication::setApplicationName(EXECUTABLE_NAME)` at
`Linphone/core/App.cpp:304`, with the comment "The EXECUTABLE_NAME will be
used in qt standard paths. It's our goal." at `Linphone/core/App.cpp:298`).
Note this is independent of the app's display name ("NP Phone" /
`NPPhone.app`); only the log/preferences folder is named after
`EXECUTABLE_NAME`.

## Remote provisioning

`Linphone/data/config/linphonerc-factory` ships a commented `config-uri`
template inside the `[misc]` section (lines 24-33):

```ini
[misc]
...
# Remote provisioning (spec §9): point at the internal HTTPS endpoint serving the
# per-agent SIP account, transports=TLS, media encryption, codec order and ICE/STUN/TURN.
# Injected/overridden at deploy time by Ansible; no secrets ship in this file.
# config-uri=https://provisioning.example.internal/npphone/default.xml
```

`provisioning.example.internal` is a placeholder — it is not a real host and
must be replaced by the deploying team's actual internal provisioning
endpoint. The line stays commented in the shipped factory config; Ansible (or
equivalent deploy tooling) is expected to inject the real, uncommented
`config-uri=` value — and any per-agent credentials — at deploy time. No
secrets are checked into this repository.

Per spec §9, the real provisioned XML (served by the HTTPS endpoint above)
carries the per-agent SIP account, `transports=TLS`, media encryption,
codec order (OPUS > PCMU/PCMA), and ICE/STUN/TURN server settings — none of
that is hardcoded in the UI or in this repo. Note that SRTP media encryption
is already mandatory in this fork's factory config, independent of
provisioning: `media_encryption=srtp` / `media_encryption_mandatory=1` in the
`[sip]` section (`Linphone/data/config/linphonerc-factory:55-56`).

## Logging (FR-12)

Logging is controlled from the `[ui]` section of `linphonerc` (either the
user config at `~/Library/Preferences/linphone/linphonerc`, or the factory
config to change the shipped default):

```ini
[ui]
logs_enabled=1
full_logs_enabled=1
```

- `logs_enabled` — enable/disable log capture. Defaults to `0`/false when
  unset (`Linphone/model/setting/SettingsModel.cpp:661`,
  `getLogsEnabled(config) { return config->getInt(UiSection, "logs_enabled", false); }`).
  Set via the UI settings toggle at runtime
  (`mConfig->setInt(UiSection, "logs_enabled", status)`,
  `Linphone/model/setting/SettingsModel.cpp:629`).
- `full_logs_enabled` — enable verbose/full logging. Also defaults to
  `0`/false when unset (`Linphone/model/setting/SettingsModel.cpp:665`);
  set via `mConfig->setInt(UiSection, "full_logs_enabled", status)`
  (`Linphone/model/setting/SettingsModel.cpp:641`).
- The `[ui]` section name is the literal string `"ui"`
  (`const std::string SettingsModel::UiSection("ui");`,
  `Linphone/model/setting/SettingsModel.cpp:40`).
- Log files are written to `getLogsFolder()`, which defaults to
  `Paths::getLogsDirPath()` when no `logs_folder` override is set in `[ui]`
  (`Linphone/model/setting/SettingsModel.cpp:678-681`); on macOS this
  resolves to `~/Library/Application Support/linphone/logs/` (confirmed on
  this machine — see Config paths above).
- An admin can also set `logs_folder=/custom/path` under `[ui]` to redirect
  log output (same getter, `Linphone/model/setting/SettingsModel.cpp:680`,
  reading `config->getString(UiSection, "logs_folder", ...)`).

On this dev machine's runtime `linphonerc`
(`~/Library/Preferences/linphone/linphonerc:107,115-116`), the shipped
default has `logs_enabled=0` and `full_logs_enabled=0` — logging is off by
default and must be turned on explicitly (via the app's settings UI, or by
an admin editing `linphonerc` directly) for support/troubleshooting.

## Speed dials

The single-view dialer can show up to three provisioned speed-dial buttons
above the number pad. They are configured from the `[ui]` section of
`linphonerc` (either the user config or the factory config), one entry per
slot:

```ini
[ui]
speed_dial_1=Dispatch|2145551234
speed_dial_2=Expert line|8005550100
speed_dial_3=Voicemail|*97
```

- Keys are `speed_dial_1`, `speed_dial_2`, `speed_dial_3` — up to three
  slots, read by `SettingsModel::getSpeedDials()`
  (`Linphone/model/setting/SettingsModel.cpp`).
- Format is `Label|number-or-sip-address`. The number may be a phone number
  or a SIP address. If the `|` separator is missing, the whole value is used
  as both the label and the number.
- A slot is skipped (and its button hidden) if the key is unset, or if the
  number half is empty after splitting.
- Buttons are hidden entirely (`visible: SettingsCpp.speedDials.length > 0`
  in `Linphone/view/Page/SingleView/DialerArea.qml`) when no speed dials are
  configured, so sites that don't need them see no change.
- Values are read once at startup (`SettingsCpp.speedDials` is a `CONSTANT`
  QML property populated from the `SettingsModel` in the `SettingsCore`
  constructor); provisioning is expected to apply before the core starts, so
  there is no live-reload of these buttons while the app is running.
- Intended to be set via provisioning/Ansible alongside the per-agent SIP
  account, not edited by end users.

Provisioning note: an interim build shipped in August 2026 imported speed
dials from a local vCard (`~/.npphone/speed-dial.vcf`, `X-SPEEDDIAL:N`). That
importer never reached the source tree; the committed mechanism is the
`[ui] speed_dial_N` keys above, and `ansible-npstations` (`templates/linphonerc.j2`,
`speed_dials` in `group_vars/all/main.yml`) renders those. The playbook removes
the legacy `~/.npphone` directory.

## Reproducing the app and deployment from scratch

Everything needed to rebuild `NPPhone.app` and push it to the fleet is in two
git repositories; nothing lives only on a build machine:

| Repo | Branch | Holds |
|---|---|---|
| `https://github.com/frank3427ch/linphone-desktop` | `simple` | App source, SDK patch (`patches/`), factory config, this doc, `VOICE_ONLY_FORK.md` (every deviation from upstream) |
| `ansible-npstations` (private) | `npphone-local-speeddial` | `bins/NPPhone.app` (the built artifact), `playbook2.yml`, `templates/linphonerc.j2`, SIP/speed-dial vars |

Pinned baselines: linphone-desktop upstream `9bee5060d` (merged 2026-08-27),
linphone-sdk `4bb4159ac` (5.5.16), Qt 6.10.3, app version tag `6.3.0-alpha`.

### 1. Build machine prerequisites (Apple Silicon, macOS 26, Command Line Tools only)

```bash
xcode-select --install                     # full Xcode is NOT required (toolchain fallback is committed)
brew install cmake ninja nasm yasm doxygen meson ccache
/opt/homebrew/bin/python3 -m pip install --break-system-packages pystache six   # SDK code generators
python3 -m venv ~/.linphone-build-venv && ~/.linphone-build-venv/bin/pip install aqtinstall
~/.linphone-build-venv/bin/aqt install-qt mac desktop 6.10.3 clang_64 -m qtnetworkauth qtshadertools -O ~/Qt
```

### 2. Source checkout

```bash
git clone https://github.com/frank3427ch/linphone-desktop.git && cd linphone-desktop
git checkout simple
# Version stamping needs a 6.3.x tag reachable from HEAD (fork tags stop at 6.2.0-beta):
git fetch https://github.com/BelledonneCommunications/linphone-desktop.git \
    refs/tags/6.3.0-alpha:refs/tags/6.3.0-alpha
# Only the SDK submodule is needed. external/feature-specs is a PRIVATE
# Belledonne repo (Squish test specs) and will fail to clone — do not init it.
git submodule update --init --recursive -- external/linphone-sdk
# gitlab.linphone.org flaps: repeat until clean, then verify no EMPTY worktrees
git submodule update --init --recursive --force -- external/linphone-sdk
git submodule foreach --recursive --quiet 'test -n "$(ls)" || echo "EMPTY: $displaypath"'
# SDK patch — re-apply after EVERY submodule update, before building
git -C external/linphone-sdk/liblinphone apply "$PWD/patches/sdk-server-conference-pbx-contact.patch"
git -C external/linphone-sdk status --short   # expect: M liblinphone/src/conference/server-conference.cpp
```

### 3. Configure and build

```bash
export Qt6_DIR="$HOME/Qt/6.10.3/macos/lib/cmake/Qt6"
export PATH="$HOME/Qt/6.10.3/macos/bin:$PATH"
cmake -S . -B build \
      -DLINPHONEAPP_MACOS_ARCHS=arm64 \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DENABLE_APP_PACKAGING=OFF
cmake --build build --parallel 10
```

- First build compiles the whole SDK (~2 h); later builds are incremental
  (`cmake --build build --parallel 10`).
- `ENABLE_APP_PACKAGING=OFF` skips the CPack DragNDrop DMG, which drives
  Finder via AppleScript and dies headless (AppleEvent -1712). The fleet gets
  a bare `.app`, so the DMG is not needed. The reference build tree that
  produced the shipped bundles was configured with `ENABLE_APP_PACKAGING=ON`
  (`build/CMakeCache.txt`); the resulting `.app` is identical, the build just
  ends with the ignorable DMG error.
- The shipped build keeps the defaults `ENABLE_UPDATE_CHECK=ON` and
  `ENABLE_BUILD_APP_PLUGINS=ON`. The spec's stripped-down packaging flags
  (see "Packaging-build flags" below) are optional and have not been used for
  any fleet release.
- `xcode-select: error: tool 'xcodebuild' requires Xcode` lines in the log
  are expected noise on a CLT-only machine.
- macdeployqt `ERROR` lines about `libopenh264.6.dylib` are expected (codec
  excluded on purpose, downloaded at runtime).
- Result: `build/OUTPUT/macos/NPPhone.app` (deployed via macdeployqt, ad-hoc
  signed). The bundle folder is space-free by design (libvpx word-splits
  install paths); Finder/Dock show "NP Phone" from `CFBundleDisplayName`.

Sanity check before shipping:

```bash
codesign --verify --deep --strict build/OUTPUT/macos/NPPhone.app && echo signed-ok
strings build/OUTPUT/macos/NPPhone.app/Contents/MacOS/linphone | grep -c speed_dial_   # >= 1: single-view build
open build/OUTPUT/macos/NPPhone.app   # registers against the PBX, dialer visible, speed dials from linphonerc
```

### 4. Refreshing an existing checkout after an upstream merge or SDK bump

```bash
git pull                                                     # or merge origin/master into simple
git -C external/linphone-sdk/liblinphone stash               # keep the patch across the checkout
git submodule update --init --recursive -- external/linphone-sdk
git -C external/linphone-sdk/liblinphone stash pop           # or re-apply patches/ if the pop conflicts
cmake --build build --parallel 10
```

If `simple` diverges from upstream in `Linphone/core/App.cpp`
(`currentCallChanged` handler), keep the `simple` side: this branch routes all
call UI into the main window and never creates a `CallsWindow`.

### 5. Release to the fleet

```bash
# from linphone-desktop, after step 3
rm -rf ../ansible-npstations/bins/NPPhone.app
cp -R build/OUTPUT/macos/NPPhone.app ../ansible-npstations/bins/NPPhone.app
cd ../ansible-npstations
git add bins/NPPhone.app
git commit -m "NP Phone: ship NPPhone.app built from linphone-desktop simple @ $(git -C ../linphone-desktop rev-parse --short HEAD)"
ansible-playbook playbook2.yml --tags linphone --limit <one pilot station>   # then the fleet
```

`--tags linphone` deletes any older `CH NP Phone.app` / `NP Phone.app`,
rsyncs `NPPhone.app` into `/Applications`, clears quarantine, refreshes the
icon cache, quits the running app, and rewrites
`~/Library/Preferences/linphone/linphonerc` from `templates/linphonerc.j2`
(SIP account from `NP_EXTENSION` + vaulted `sip_passwords`, speed dials from
`speed_dials`). To change speed dials only: edit `group_vars/all/main.yml` and
run `--tags linphone_speeddial`.

Rollback: `git revert` the bins commit in `ansible-npstations` and re-run
`--tags linphone`.

## Build

Standard dev build used throughout this plan's tasks (existing `build/`
directory configured as in step 3 above):

```bash
cd /Users/administrator/Documents/GitHub/linphone-desktop
export Qt6_DIR="$HOME/Qt/6.10.3/macos/lib/cmake/Qt6"
export PATH="$HOME/Qt/6.10.3/macos/bin:$PATH"
cmake --build build --parallel 10
```

The known DMG (`cpack DragNDrop`) `-1712` packaging failure in headless/CI
environments is environmental and can be ignored; the `.app` bundle itself
still builds successfully before that step.

### Packaging-build flags (spec §8.7)

For release/packaging builds, pass these CMake options to strip
functionality not used by the single-view voice-only fork:

```
-DENABLE_APP_PDF_VIEWER=NO -DENABLE_APP_WEBVIEW=NO -DENABLE_UPDATE_CHECK=NO -DENABLE_BUILD_APP_PLUGINS=NO
```

All four options are defined in the top-level `CMakeLists.txt`:

| Option | Default | Definition |
|---|---|---|
| `ENABLE_APP_PDF_VIEWER` | `OFF` | `CMakeLists.txt:162` |
| `ENABLE_APP_WEBVIEW` | `OFF` | `CMakeLists.txt:163` |
| `ENABLE_BUILD_APP_PLUGINS` | `ON` | `CMakeLists.txt:164` |
| `ENABLE_UPDATE_CHECK` | `ON` | `CMakeLists.txt:183` |

`ENABLE_APP_PDF_VIEWER` and `ENABLE_APP_WEBVIEW` already default to `OFF` in
this tree, so `=NO` is a no-op confirmation rather than a change from
default. `ENABLE_BUILD_APP_PLUGINS` and `ENABLE_UPDATE_CHECK` default to
`ON` and must be explicitly set to `NO` for packaging builds of this
voice-only fork, since neither an app-plugin ecosystem nor an in-app update
checker is part of this fork's scope.

## Pilot acceptance checklist

Before rolling the single-view build to a pilot group, run the acceptance
criteria in `single-view-softphone-spec.md` §11 (AC-1 through AC-7) —
covering fresh-install registration time, hold/merge call flows, conference
leg removal, USB headset hot-unplug fallback, DTMF delivery, single-view
navigation lockdown, and 8-hour registration survival with automatic
re-registration after network loss.
