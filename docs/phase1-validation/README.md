# Phase 1 validation — 1.10.0+21 (2026-10-22)

Build: `flutter build apk --release` from commit `0f6f514` plus the ownership-detector
correction in the following commit, branch `codex/nokia-home-app`.

- APK: `artifacts/releases/tt-router-1.10.0-21.apk` (58.8 MB)
- SHA-256: `cdc1ce93cccfc8f076f3759a560e1c822f36d6937112ae6c5a6ae512675fbdef`
- Signer: `C=US, O=Android, CN=Android Debug`, SHA-256
  `c5f7a819539e89c7c4d1e678e9aa9affaeafe1a12b7ad2db3710c152d100ab89` — same key as
  1.9.2+19, so `adb install -r` upgraded in place without clearing data.
- Installed on SM-F936B (RFCTB0AH5BN) over 1.9.2: `versionName=1.10.0`, `versionCode=21`.

## Checks

- `flutter analyze`: no issues.
- `flutter test`: 245/245 pass, including 18 new or rewritten cases for policy
  enforcement, reconnect suppression, the reconnect cap, ownership handling, gateway
  enforcement and injected-gateway wiring.
- Upgrade path: `adb install -r` succeeded; saved pairing and preferences survived.

## On-device observations

- Startup connects once to `192.168.10.1:25678`, then the router answers `ErrorCode 5`
  ("managed by another phone").
- Background → foreground added **no** connection attempt (`MqttService: Connecting`
  count stayed at 1), confirming resume no longer bids for the router.
- No `FATAL EXCEPTION` or Flutter error in logcat.

## Defect found and fixed during deployment

The first build inferred Argon ownership from `router.monitoring.state == "connected"`.
The live Argon reports that state for a **Dell LAN observer**
(`source: lan-observer:dell`, snapshot 4 s old), not for its own control session. The app
correctly showed the "Router control provided by Network Hub" banner — and then froze:
polling was suppressed, so it never noticed when access freed up and sat on "Waiting for
router access" indefinitely.

Fix: ownership now requires an explicit `owner`/`control` field equal to `argon`; the
banner disappeared on the rebuilt APK. `RouterProvider.applyPiOwnership()` also closes any
established session instead of leaving it idle.

## Current router state (not a Phase 1 defect)

The TaoTronics is being managed by another client right now. Argon reports
`router.monitoring.source = lan-observer:dell` with a 4 s fresh snapshot, and the app is
refused with `ErrorCode 5` on every probe (45 s cadence). The phone shows "Another phone
is managing the router" and "Devices: waiting", which is correct: one management client at
a time is the router's rule. Phase 1 reduces this phone's bids; it cannot free a session
another client is actively holding.

## Not verified

- Automatic reconnect cap and jitter on a live outage (covered by tests only).
- Argon ownership handshake end to end: Argon does not publish `router.owner` yet, so the
  blocked path is exercised by tests, not by the deployed Pi.
- Snapshot `wan`/`guest` fields after the sync change: they are expected to be `null`
  unless a settings screen read them recently.
