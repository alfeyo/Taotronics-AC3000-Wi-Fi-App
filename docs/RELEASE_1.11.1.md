# Release 1.11.1+25 — Complete the interrupted Pi-first app

24 October 2026 · `codex/nokia-home-app` · baseline `aff83de` (1.11.0+24)

## Completed

Preserved Claude's interrupted layout, theme, typography, navigation styling, cards, spacing and hardware imagery. Completed the existing Home quick controls and dedicated Router destination; kept detailed diagnostics in Network Hub and advanced Wi-Fi behind explicit direct control.

Statistics retains the gauge and live graphs, gives Today and Yesterday priority, and keeps longer periods in More history. Weekly device activity uses real observer rows with today's data merged exactly once. Missing observations remain missing, estimates remain explicit, and partial household periods retain `≥`. Monitoring coverage has an inline explanation and timestamps.

Refreshes await in-flight polls and report stale data honestly. Home VPN actions use the same paired-device authorization, confirmation and read-back as Network Hub. Handover cancellation releases late acquisitions; backgrounding and lease expiry close direct access without deleting pairing. Wi-Fi routes react when the app returns to Argon mode.

## Validation

- `flutter analyze`: clean.
- Full Flutter suite: **264 passed**; final focused suite: **19 passed**. Coverage includes Pi API integration, authorization, VPN commands/location, observer handover, cancellation, background release, lease expiry, refresh concurrency, navigation and responsive layouts.
- Argon suite: **199 passed**. No Argon backend or observer source changes were required.
- Reviewed the live Dell observer: SHA-256 `50a6ba293623e6bd5ae9ff73842d1ddbb5fc25e057eeb0ed7974c87133fcf9ca`, identical to the repository's handover-capable version. Source updated 18:28:22 UTC, running process started 18:28:38 UTC; one node process under flock with cron watchdog. It was already deployed, so no restart/redeployment was needed.
- Live identity, live, gateway and lease endpoints returned 200. Unauthorized empty control requests were refused. Household routing, VPN, firewall, DHCP, DNS and Wi-Fi configuration were not changed.
- Review findings, test/build logs, API checks and device screenshots: `docs/release-1.11.1-validation/`.

## APK and installation

- APK: `build/app/outputs/flutter-apk/app-release.apk` (59.5 MB).
- SHA-256: `cc285fa6cce1609d9710a0d819e23eeb01fcd54248fda7914dc3f84c171d35da`.
- Signing certificate matches the installed verified release.
- Installed with `adb install -r` on Galaxy Z Fold4 (`SM-F936B`), without clearing data. Package reports 1.11.1 / 25; original first-install time remains **2026-10-17 14:25:47**. Existing Argon trust, router pairing and VPN grant remain available.
- Verified on the physical cover screen: Home, Router, Devices, Statistics, Settings, Network Hub, Nokia entry and Notifications. Refresh statistics and devices update successfully. VPN toggle and location both reach their authorized confirmation flows and were cancelled, leaving VPN off and the UK/London selection unchanged.
- Ordinary navigation before takeover produced **zero MQTT/discovery log lines**. Home connected automatically through Argon's LAN API.
- Fold4 unfolded, OnePlus portrait, landscape and enlarged-text layouts are covered by widget tests. The OnePlus was not connected, so it was not installed or physically tested.

## Direct Control verification

Live Fold4 round trip completed without router writes: lease acquired at 20:55:26 Lusaka, Dell yielded at 20:55:38, phone reached **Direct router control / My Router Online** after the router's expected previous-controller delay. Saved router pairing loaded its Wi-Fi information and masked password. The lease renewed while active. **Return to Argon** released it at 20:56:52 and immediately restored Argon-backed screens.

Fresh Dell observations resumed after the router's return delay (about 70 seconds); the lease is inactive, VPN remains off, and the exit selection remains UK/London. See `release-1.11.1-validation/handover.json` for timing and observer-resumption evidence. No competing phone MQTT connection occurred during ordinary monitoring.

## Backup and rollback

Verified prior APK and a copy pulled from the Fold4 are in:

`~/tt-router-backups/pre-1.11.1-20261024/`

Both `app-release-1.11.0+24.apk` and `fold4-installed-base.apk` have SHA-256:

`afa1128a7745a42cd9ae0902e1cf412f01b52f6561c331e1b8177c59374f1d67`

Install the new release without removing app data:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Attempt an in-place rollback only if Android permits downgrades for this package:

```sh
adb install -r -d ~/tt-router-backups/pre-1.11.1-20261024/app-release-1.11.0+24.apk
```

Some Android release builds reject a lower version code even with `-d`. If rejected, **do not uninstall or clear data**. Build the verified `aff83de` source in a separate checkout, using the same signing configuration and a version code higher than the installed build, then install with `-r`. Keep the current development checkout intact. No Argon or observer rollback is needed for this app-only release.

## Remaining limits

No live VPN change or Wi-Fi write was made. Background push notifications do not exist; the existing event/usage-alert center operates while the app is open. Tailscale/Bluetooth fallbacks retain existing automated coverage but were not forced during household validation. Build succeeds with existing plugin Kotlin migration warnings; no dependency upgrades were included.
