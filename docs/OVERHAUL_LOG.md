# Overhaul log

Working branch: `overhaul/stability-and-ux`. Each stage ends with analyzer,
tests, a release build and an on-device check on a Galaxy Z Fold4 (SM-F936B,
Android user 0) connected to the TaoTronics router at 192.168.10.1.

Rollback points:

| Tag | Commit | Meaning |
| --- | --- | --- |
| `baseline-pre-overhaul` | `f2d27a3` | Original repository state |
| `known-good-internet-fix` | `8891fb1` | Original app + INTERNET permission; verified connecting on device |

To roll back the installed app: `git checkout <tag> && flutter build apk --release && adb install -r -d --user 0 build/app/outputs/flutter-apk/app-release.apk`.
All builds are signed with the same debug key, so in-place updates and
downgrades keep app data.

## Baseline (2026-10-17)

- Package `com.ttrouter.tt_router_flutter`, version 1.0.0 (1), signed with the
  Android debug key (SHA-256 `c5:f7:a8:19:…:ab:89`).
- `flutter analyze`: clean. `flutter test`: 1 test (app launches).
- `releases/TaoTronics-Router-App.apk` is **not** this app: it is the vendor's
  `com.taotronics.router` 1.0.0.33 (compileSdk 29). The README's download link
  therefore installs a different application.
- Router TLS chain captured through the phone: leaf
  `CN=wifilocal.taotronics.com, emailAddress=leo.li@idazoo.com`
  (SHA-256 `83:00:77:AE:…:27:C3`) signed by the CA bundled in the app
  (`emailAddress=dazoo.app@idazoo.com`, SHA-256 `E0:33:7C:3D:…:2F:22`);
  `openssl verify` OK. A forged self-signed certificate with identical names
  fails verification but was accepted by the original name check.

## Stage 1 — critical fixes (2026-10-17)

Changed:

- **TLS (critical):** `RouterCertificateVerifier` accepts the router only if
  its certificate is the pinned CA or carries a valid RSA/SHA-256 signature
  from the pinned CA key, names it as issuer and is in date. The name-only
  fallback was removed. Tests use the live router leaf, a self-signed forgery,
  a lookalike-CA leaf with identical issuer name, tampered TBS/signature bytes,
  expiry and malformed input.
- **Connection lifecycle:** `MqttService.connect` is serialized (a reconnect
  can no longer tear down a handshake in progress; identical connects share
  one attempt). Drop events fire only for unexpected loss of an established
  session. `RouterProvider` uses session generations so stale reconnects
  cannot override a newer selection/login; reconnect is paused in background
  and retried immediately when the router's discovery beacon returns.
- **Request correlation:** requests to the same path run one at a time,
  identical concurrent requests share one round trip, every request completes
  exactly once (reply, timeout, drop, or malformed payload → `null`).
- **Router stall:** this router never answers `GetWirelessInfoListV2` and
  processes commands serially, so each V2 attempt froze all commands for
  ~10 s every 30 s. V2 is now tried once per router, then V1 is used.
- **Telemetry back-off:** one late batch (router occasionally answers ~4.6 s,
  over the 4 s timeout) no longer disables live telemetry; it backs off after
  3 consecutive misses and recovers on the next answer.
- **BLE native:** malformed/partial replies, JSON errors and SecurityExceptions
  become Flutter errors instead of crashes; a superseded discovery/provision
  call is answered with `cancelled` exactly once.
- **Save semantics:** writes return `SaveResult` (confirmed / pending
  verification / failed). Wi-Fi, WAN, LAN and guest changes that drop the
  connection are re-read after reconnect and reported as confirmed, not
  applied, or unconfirmed. A missing reply on other settings is a failure.
  Reboot without acknowledgement is reported as pending, not failed.
- **Settings safety:** every router settings page disables Save when its
  current values could not be read (previously Save would write blank
  defaults, e.g. firewall off, WAN DHCP, VPN disabled).
- **Credentials:** router passwords moved to Android Keystore-backed storage
  with a migration that removes the plaintext copy only after a verified
  secure write.
- **Discovery:** reachability uses TCP probes where a refusal proves the host
  answered; the always-true DNS lookup of the IP literal is gone. Re-checks
  after connectivity changes; no setState after dispose.
- **Lifecycle:** live polling pauses are reference-counted tokens; polling
  stops while the app is in the background; provider access in `dispose`
  removed; diagnostics/pairing guard async updates with `mounted`.
- Port-forwarding delete asks for confirmation; node signal bars hidden when
  the router reports no signal; models tolerate string/number variations.
- Optional release signing via `android/key.properties` (falls back to debug).

Verified:

- `flutter analyze`: no issues. `flutter test`: 48 passed.
  Kotlin `testDebugUnitTest`: 3 passed.
- On device (in-place update over the baseline install, user data kept):
  router discovered, certificate verdict `signedByPinnedAuthority`, MQTT
  connected, Keystore key created by the password migration, dashboard shows
  live nodes/devices/internet/throughput.
- Wi-Fi switched off for 6 s and back on: reconnect attempts backed off
  (network unreachable) and the session recovered without user action.
- Comparison run of the baseline build confirmed the V2 stall predates the
  overhaul.

Open:

- The router still misses roughly one telemetry poll in eight (router-side
  stall); values stay on screen and are refreshed on the next answer.
- Replies are matched by topic; a reply arriving after its request timed out
  could be taken by the next request to the same path (protocol has no id).

## Router behaviour observed (live, 2026-10-17)

- Commands are processed one at a time. `GetWirelessInfoListV2` is never
  answered and blocked all other commands for ~10 s; V1 works.
- The router periodically stalls for ~4–5 s (roughly every 12–24 s), so an
  occasional telemetry batch misses its 4 s timeout.
- No web server: TCP 80/443 are refused. Reachability must not depend on them.
- `GetDevListInfo` has no per-device byte counters (`UpBytes`/`DownBytes`
  absent); `ConnTime`, `CreateTime`, `UpdateTime` are epoch seconds.
  `ClientType` 0 was seen for an Ethernet-only device and 2 for Wi-Fi clients
  (the app labels links on that basis and says it is inferred).
- `GetExistNode` reports `Uptime` (s), `LocalConn`, `Model`, `Role`; no
  firmware version.
- `GetSystemState` returns an empty list.

## Stages A–B — design system, shell, overview (tag `stageAB-overview`)

- Theme tokens (light/dark, status colours, spacing, radii, breakpoints),
  shared widgets, connection and pending-change banners.
- Home shell: Home / Devices / Wi-Fi / Settings; bottom bar folded, rail
  unfolded; back returns to Home before asking to leave.
- Overview: internet state, labelled live throughput with staleness,
  devices/nodes/uptime/storage tiles, quick actions, connection details.
- Removed "Total Data Usage" (always 0 B: the router has no such counters).

## Stages C–E — devices, Wi-Fi, settings (tag `stageCDE-ux`)

- Devices: search, filters, sorting, detail sheet with every reported field.
- Mesh nodes: uptime, clients, model; firmware/signal only when reported.
- Wi-Fi: cards with reveal/copy, validated edit sheet, reconnection warning,
  pending/confirmed/failed result flow.
- Settings regrouped; all forms validate input and confirm risky changes.
- Version 1.1.0 (2).

## Stages F–G — diagnostics and setup (tag `stageFG-diagnostics-setup`)

- Diagnostics: measured gateway latency and router response time, findings
  with next steps, theme-aware, export without passwords.
- Discovery/setup/pairing: dark-mode safe, permission recovery, Bluetooth
  error guidance, superseded searches ignored, "Set up a router" in Settings.

## Final verification (2026-10-17, build 1.1.0 (2))

- `flutter analyze`: no issues. `flutter test`: 71 passed. Kotlin unit tests:
  3 passed.
- APK `releases/TaoTronics-Router-App.apk`, 36.1 MB,
  SHA-256 `7b22cf0f915c16db7ce193acb0068880d710d682dfec440af1f92c1d96a8225a`,
  package `com.ttrouter.tt_router_flutter`, versionCode 2, INTERNET declared,
  debug-key signed (same key as the installed app).
- Galaxy Z Fold4 (user 0): in-place upgrade from 1.0.0 kept the pairing; router
  discovered; certificate `signedByPinnedAuthority`; MQTT connected; no crash
  in a 60 s run; Home, Devices (filters, details), Wi-Fi (edit sheet opened and
  cancelled), Settings, WAN (read only), Diagnostics (gateway 9 ms, router
  99 ms, no findings), discovery, setup wizard Bluetooth search (not-found path
  and superseded search) checked on screen.
- Wide layout checked by temporarily setting the cover display to 240 dpi
  (~603 dp, navigation rail); density reset afterwards. Light mode checked by
  switching night mode off and back to its original "yes".
- Wi-Fi off/on recovery verified (Stage 1).

Not exercised on the live router (by design — disruptive or needs consent):
saving Wi-Fi/WAN/LAN/guest/security/VPN/DDNS/QoS/LED/schedule changes,
reboot, provisioning a router over Bluetooth. Their request/verification
logic is covered by unit and widget tests against a fake router.

## Outstanding risks

- Release is signed with the Android debug key (sideload only). A store
  release needs a private key; switching keys requires a reinstall.
- Replies are matched by topic (protocol has no request id); a very late reply
  could be taken by the next request to the same path.
- `ClientType` link labels and the bundled band labels (index → 2.4/5 GHz)
  are inferred, not documented by the vendor.
- The pinned TaoTronics CA and router certificate expire in May 2030; after
  that the app will refuse the router unless the clock is wrong or the
  firmware ships a new certificate.
- The physical unfolded screen was emulated with a density override, not
  tested by unfolding.

## 1.2.0 — Wi-Fi restoration and smart-home redesign (2026-10-17)

Stages and tags: `redesign-s1-wifi`, `redesign-s2-home`,
`redesign-s3-devices-settings`, `v1.2.0`.

Wi-Fi regression, root causes and fixes:
- The Wi-Fi tab had no per-band switch; on/off existed only in the
  two-band form (indexes 0/1), so network index 2 could not be enabled or
  edited. Every reported network now has its own switch and editor.
- `toRouterPayload` added V2-only `Disable`/`ConfStatus`/`NodeSn` to V1
  entries and blank `Password` when omitted. Payloads are now the router's
  own fields plus only edited values; untouched entries are byte-identical.
- `_subsetMatches` treated missing fields as matches; it now returns
  unknown, so such saves are "unconfirmed", never "confirmed".
- Saving is refused before the list loads, when a required field is
  missing, or when it would switch off the last enabled network.
- Late replies to timed-out write commands are discarded instead of being
  taken by the next write on the same command.
- Pairing JSON excludes the password unless the secure-storage fallback
  explicitly requests it.

Design: palette from the reference pack (charcoal #23242C, slate #747782,
indigo #777DDE, amber #F0A85B, off-white #F5F6FA). The dark page background
is slate deepened to #545864 for 6.6:1 text contrast; light-mode indigo is
#5B61C9 (5.25:1). Floating pill navigation, pill buttons, rounded panels,
page headers; Home, Wi-Fi, Devices, Mesh, Settings, discovery and splash
redesigned. Typography uses the platform font (Inter was not bundled).

Verification:
- `flutter analyze` clean; `flutter test` 84 passed (stateful V1 fake router
  for toggles/edits/drops/verification, late replies, LED, responsive
  344/690/1100 dp, 1.6× text, dark mode). Kotlin tests 3 passed.
- Galaxy Z Fold4 cover screen, in-place upgrade to 1.2.0 (3) with data kept:
  TLS verified, MQTT connected, Home/Wi-Fi/Devices/Settings/Mesh/LED/
  Diagnostics/discovery checked; all Settings entries present; light mode
  and wide (rail) layout checked via night-mode and density overrides,
  both restored.
- LED switch verified on the live router: off → on → off (left off, as
  found). No live Wi-Fi band, reboot or credential change was made.

Observation: between 16:30 and 16:40 the router began reporting the 5 GHz
network (index 1, "TT-35A0") as off (`Create` 0). The app sent no Wi-Fi
command (every path requires the confirmation dialog, which was never
accepted). The app now shows that state; it was not changed back.

## 1.2.1 — final Home refinement (2026-10-17, tag `v1.2.1`)

- App start opens Home automatically once the saved pairing reconnects
  (splash waits up to 12 s, then falls back to discovery/setup).
- Home: compact "My Router" header with notifications; router card with the
  TaoTronics router illustration from the original app, model, primary
  SSID, status, device count, password masked with Show/Hide only when the
  router reports it, and an LED badge that toggles the real LED.
- Live download/upload sparklines from samples collected this session
  (max 40); "Usage & insights" shows WAN type (GetMWanInfo), WAN IP,
  gateway, internet state and session peaks. No daily/weekly totals: the
  router does not report them.
- In-app notifications for disconnections, failing reconnects and settings
  results (no push, no background service).
- Verified on the Fold4: cold start → Home without taps; LED badge
  on → off → on with read-back (left as found: on); wide layout checked.
- Observed: the router's LED changed from off (16:50) to on (17:06) without
  any app command, like the 5 GHz band earlier — external changes.
- Future placeholder branch: `feature/nokia-wifi-extension`.
