# Nokia WiFi app: protocol investigation (static analysis)

> Update, 18 October 2026: both Nokia Beacons are factory-reset and powered off.
> Older Nokia addresses, identity and configuration below are historical, not
> current. TaoTronics broadcasts `Nokia Wifi`. The supported target is a separate
> **two-Beacon Nokia mesh in AP bridge mode behind TaoTronics**; cross-vendor
> enrollment remains unsupported. Exact models/firmware and bridge behavior are
> unverified. Follow [Nokia bridge validation](NOKIA_BRIDGE_VALIDATION.md), including
> temporary-SSID testing and approval before household-SSID activation.


Date: 2026-10-18. Method: static inspection only (unzip, shasum, apksigner, aapt2, jadx).
The app was never installed or run, no code from it was executed, and nothing was sent over the network.
The APK was not modified. Embedded secrets are listed as present but their values are not reproduced.

Source file: `~/Downloads/Nokia+WiFi_3.260311.00_APKPure.xapk`, an APKPure mirror bundle. It is treated as
untrusted input and was extracted into a scratch directory outside this repo.

## 1. Bundle identity and integrity

| Item | Value |
|---|---|
| Package | `com.nokia.wifi` ("Nokia WiFi") |
| versionName / versionCode | `3.260311.00` / `326031100` |
| minSdk / targetSdk / compileSdk | 29 / 36 / 36 |
| XAPK SHA-256 | `c157d7c0ea08ec97bb5ec6b28bd0edc7ac6827d70f3e40d8dac834e3ebebc5dd` |
| base `com.nokia.wifi.apk` (43.4 MB) | `588d8af0d40a922892dbd02af9867c5d3dcd0f45cd925d5146bed6f7704e7979` |
| split `config.armeabi_v7a.apk` | `1da152c34505bd1ea53648908677716a3d59ef029f15a5cdf70c141016536a71` |
| split `config.en.apk` | `921ce5fe72d0f570a8a9d1853c57eef2c31c66a0b99115f81458521151c1b5a5` |
| split `config.mdpi.apk` | `227001c2f0cca9a2875e3240f3a6bf0525985ee021206baa4791159be726b296` |

The bundle also contains `manifest.json` (APKPure metadata) and `icon.png`.

**Signing.** All four APKs pass `apksigner verify` with the same v3 signer:
- Subject/issuer DN: `CN=Nokia, OU=DHBU, O=Nokia, L=Chennai, ST=TN, C=IN`
- Cert SHA-256: `79896c1c46110b61d8f91cec848f9d77d35014ba4a376d68033c2e322081b372`
- They also carry a Google Play **Source Stamp** (`CN=Android, O=Google Inc.`, SHA-256 `3257d599…bbd6d`), which means the APKs were built for Play distribution.

Assessment: this looks like an official Nokia signer (O=Nokia, OU=DHBU, which is probably Device/Home Broadband
Unit), and the Play source stamp suggests APKPure passed the Play splits through unmodified. **Not verified:** we
have not compared this certificate digest with one from a Play-installed copy. Do that before trusting it fully.

## 2. App composition

**Architecture.** The app is a hybrid Ionic/Angular app running on Capacitor and Cordova. Almost all protocol
logic lives in minified JS under `assets/public/` (407 chunks, about 59 MB). The native Java code is a thin layer
of plugins.

Key JS files:
- `chunk-ZTUP5JXS.js`: the API service (request builder, auth headers, discovery, response mapping, USP mesh mapper).
- `chunk-O5UGQCOY.js`: base URLs, the relative-URL table, the device-capability model, and the gateway IP helper.
- `chunk-SKC2FBIM.js`: the local WebSocket client.
- `chunk-C4KD4T5M.js`: constants, strings and model names.
- `chunk-6OP2DCVQ.js`: the BLE / FastMile Receiver client.

**Permissions:** INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_STATE, ACCESS_FINE/COARSE_LOCATION,
CAMERA, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, BLUETOOTH/BLUETOOTH_ADMIN (maxSdk 30), BLUETOOTH_SCAN
(neverForLocation), BLUETOOTH_CONNECT, FOREGROUND_SERVICE, RECEIVE_BOOT_COMPLETED, WAKE_LOCK, POST_NOTIFICATIONS,
FLASHLIGHT, USE_BIOMETRIC/USE_FINGERPRINT, READ/WRITE_EXTERNAL_STORAGE, C2DM RECEIVE (FCM).

**Manifest flags.** `usesCleartextTraffic=true`. `network_security_config.xml` allows cleartext for every host and
adds `@raw/gsmrsp2root` (the GSMA eSIM RSP root) to the system trust anchors. The SSO redirect scheme is `nokiawifi`.

**Notable components:**
- `com.nokia.wifi.MainActivity` (exported launcher).
- `com.barcodescanner.BarcodeScanner` (exported; QR scanning).
- zxing `CaptureActivity`, ML Kit code scanner.
- Capacitor push (`MessagingService`) and local-notification receivers.
- `FirebaseMessagingService`, `com.davidbriglio.foreground.ForegroundService`.

There are no Nokia-specific background services or providers.

**Nokia native code:**
- `nokia/prism/AndroidPlugin.java` (Cordova plugin `androidplugin`). Handles: getgatewayip, forceToWifi (bind
  process to Wi-Fi), connectToSSID, getCurrentSSID, network listener, captive portal check,
  encrypt/decryptBLERequest, QR startScan.
- `nokia/prism/BLEDataConversion.java`, `ReceiverRequestMessage*.java`: framing and crypto for BLE requests.
- `com/nokia/lpa/*`, `com/gieseckedevrient/lpa`: eSIM LPA SDK, used for FastMile receivers/gateways.
- White-label stubs: `com/{beanfield,ezeefiber,purplefibre,novus,…}/wifi` (R classes only).

**Native libraries (armeabi-v7a split only):** `libbarhopper_v3.so` (ML Kit barcode),
`libimage_processing_util_jni.so` and `libsurface_util_jni.so` (CameraX), `libsqlcipher.so` (encrypted SQLite).
There are no Nokia protocol `.so` files.

**Third-party libraries:**
- Networking: `cordova-plugin-advanced-http` (native HTTP with cookie jar and `setServerTrustMode`); OkHttp3 and
  Retrofit2 are present in the dex but are not referenced by Nokia classes.
- Bluetooth: `@capacitor-community/bluetooth-le`.
- Scanning: ML Kit barcode, zxing/phonegap barcodescanner.
- Firebase Messaging (FCM), PostHog analytics.
- Storage: `@capacitor-community/sqlite` + SQLCipher, capacitor-secure-storage, `cordova-plugin-aes256-encryption`.
- `cordova-plugin-networkinterface`, Jackson.

**Not found:** MQTT/Paho, gRPC, SSDP, UDP broadcast, NSD/Zeroconf browsing. The protobuf classes belong only to
ML Kit internals.

**Embedded credentials (values redacted):**
- `assets/public/chunk-ZTUP5JXS.js`, environment object: AES key/IV constants, cloud client-id/client-secret
  headers, an app-config `x-api-key`, a receiver salt key, and a PostHog project key. Each is an embedded
  credential present (redacted).
- `nokia/prism/BLEDataConversion.java`: static AES IV, an embedded credential present (redacted).
- `res/values/strings.xml`: standard Firebase config (`google_api_key`, `google_app_id`, …), an embedded
  credential present (redacted).

## 3. Protocol evidence

### 3.1 Discovering and identifying the gateway (CONFIRMED)

- **Gateway IP.** `AndroidPlugin.getgatewayip` reads `WifiManager.getDhcpInfo().gateway`. JS
  `getGWIpAddress()` (`chunk-O5UGQCOY.js`) returns `http://<dhcp-gateway>`, or falls back to
  `http://www.webgui.Nokiawifi.com`.
- **Fallback order.** When discovery has not yet succeeded, the API service fans out the same CGI request to
  several base URLs (`chunk-ZTUP5JXS.js`, request ids `isMainID+0..5`):
  1. gateway IP over http, then https;
  2. `www.webgui.Nokiawifi.com` (`ONT_HOSTNAME`) over http, then https;
  3. `nokiadevice.local` (`MDNS_DOMAIN_URL`) over http, then https.

  The first host that answers becomes `ONT_IP`, which is cached in native storage as `ONT_IP_NATIVE`.
- **What "mDNS" means here.** It is only a `.local` hostname resolved by the OS resolver. There is no service
  browsing. **No hard-coded LAN IP** (such as 192.168.18.1) exists anywhere in the JS.
- **Probe request.** Discovery and liveness use `login_app.cgi?chk` (`dnsCheckCall`). The same endpoint takes
  `?sts`, `?out` (logout), `?dnatd` and `?RebootStatus`.
- **Pinning to Wi-Fi.** In local mode the app calls `forceToWifi`, which runs
  `ConnectivityManager.bindProcessToNetwork(wifi)`, so that cellular data does not take the requests.
- **Device identity.** `get_devmap_cap_status_app.cgi` returns `devapp_cap_info[0]`, which contains:
  - `devGwMac` (root MAC), `devGwSnum` (serial), `devMode`, `devVer` (CGI version);
  - `cldRemoteUrl`: the cloud base URL, which is **supplied by the device**;
  - feature blocks: `RGW_Onboarding.Cloudless_Support`, `AP_Onboarding.Dynamic_Backhaul`, `Settings.Bridge_Mode`,
    MLO, WPA3, TR-143 speed test, and others.

  Cloud mode can also read `devices-catalogue/hardwares/{hw}/softwares/{sw}`.

### 3.2 Local vs cloud selection (CONFIRMED)

`Fe.isModeLocal()` (`chunk-O5UGQCOY.js`) chooses **local** in any of these cases:
- the device capability is empty;
- `devVer` is older than the new-architecture CGI version;
- account creation was skipped;
- a local account is in use;
- `Cloudless_Support != 0`.

Otherwise the app uses **cloud** mode, unless `FORCE_SWITCH_TO_LOCAL` is set.
- **Local requests** go to `<ONT_IP>/<name>_app.cgi`.
- **Cloud requests** go to `REMOTE_URL` (taken from `cldRemoteUrl`). The production build ships an empty
  `REMOTE_URL`; only a device-farm build hard-codes `l1api.stg.homewifi.nokia.com`.
- **Hybrid "isRestToCGI" mode** sends the same CGI path to the cloud with a Bearer token. The cloud relays it to the
  Beacon. Examples: `getDeviceCapability`, `setOnboardFlag`.

### 3.3 Authentication (CONFIRMED mechanism; values not recorded)

- **Local login.** `POST login_app.cgi` with form body `name=…&pswd=…&srip=`. The JSON response contains
  `cookie:{sid,lsid}`, which later requests send back as a `Cookie` header with form-urlencoded content.
  Logout is `login_app.cgi?out`.
- **Admin password change:**
  - Beacon: `whw_onboarding_app.cgi` with `act=ConfigWhwAdminPswd`.
  - FWA: `service_function_app.cgi` JSON `GenericServiceCall`/`ChangePassword`, preceded by
    `whw_onboarding_app.cgi?nonce` and `?salt`. The password is processed client-side with CryptoJS
    (SHA-256/PBKDF2 present in `chunk-T2YGUJRY.js`).
- **Local TLS.** For local calls the app sets `cordova.plugin.http.setServerTrustMode("nocheck")`, so it does not
  validate the Beacon's HTTPS certificate. Cloud calls use `default` trust.
- **Cloud login.** `POST {REMOTE}/auth/token` with email and password, plus client-credential headers
  (`X-Service-Type: KC`, which suggests Keycloak). It returns an access token, a refresh token and a user UUID.
  Later calls send `Authorization: Bearer <token>`.
- **Optional SSO.** OAuth2 in a browser tab, redirecting to `nokiawifi://mobileapp/oauth2callback`. The SSO URLs
  come from the tenant `appinfo` config at `https://mappconfig.console.wifi.nokia.com/appinfo`.
- **Linking device to account.** `subscribers/subscribers/{uuid}/claim` with the root MAC and a claim PIN read
  from device capability.
- **FastMile (FMC).** A separate server login (`rest/auth/login`) issues its own Bearer token.

### 3.4 Live local data: WebSocket (CONFIRMED)

1. `POST websoc_session_app.cgi` with `command=Session_START{Mobile}&timeout=1800`. The matching stop command is
   `Session_STOP{Mobile}`.
2. Open `ws://<ONT_IP>:8099`. The first frame is `base64(username:password)` (the local credentials). The server
   replies `200 OK` or `401 Unauthorized`.
3. Event JSON follows, with these `event` types: `AllDeviceInfo`, `SSIDInfo`, `SSIDInfoChange`,
   `Wifi_Associated_Devices_Update`, `NewDeviceAdded`, `DeviceStatusUpdate`, `DeviceInfo`, `MeshNetwork`,
   `MeshLinks`, `ExtenderAdded`, `MeshNodeAdded`, `OnboardTimeout`, `OnboardMeshNodeAddedTimeout`.

In local mode, the inventory and mesh views are fed from this socket plus `device_name_status_app.cgi`. In cloud
mode they come from REST polling instead.

### 3.5 Mesh, backhaul and radio data

- **Mesh model (CONFIRMED).** The `MeshNetwork` shape is `{gw, aps[], links[]}`.
  - Each AP has: `id` (serial), `role` (`root`/`beacon`), `status`, `macaddress`, `ipaddress`,
    `backhaulQuality` (`GOOD`/`NORMAL`/…), `isbackhaul-connected`, `costtogateway`, `meshbackhaulnodes[]`
    (children), `ssids[]`, `isEthernetConnection`.
  - Each link endpoint has: `bssid`, `remote-bssid`, `medium`, `metric`, `port`, `state`, tx/rx bytes, packets
    and errors, `data-rate-tx/rx`, `stat-sample-time-ms`, `to-gateway`.

  The app derives throughput from byte deltas (`uspMeshMapper.deriveLinkRates`, `chunk-ZTUP5JXS.js`).
- **Cloud mesh (CONFIRMED).**
  - `home-hub/networks/{ROOT_MAC}/mesh?live=true|false`
  - `home-hub/networks/{ROOT_MAC}/members` (clients)
  - `device-management/devices/{MAC}/status`, which gives model, firmware, hw/sw id and a USP `endpoint_id`.
- **USP / TR-369 (CONFIRMED, cloud only).** For devices that report `endpoint_id`:
  - `POST rest-usp/agents/{ENDPOINT_ID}/message` with USP `OPERATE Device.X_ALU-COM_Wifi.GetMeshNetworkTopology()`;
  - `GET devicehub/devices/{MAC}/system/datamodel?path_param=Device.IP.Interface.1.…`.

  The app does not speak USP locally.
- **Client radio data (CONFIRMED, from DeviceInfo).** Per client: `rssi` (a per-band object means the client is
  MLO), `band`, `preferred_radio_band`, `ssid`, `gw` (the AP it is attached to), Ethernet `tx/rxPhyRate`.
  Streams come from `whw_zerotouchonb_app.cgi act=streamsinfo&mac=…`.
- **Radio settings (CONFIRMED, endpoints only).** The app exposes:
  - SSIDs via `wlan_list_app.cgi`, `wlan_status_app.cgi?oid=`, and `service_function2_app.cgi` JSON
    `{action:"WLANConfig"|"MLOConfig"|"RebootConfig", paralist}`;
  - guest/gaming via `wlan_config_app.cgi`;
  - country via `whw_wlcountycode_app.cgi`;
  - "optimize network" via `network_optimize_app.cgi act=OptimizeNetwork`;
  - MAC filtering via `wlan_macfilter_app.cgi`.

  "Band steering" appears only as UI text for multi-SSID band choice. **No** roaming, 802.11k/v/r or DFS settings
  were found.
- **EasyMesh / IEEE 1905.1 / Multi-AP: no evidence.** No such strings exist; the only "1905" matches are inside
  SVG path data. The link fields (`bssid`/`remote-bssid`/`medium`/`metric`) and the prplOS model "Beacon P19.1"
  look like what a prplMesh/EasyMesh-style stack would report. That is INFERRED only. The app treats the mesh as a
  Nokia-proprietary data model.

### 3.6 Adding extenders and onboarding (CONFIRMED)

- **Gateway first setup:**
  - `whw_onboarding_app.cgi` with `act=ConfigWhwPswd&wl_ssid=…&wpaKey=…`;
  - `whw_onboarding_status_app.cgi?status`;
  - `whw_gatewayrdy_status_app.cgi`.
- **Adding an extender by serial.** The serial is typed in or scanned from the label QR with ML Kit.
  1. `POST whw_zerotouchonb_app.cgi` with `act=AddBeacon&BeaconSrn=<serial>`.
  2. `GET whw_zerotouchonb_status_app.cgi?gmode=start|poll|get`. With `checkMesh` set, the same poll checks mesh
     quality.
- **Ethernet onboarding.** A separate flow (`IS_ETHERNET_ONBOARDING_FLOW`); Ethernet-to-Wi-Fi moves are also
  supported.
- **Removing an extender:** locally via `whw_zerotouchonb_app.cgi`; in the cloud via
  `subscribers/{uuid}/devices/{id}?force=true`.
- **Not used:**
  - **WPS:** no WPS calls.
  - **QR:** used only to read serials and to *generate* `WIFI:T:WPA;S:…;P:…;;` share codes.
- **BLE.** BLE is used for **FastMile 5G Receivers (outdoor units), not Beacons**:
  - scan for name prefix `Nokia`;
  - service `30839AC4-7D7E-415C-9A42-167340CF233C`, TX `2734594A-…`, RX `6604C4B2-…`;
  - payload is a JSON `{method,resource,id,data,version,headers}` CGI tunnel, encrypted with AES/CFB8
    (key = SHA-256 of a per-device password), and responses may be deflated.

## 4. Bridge/AP mode and model references (CONFIRMED)

**Bridge/AP mode:**
- Read with `GET whw_beacon_mode_app.cgi?getWorkMode`, which returns `workMode`, `has_bridge_wan`, `result` and
  `reason`. Values are `RGW` (routed) or `AP_BRIDGE`.
- Set with `POST whw_beacon_mode_app.cgi` and `act=setWorkMode&brEnable=0|1`. The Beacon then reboots.
- The feature is gated on capability `Settings.Bridge_Mode` and `CURRENT_CGI_VERSION >= BRIDGE_MODE_ONT_VERSION`.
- UI strings: "Enabling bridge mode will disable WAN configuration…", and "Profiles are disabled when your network
  is in bridge mode".
- WAN settings: `wan_list_app.cgi`, `wan_config_app.cgi`.

**Models (`BEACON_MODELS` in `chunk-C4KD4T5M.js`):**
- **Beacons:** Beacon, 1, 1.1, 2, 2E, 3, 3.1, 3.1.1, 3.3, 4, 6 (`HA-0336G-A`), 9, 10, 19, 19.1, P19.1 (prplOS), 24,
  G3.1, G6, G6.2. Most also appear as "Nokia WiFi Beacon …".
- **ONTs:** HA-140W-B, G-140W-C/H, G-240-G, G-240W-C/G/J, G-0425G-A/B, G-1425G-A/B, G-2425G-A/B, G-2426G-A/B,
  "Gateway 3".
- **FastMile:** 4G/5G Gateways 1–7.1, 5G Receiver (5G12/13/14/15/16/18/19/26/30 part numbers).

The CGI API version is tracked with constants of the form `BBDR23xx…BBDR2603_CGI_VERSION`. No firmware image URLs
were found. OTA is triggered on the device via `whw_ota_agent_app.cgi`.

## 5. Operation table

"Local" means `<gw-ip | www.webgui.Nokiawifi.com | nokiadevice.local>`; the app tries http and then https.
"Cloud" means the device-provided `cldRemoteUrl`.

| Operation | Transport | Endpoint / command (sanitized) | Auth | C/I | Evidence |
|---|---|---|---|---|---|
| Find gateway | Android DHCP info + HTTP probe | `login_app.cgi?chk` on gw-ip → webgui domain → `nokiadevice.local` | none | C | AndroidPlugin `getgatewayip`; ZTUP5JXS discovery fan-out |
| Device identity/capabilities | HTTP(S) local | `GET get_devmap_cap_status_app.cgi` | none or session | C | O5UGQCOY `Vo` class |
| Local login | HTTP(S) local | `POST login_app.cgi` `name,pswd` → `{sid,lsid}` | local admin creds | C | ZTUP5JXS `loginLocal` |
| Live events | WebSocket | `websoc_session_app.cgi Session_START{Mobile}` then `ws://gw:8099`, first frame base64(user:pass) | local creds + session | C | SKC2FBIM |
| Gateway status / WAN | HTTP local | `device_status_app.cgi`, `wan_internet_status_app.cgi`, `index_app.cgi` | cookie | C | ZTUP5JXS |
| Client inventory (local) | WS + HTTP | `AllDeviceInfo`/`DeviceInfo` events; `device_name_status_app.cgi`; `wlan_devices_status_app.cgi` | cookie | C | SKC2FBIM, ZTUP5JXS |
| Mesh/backhaul (local) | WebSocket | `MeshNetwork`, `MeshLinks` events | local creds | C | SKC2FBIM, O5UGQCOY |
| Extender list/status | HTTP local | `whw_zerotouchonb_status_app.cgi?gmode=get|poll` | cookie | C | ZTUP5JXS `getExtendersList` |
| Add extender | HTTP local | `POST whw_zerotouchonb_app.cgi act=AddBeacon&BeaconSrn=` | cookie | C | ZTUP5JXS `setSerialNumberExtender` |
| Wi-Fi config | HTTP local | `wlan_list_app.cgi`; `service_function2_app.cgi {action:WLANConfig/MLOConfig}` | cookie | C | ZTUP5JXS |
| Reboot (local) | HTTP local | `service_function2_app.cgi {action:RebootConfig}` | cookie | C | ZTUP5JXS `rebootRootLocal` |
| Bridge/AP mode | HTTP local | `whw_beacon_mode_app.cgi ?getWorkMode` / `act=setWorkMode&brEnable=` | cookie | C | ZTUP5JXS, T3WM3WDK |
| Optimize network | HTTP local | `network_optimize_app.cgi act=OptimizeNetwork` | cookie | C | ZTUP5JXS |
| Cloud login | HTTPS cloud | `POST auth/token` | email/pw + client headers → Bearer | C | ZTUP5JXS `loginRemote` |
| Cloud mesh / clients | HTTPS cloud | `home-hub/networks/{MAC}/mesh`, `/members` | Bearer | C | O5UGQCOY URL table |
| Beacon status (cloud) | HTTPS cloud | `device-management/devices/{MAC}/status` | Bearer | C | ZTUP5JXS |
| Mesh topology via USP | HTTPS cloud → USP | `rest-usp/agents/{EP}/message` OPERATE `Device.X_ALU-COM_Wifi.GetMeshNetworkTopology()` | Bearer | C | ZTUP5JXS `getMeshNetworkTopology` |
| CGI relayed via cloud | HTTPS cloud | same `*_app.cgi` path on cloud base | Bearer | C (relay mechanism I) | ZTUP5JXS `getHeaders` / `isRestToCGI` |
| Reboot (cloud) | HTTPS cloud | `devicehub/devices/{MAC}/system/reboot` | Bearer | C | O5UGQCOY |
| Tenant/app config | HTTPS | `mappconfig.console.wifi.nokia.com/appinfo` | API-key header (redacted) | C | O5UGQCOY |
| Receiver (5G) control | BLE GATT | JSON CGI tunnel, AES-CFB8 | per-device key | C | 6OP2DCVQ, BLEDataConversion |

## 6. Unknowns and what would confirm them (not performed)

1. **Exact local response schemas** for `get_devmap_cap_status_app.cgi`, `whw_zerotouchonb_status_app.cgi`, the
   `MeshNetwork`/`MeshLinks` WS frames, and `whw_beacon_mode_app.cgi`. To confirm: read-only GETs and a WS capture
   on the user's own Beacon, from a LAN client, after logging in with the user's own admin account.
2. **Whether the user's Beacon firmware reports `Cloudless_Support=1`**, which would make it local-only, and its
   `devVer`. Read the device-capability response on the LAN.
3. **Whether Beacons in bridge mode** still serve `login_app.cgi` and port 8099 on their LAN IP, and whether
   `www.webgui.Nokiawifi.com` still resolves once the Beacon is not the DHCP/DNS server. Test on the user's own
   network.
4. **Whether HTTPS is served locally**, and with what certificate. The app skips verification, so it cannot tell
   us.
5. **The `backhaulQuality` scale** beyond GOOD/NORMAL, and the units of `metric`/`data-rate-*` (the code suggests
   kbps). To confirm: observe live frames while moving an extender.
6. **Whether the cloud relays `isRestToCGI` requests over TR-069/USP or another tunnel.** This is server-side and
   cannot be determined from the app.
7. **EasyMesh/1905.1 on the wire.** To check: a passive capture of 1905 ethertype 0x893a between the user's Beacons.
   The app gives no evidence either way.
8. **Signer provenance.** Compare the certificate SHA-256 with one from a Play-installed copy (for example via
   `adb shell pm` on a phone that has the official install).
