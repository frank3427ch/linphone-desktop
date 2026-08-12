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

## Build

Standard dev build used throughout this plan's tasks:

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
