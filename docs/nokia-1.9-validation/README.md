# TT Router 1.9.0+17 — 18 October 2026

- `flutter analyze`: no issues.
- `flutter test`: 215 passed, including Nokia identity/login/bridge/mesh gates, changed-key credential replay rejection, native HTTP 299 handling, 5 GHz DHCP/internet verification, guest field/password read-back, disposal during delayed verification and responsive Nokia layouts.
- Release APK built successfully: `artifacts/releases/tt-router-1.9.0-17.apk` (local, git-ignored).
- APK SHA-256: `ec0de9488c9341fe586be5e250a67dd55b7c80c70ab9b77a868d000cafb688bd`.
- Certificate SHA-256: `c5f7a819539e89c7c4d1e678e9aa9affaeafe1a12b7ad2db3710c152d100ab89`, matches 1.8.0+16.
- Fold4 `RFCTB0AH5BN`: `adb install -r` succeeded; installed package reports versionName 1.9.0 / versionCode 17. No uninstall or app-data clear. Existing TaoTronics pairing and Argon monitoring retained.
- Owner-authorized Nokia login succeeded in the final APK. Reopening Nokia Mesh restored the saved pinned-key login and AP_BRIDGE read-back at 192.168.10.97. The client-path check passed using Nokia radio, TaoTronics DHCP/gateway and Wi-Fi-bound HTTPS.
- TaoTronics Wi-Fi page: main and duplicate entries active, index 2 off, WPA2-PSK and 24 router-reported clients at capture. No live TaoTronics Wi-Fi write was performed. Observed broadcast attribution is withheld when joined through Nokia; the UI explains that a TaoTronics-radio scan is needed.
- Argon read-only post-check: VPN mode off, service inactive, default route via 192.168.88.1 dev eth0, source 192.168.88.250. No production system modifications or Next.js changes.
- Next repository test run: 186 passed, 0 failed (existing baseline; no source changes).
- CodeRabbit final implementation review completed with 2 issues; both addressed. The report retains the original findings; fixes and the unresolved existing Argon VPN DNS bootstrap issue are described in `../FINAL_CODE_REVIEW.md`.
- OnePlus unavailable. The second Beacon awaits the requested owner activation and printed serial; enrollment/backhaul/roaming are not yet hardware-validated. Nokia radio/guest/channel writes remain unavailable pending complete protocol validation.

Rollback checkpoint: Flutter baseline `bfb2331` / prior release `12e61a9`; retained APK `artifacts/releases/tt-router-1.8.0-16.apk`. Prefer a forward fix; uninstalling to downgrade would lose local pairing. Root rollback would be a deliberate Nokia mode/configuration operation, not an Argon change; no automatic rollback is scheduled.
