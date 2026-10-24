# Release 1.11.0+24 — Pi-first (24 October 2026)

## Artefacts

| Item | Value |
|---|---|
| APK | `build/app/outputs/flutter-apk/app-release.apk` (59.2 MB), versionName 1.11.0, versionCode 24 (+22 and +23 were interim device builds the same evening) |
| Previous APK backup | `~/tt-router-backups/pre-1.11.0-20261024-1954/app-release-1.10.0+21.apk` (sha256 `cdc1ce93…bdef`); the APK pulled from the Fold4 before install is `fold4-installed-base.apk` in the same folder |
| Argon build | `bxhZlp94u3_VPhSg3FEOm` (argon-dashboard `387360b`, docs `3cb7351`) |
| Argon rollback | `/home/alfeyo/argon-backups/release-20261024-195417/rollback.sh` |
| Observer | `argon-dashboard/scripts/system/argon-tt-observer/observer.mjs` (not yet on the Dell, which is offline) |

## Validation

* Flutter: `flutter analyze` clean; `flutter test` 255/255 (10 new in `test/pi_first_test.dart`: Argon mode never contacts the router; live-shaped router-view parsing; device filters; lease → handover → connect → release round trip with pairing kept; held lease; observer timeout releases the lease; unpaired blocker and explicit override; signed usage alerts with pathname-only signatures and ack; Fold4 cover and unfolded rendering of Home, Devices, Statistics and Wi-Fi gate).
* Argon: 199/199 tests locally and on the Pi; production build; candidate on loopback :3100 with the production environment; post-activation checks listed in `argon-dashboard/docs/DEPLOYMENT-2026-10-24-pi-first.md`.
* No live VPN change, router write or Direct Control takeover was performed for testing.

## Device verification — Galaxy Z Fold4 (SM-F936B, cover screen), 20:01–20:10

Installed with `adb install -r` over 1.10.0 (21): `firstInstallTime` stayed 2026-10-17 14:25, so data was kept; Argon trust, pairing and the VPN grant survived ("VPN permission granted to this phone").

| Check | Phone | Argon API at the same time |
|---|---|---|
| Cold start | Home, "Connected to Argon — monitoring household network", Local network; 0 router/MQTT log lines | — |
| Today | 21.1 GiB ↓ · 1.28 GiB ↑ · 22.4 GiB, 100% observed | 21.15 / 1.28 / 22.43 GiB, coverage 0.9997 |
| Last 7 days / this month | 253 GiB / 331 GiB (≥, 81% covered) | 253.00 / 330.76 GiB |
| Live rates (Statistics) | 613 kbps ↓ · 851 kbps ↑ | 612 604 / 851 373 bit/s |
| Devices | 18 online · 49 known; Note10 ≈ 3.98 GiB, dell ≈ 2.89 GiB, estimated | counts 18/49; 3.98 / 2.89 GiB |
| Network Hub | CPU 27%, 44 °C, no throttling, eth0 via 192.168.88.1, observer "Dell LAN observer", mesh 1/1 | same |
| Wi-Fi / Settings | capability matrix; "Argon mode" card with Take Direct Router Control | — |

Defects found on the device and fixed in +23/+24: rate cards mixed bytes ("35.3 KiB/s") with a bits caption → rates are now always bits (bps/kbps/Mbps); new router/inventory events showed only "Network Hub" → titled and with their message; Network Hub "Refresh devices" was disabled and its Health/Sync rows assumed a router session → they now use Argon; "Off · Off" VPN label and a lower-cased "argon".

Not verified on a device: the OnePlus (not connected), a real Direct Control takeover (no disruptive test; the observer update is still pending), and background notification delivery (none exists).

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
