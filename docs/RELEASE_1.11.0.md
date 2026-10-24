# Release 1.11.0+22 — Pi-first (24 October 2026)

## Artefacts

| Item | Value |
|---|---|
| APK | `build/app/outputs/flutter-apk/app-release.apk` (59.2 MB), versionName 1.11.0, versionCode 22 |
| Previous APK backup | `~/tt-router-backups/pre-1.11.0-20261024-1954/app-release-1.10.0+21.apk` (sha256 `cdc1ce93…bdef`) |
| Argon build | `bxhZlp94u3_VPhSg3FEOm` (argon-dashboard `387360b`, docs `3cb7351`) |
| Argon rollback | `/home/alfeyo/argon-backups/release-20261024-195417/rollback.sh` |
| Observer | `argon-dashboard/scripts/system/argon-tt-observer/observer.mjs` (not yet on the Dell, which is offline) |

## Validation

* Flutter: `flutter analyze` clean; `flutter test` 255/255 (10 new in `test/pi_first_test.dart`: Argon mode never contacts the router; live-shaped router-view parsing; device filters; lease → handover → connect → release round trip with pairing kept; held lease; observer timeout releases the lease; unpaired blocker and explicit override; signed usage alerts with pathname-only signatures and ack; Fold4 cover and unfolded rendering of Home, Devices, Statistics and Wi-Fi gate).
* Argon: 199/199 tests locally and on the Pi; production build; candidate on loopback :3100 with the production environment; post-activation checks listed in `argon-dashboard/docs/DEPLOYMENT-2026-10-24-pi-first.md`.
* No live VPN change, router write or Direct Control takeover was performed for testing.

## Install (data preserved)

```
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`-r` keeps app data: Argon trust, pairing credential, Keystore key and router pairing. Never uninstall first.

## Rollback

* App: `adb install -r -d ~/tt-router-backups/pre-1.11.0-20261024-1954/app-release-1.10.0+21.apk` (downgrade, data kept).
* Argon: `ssh alfeyo@100.94.137.17 /home/alfeyo/argon-backups/release-20261024-195417/rollback.sh`.
* Observer: restore the previous `observer.mjs` (identical to `37de62c`'s copy) and stop the node process; cron restarts it.

1.11.0 works against the previous Argon build too: without `/api/v1/router/lease` a takeover reports "This Argon does not support router handover yet" and nothing connects.
