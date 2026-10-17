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
