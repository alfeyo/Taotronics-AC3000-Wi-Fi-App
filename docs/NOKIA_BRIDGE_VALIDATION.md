# Nokia bridge and mesh validation

Verified 18 October 2026, Africa/Lusaka. This supersedes the earlier powered-off / official-app-only preparation notes.

## Wireless-root determination: requires wired root uplink

**Root-to-TaoTronics wireless uplink is unsupported in the verified setup.** Retain TaoTronics LAN → Ethernet → root Beacon WAN, with Nokia-to-Nokia wireless backhaul preferred for the second unit. No cable-disconnection test or root mode change is warranted: no supported reversible third-party station/uplink procedure was established for Beacon 2 hardware `3FE49294BAAA`, firmware `3FE49334IJJJ09`, CGI 5.5. This is a finding about this firmware and router combination, not a claim that every Nokia/EasyMesh implementation lacks wireless agent operation.

### Evidence and limits

Authenticated read-only evidence is preserved in [the sanitized endpoint record](evidence/nokia-beacon2-uplink-2026-10-18.json). Login succeeded with the owner's authorized local credentials; credentials, session cookies and keys are excluded. No configuration endpoint was written during this investigation.

| Read / source | Observation and implication |
|---|---|
| `device_status_web_app.cgi` | Model, hardware, firmware and serial match the provisioned root |
| `whw_beacon_mode_app_status_web_app.cgi?getWorkMode` | `AP_Bridge`; bridge mode changes routing behavior, not a third-party Wi-Fi association |
| `main_web_app.cgi` | `IS_AP_BRIDGE_MODE=1`, `HAS_WIFI_PORT_MODE=0`, `can_end_user_config_wifi_port_mode=0`, `HAS_PORT_MODE=0`; `g_has_connection_mode=1` is not station-mode evidence |
| Discovery capability response | Bridge_Mode, Network_Mode, AP WiFi_Onboarding and Ethernet_Onboarding are enabled. The official app uses AP WiFi_Onboarding in its **extender** flow. RGW Scan_and_Connect is not evidence of a wireless WAN |
| Firmware WebGUI main/network modules | Mode control is `brEnable`; WAN IP choices are DHCP, static and PPPoE. No supported upstream SSID/credential association, WISP, universal repeater, station/client or interoperable WDS workflow was found |
| Official app source | Wi-Fi onboarding routes to extender setup. “Repeater” hits are animation-library modifiers; WDS substring hits are operator identifiers/embedded binary data, not network controls |
| `mesh_status_web_app.cgi` | Root MAC matches, `OnboardStatus=ROOT`; empty beacon list, 0 of maximum 6 entries |
| `wan_internet_status_web_app.cgi` | `gwwanup=1`; reports uplink health but not its medium or client internet success |
| `lan_status_web_app.cgi?lan` | One LAN record reports `NoLink`. It is not the WAN-port state and does not override the existing physical wired-root observation |

[Nokia's networking-mode documentation](https://wifi-helpcenter.nokia.com/hc/en-us/articles/4421210042263-Overview-of-networking-modes) explicitly defines bridge-mode Wi-Fi/Ethernet backhaul as links **between Beacons**. The [Beacon 2 guide](https://www.nokia.com/asset/i/215103/) documents EasyMesh and a WAN Ethernet installation, but does not establish TaoTronics controller interoperability. The TaoTronics protocol/radio investigation has not established a compatible EasyMesh controller or WDS procedure. Generic EasyMesh support alone cannot authorize a working cross-vendor wireless link.

Firmware source fingerprints (SHA-256):

- `main.c2e6eb720d33b3e7702c.js`: `a05f5abc0342bd704cacd16586cbd1781065020941c66071671e51ceb750431c`
- Network module `5.0cef732063d8394e86ac.js`: `5a797a58905ecd0021cd0a2205ce2bfd2d15c83b57694a2919094e242d03c394`

### TT Router 1.9.1+18

The Nokia Mesh screen shows **Requires wired root uplink** only for the reviewed Beacon 2 firmware. Other firmware gets an unverified-capability message. It separates required Ethernet root wiring from supported Wi-Fi/Ethernet Nokia-extender methods, labels live link type as unreported, and uses the existing WAN health and phone-bound client checks. WAN health becomes unknown after 90 seconds or a failed refresh; mesh inventory is marked stale. There is no speculative upstream-network selector or repeater toggle. No new configuration protocol or credential format was added.

Validation of this release:

- `flutter analyze --no-pub`: no issues. `flutter test --no-pub`: **216 tests passed**, including firmware scoping, unknown/offline/stale/failed WAN status and three screen sizes.
- CodeRabbit reviewed the app/documentation diff and raised **0 issues**. Hardware also showed the cached mesh inventory becoming stale after the freshness window.
- Release APK built successfully and installed in place on Fold4 `RFCTB0AH5BN`; Android reports version `1.9.1`, build `18`. The existing sideload signer matched; app data and secure credentials were preserved. The build retains the existing plugin KGP migration warning.
- Fold4 saved-root reconnect succeeded, read-back remained AP_BRIDGE, and the new wired-root panel rendered without clipping. Client verification passed again: phone `192.168.10.217`, TaoTronics DHCP/default gateway `192.168.10.1`, stable Nokia Wi-Fi association and bound HTTPS internet. The add-extender action became available only after that check.
- Argon dashboard service active; `/devices` and `/api/v1/gateway` returned 200. Gateway reports Ethernet `eth0` online through `192.168.88.1`, VPN mode/state off and health OK. No Argon configuration was changed. TT Router still displayed live TaoTronics inventory (24 devices at the observation).
- APK: `artifacts/releases/tt-router-1.9.1-18.apk`, SHA-256 `b904a088273670763558d595987493edfd3e4eb800c88db58bb6260b1f07e6a5`. Prior 1.9.0 artifact retained. OnePlus remains unavailable.

### Recovery and second-node readiness

Keep the current root cable and AP bridge configuration. If management becomes unavailable, rejoin NOKIA-E6C0, rediscover its current TaoTronics DHCP address, and reconnect the saved identity; a changed RSA key must not receive automatic credential replay. Do not factory-reset the working root. Application rollback source is `2bc6c5b`; preserve `artifacts/releases/tt-router-1.9.0-17.apk`. Rebuild that source with a higher Android build number if an in-place rollback is needed; do not uninstall or clear secure storage.

After the root/client path check, the owner can power the second unit near the root, leaving its Ethernet disconnected, and provide its printed model and ALCL serial. Use the existing serial enrollment action only after checking compatibility. Observe the real node model/firmware, root relationship, reported backhaul and signal before claiming success. Then verify DHCP/internet from its radio, coverage at the intended location and the root's behavior while the extender is offline. These physical checks remain pending; an empty inventory cannot validate them.

## Root: verified on hardware

| Item | Observation |
|---|---|
| Model | Nokia WiFi Beacon 2; hardware 3FE49294BAAA |
| Identity | ALCLB4392160; root MAC b4:63:6f:db:e6:c0 |
| Firmware / local API | 3FE49334IJJJ09 / CGI 5.5 |
| Physical uplink | Existing TaoTronics LAN → root uplink, left in place |
| Factory state | NOKIA-E6C0; routed management 192.168.18.1; WAN 192.168.10.101 |
| Owner management | Printed local admin credentials; encrypted WebGUI nonce/RSA/AES exchange from TT Router; stored separately in Android secure storage |
| Mode change | Sent from TT Router through the verified local WebGUI bridge endpoint |
| Read-back | Same serial/MAC, AP_Bridge; management DHCP address 192.168.10.97 |
| Client | Fold4 on b4:63:6f:db:e6:c9 (2.4 GHz), then …:cd (5 GHz), SSID NOKIA-E6C0 |
| Client DHCP / gateway | 192.168.10.217/24; Android DHCP event reports server 192.168.10.1; default gateway 192.168.10.1 |
| Internet | Wi-Fi-bound HTTPS generate_204 returned 204 |
| Preserved controls | Fold4 retained TaoTronics pairing; live TaoTronics device inventory and Argon traffic visible through Nokia |

The client observation verifies a bridged path without a Nokia NAT hop for that client. It does not prove that no rogue DHCP server exists anywhere on the network. The LAN configuration CGI still exposes an enabled, old 192.168.18.x DHCP configuration, while actual AP-mode client provisioning came from TaoTronics. Do not infer active DHCP service from that stored configuration alone.

Factory SSID and security were retained. No household SSID/password, TaoTronics wireless profile, Argon routing/firewall/NAT/DHCP/VPN/SSH setting was changed in this phase. A household-SSID migration still needs owner approval.

## Second Beacon: pending owner activation

The root reports an empty `beacon_detail` list, 0 entries and maximum capacity 6. After closing the root wireless-uplink finding and re-verifying the client path, the owner was asked to power the second Beacon near the root, leave its Ethernet disconnected, and provide its printed model and ALCL serial. No second-node enrollment or removal has occurred.

TT Router prepares local encrypted `mesh_web_app.cgi?add` / `?del` commands verified from this root’s WebGUI. Addition requires a fresh bridge/client-path check, a distinct valid serial, available capacity and explicit UI confirmation that the unit is powered on. Acknowledgment is pending until the inventory is read back; listed enrollment alone is not mesh connectivity or backhaul verification. Backhaul, coverage, roaming and cross-model compatibility remain unverified.

## Validation limits

- OnePlus is not currently attached; no 1.9.0 installation or physical navigation claim is made for it.
- Narrow, Fold-sized and landscape rendering are covered by Flutter widget tests.
- Native IPv6 discovery remains a candidate path; this successful Android management session used IPv4. The factory IPv6 endpoint was independently reachable through phone-bound curl.
- Firmware/radio/guest write payloads are not fully validated for Nokia; there are no speculative buttons for them. Current radio/security/channel settings are read-only.
- The root’s local mobile login endpoint rejected this firmware’s owner login. The verified WebGUI flow is deliberately gated to Beacon 2 / CGI 5.5.
