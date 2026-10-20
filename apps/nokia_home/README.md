# Nokia Home

Independent Android companion for the household's Nokia WiFi Beacons. Version 1.0.0+1, application ID `com.alfeyo.nokia_home`. Installs alongside TT Router with separate private credential storage. It is not the official Nokia application.

## Use

1. Open **Connect → Choose Wi-Fi** and select `Nokia Wifi` in Android settings. A factory Beacon uses its printed `NOKIA-…` network and Wi-Fi key. Enter Wi-Fi credentials in Android, not in a fake upstream-router form.
2. Return and run **Check Wi-Fi internet**. The app reports the actual BSSID, address, gateway and Wi-Fi-bound HTTPS result. An identical SSID on TaoTronics is not credited as a Nokia internet connection.
3. Select **Find Beacon**. Optionally enter the last observed management address (`192.168.10.97`); it must return a valid Nokia identity. No hardcoded device credentials are included.
4. On **Beacon**, use the device's local administrator login. Identity checks and the existing firmware-specific encrypted login protect saved reconnections. No cloud account is required.
5. Refresh radio/client/mesh reports. To enroll an additional compatible Nokia, first verify the root's client DHCP/internet path, enter the exact printed ALCL serial and approve enrollment. Acknowledgment or inventory membership is not completion. The observer is bounded and read-only.

This app cannot add wireless-WAN support to the installed Beacon 2 firmware. No verified operation makes it associate upstream to TaoTronics Wi-Fi. It does not change SSIDs, router mode, Argon, DHCP, VPN or routing. Missing backhaul signal/parent/internet fields remain unknown. Opening Android settings or backgrounding the app invalidates prior connection evidence.

## Implementation from inspected sources

Reused the existing decompilation of Nokia WiFi **3.260311.00**, not a new download. Source fingerprints and the deeper trace are in [the enrollment manifest](../../docs/evidence/nokia-enrollment-call-paths-2026-10-18.json) and [protocol investigation](../../docs/NOKIA_ENROLLMENT_PROTOCOL.md).

| Source | Actual behavior | Nokia Home implementation |
| --- | --- | --- |
| `nokia/prism/AndroidPlugin.java:437–465`, `connectToSSID` | Changes Android phone Wi-Fi using `WifiManager`; dispatcher also returns `AUTO_CONNECT_NOT_SUPPORTED`. It does not configure a Beacon upstream radio. | Opens Android Wi-Fi selection; verifies the resulting connection afterward. Does not copy the app's destructive remove-existing-profile step. |
| `chunk-ZTUP5JXS.js`, device discovery/login builders | Discovers Nokia identity and authenticates a local owner. | Existing identity-checked local transport; Beacon 2 CGI 5.5 uses the previously verified device WebGUI nonce/RSA/AES login. |
| `chunk-XRW5DKG6.js`, `saveSerialNumber`; `chunk-ZTUP5JXS.js`, `setSerialNumberExtender` | Submits `act=AddBeacon&BeaconSrn=<serial>` to the authorized root. | Reuses the verified CGI 5.5 WebGUI equivalent `mesh_web_app.cgi?add`, with serial/identity/capacity guards and explicit confirmation. |
| Firmware WebGUI `loadMeshData` and `mesh_status_web_app.cgi` | Reports root/extender inventory and raw onboarding/backhaul fields. | Freshness labels and bounded observation; no invented RSSI, parent relationship or internet state. |
| `setWifiNamePassword` / `ConfigWhwPswd` | Configures broadcast SSID/security, not a third-party uplink. | No unsupported upstream credential form or broadcast writes. |

The app is a self-contained Flutter package. Its `NokiaService`, `NokiaProvider`, Wi-Fi scanner and two Android transports are snapshots of the tested TT Router implementation at commit `380e465`, with application/channel naming and recovery wording adapted for Nokia Home. The new Android activity registers only `nokia_home/local` and `nokia_home/wifi_scan`. There is no dependency on the TT Router app, its assets, MQTT, Bluetooth setup or Argon providers. Reconcile these snapshot files with the original implementation when transport fixes are made. The existing service/diagnostic regression tests are carried into this package. No decompiled binaries, vendor artwork, cloud secrets or household passwords are bundled.

## Build and validation

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. The build uses the local debug signing key for private sideloading, not Play distribution. A production signing identity is not configured.

Widget tests cover Wi-Fi selection without router writes, identical-SSID attribution, actual radio matching, roaming during verification, lifecycle freshness, stale inventory, and small-screen accessibility. These simulated tests validate application behavior, not physical Nokia backhaul. Android-device installation and household testing require an available authorized phone; ADB listed none during this work.

Validation on 20 October 2026: **30 app tests passed**, analyzer clean, release APK built, APK package/version/launcher verified and signature verified. The setup screen was rendered and visually inspected at 390 × 844. The 32 original Nokia baseline tests also passed before the transport snapshot was made. See [validation record](validation.json). No live router operation or physical connectivity claim is part of these results.
