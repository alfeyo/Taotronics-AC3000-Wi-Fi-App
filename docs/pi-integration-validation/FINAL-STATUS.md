# Argon Pi integration — final status (2026-10-17)

## Release
- Version 1.4.0+7, built from `4f03256` on `feature/argon-pi-integration`.
- APK: `artifacts/releases/tt-router-1.4.0-argon.apk` (SHA-1 `e392016fb864621d6f277e44deaa71e85430edb3`, 57.1 MB).
- Signed with the same certificate as the installed 1.3.1+6 (SHA-256 `c5f7a819…00ab89`).
- Prior releases retained: `tt-router-1.3.1-verified.apk`, `tt-router-1.3.1-from-fold4.apk`.

## Observed on Galaxy Z Fold4 (RFCTB0AH5BN, SM-F936B)
- `adb install -r` upgrade 1.3.1+6 → 1.4.0+7 succeeded without clearing data.
- Saved pairing survived; router 5702H5035a0eU6b9 at 192.168.10.1 discovered, pinned-CA MQTT connected.
- Home screen: Internet online, 4 devices, LED control and live rates shown.
- Gateway screen loads the unconfigured state and Connect Argon form; phone reaches 100.94.137.17 over Tailscale.

## Checks
- Flutter: `flutter analyze` no issues; `flutter test` 94/94 pass.
- Dashboard: `npm test` 105/105 pass; `next build` compiles; deployed build `6WqZWy3vUk6i2m0mhppMz`; `/devices` and `/network` HTTP 200.
- Companion API rejects unauthenticated requests (401).

## Blocked — not verified
Live telemetry was not observed. The companion token was never saved on the phone:
the Connect Argon form stayed unsubmitted (token empty, Share router telemetry off) across
re-checks at 20:56–20:58 CAT, and no touch input reached the device. The Pi stayed
`not-connected` with 0 clients and no `receivedAt`. Therefore the following are NOT verified:
- bridge authentication and snapshot upload/acceptance;
- real TaoTronics clients on `/devices` (names, counts, states, rates);
- source timestamps, 60 s expiry and stale-data handling with live data;
- disabling the bridge without affecting router controls;
- Gateway traffic, VPN, availability and events rendered from live Pi data in the app.
The Pi correctly shows no fabricated clients. Wi-Fi/LED writes were not exercised this session.
