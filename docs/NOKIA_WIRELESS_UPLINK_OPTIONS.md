# Nokia uplink recovery and dedicated wireless bridge options

18 October 2026, Africa/Lusaka. **Final feasibility audit: TT Router 1.9.2+19.** Read-only inspection of existing APK, device WebGUI sources, recorded authenticated responses and Flutter code; no new router requests, cable removal or production configuration changes. Second-Beacon role replacement is assessed below, not performed. The previously approved Beacon 1 SSID migration is recorded separately in [current validation](NOKIA_BRIDGE_VALIDATION.md).

## Final compatibility verdict

**No supported direct Wi-Fi upstream from TaoTronics TT-ND001 to this Nokia Beacon 2 was found. Keep the root Ethernet uplink.** Installed firmware: `3FE49334IJJJ09`, hardware `3FE49294BAAA`, local API CGI 5.5. Neither its exposed API nor the reviewed Nokia onboarding implementation supplies a verified operation to select a third-party upstream BSSID/SSID and associate using its credentials. TaoTronics' reviewed protocol supplies no matching interoperable WDS/four-address or EasyMesh controller enrollment method.

This closes the supported-interface investigation. It does not prove that the chipset could never implement another mode: no full firmware filesystem, kernel or driver image was audited. No speculative endpoints or firmware writes were attempted. A future vendor-supported procedure for these exact versions would be new evidence; generic bridge/backhaul labels are insufficient.

### Actual source and device evidence

Fingerprints and reproducible search patterns are in [the audit manifest](evidence/nokia-wireless-bridge-audit-2026-10-18.json). APK provenance and signer-verification limits are in [the protocol investigation](NOKIA_PROTOCOL_INVESTIGATION.md). The audit covered 407 top-level APK JavaScript assets, the Nokia native plugin, existing firmware WebGUI main/network bundles and recorded API responses.

| Evidence | What it establishes |
|---|---|
| `AndroidPlugin.java:437`, `connectToSSID`, Android `WifiManager.addNetwork` / `enableNetwork` | Connects the **phone**, not a Beacon station interface. |
| `chunk-RZ4D673W.js`, `encryptScanSSIDDetails`, `QRSCANNED_DATA` | Apparent SSID scan references belong to QR onboarding and log redaction, not router upstream scanning. |
| `chunk-N6TIFTLF.js`, `goToExtenderOnboardingFlow`, `getAPOnboarding("WiFi_Onboarding")` | Wireless onboarding capability selects the **Nokia extender** flow. |
| `chunk-ZTUP5JXS.js`, `setSerialNumberExtender` | Submits `act=AddBeacon&BeaconSrn=<Nokia serial>` to `whw_zerotouchonb_app`; no third-party upstream credentials. `ConfigWhwPswd` changes the broadcast network. |
| `chunk-O5UGQCOY.js`, `isDynamicBackhaulSupported`; `chunk-Q47COLNM.js`, `TestConnectionExtenderPage` | Generic dynamic-backhaul capability is used for extender signal prediction. `Dynamic_Backhaul` is absent from this root's captured `AP_Onboarding` block. |
| `RGW_Onboarding.Scan_and_Connect=1` | A capability flag without a verified root station-association operation. Similarly named receiver scan/connect timeouts belong to the separate Bluetooth receiver workflow; they do not establish this flag's meaning. |
| Authenticated `main_web_app.cgi` | `HAS_WIFI_PORT_MODE=0`, `can_end_user_config_wifi_port_mode=0`, `HAS_PORT_MODE=0`, `g_has_bridge_wan_set=0`. `g_has_connection_mode=1` does not establish station mode. |
| Firmware network bundle and `wan_config_glb_status_web_app.cgi` | IP/PPP connections, `IP_Routed` / `IP_Bridged`, DHCP and interface bindings; no verified upstream SSID selection or association payload. |
| Root mode/topology read-back | `AP_Bridge`, root role `ROOT`, no extenders. Bridge forwarding mode is distinct from radio upstream association. |
| TaoTronics `GetExistNode`, `SetMeshInitByBt`, `Get/SetWirelessInfoList` | TaoTronics node enrollment and client-facing AP SSIDs. The latter's password field is not an upstream station credential. See [protocol handoff](ROUTER_PROTOCOL_HANDOFF.md). |

Case-insensitive searches found no WISP, WDS, station/client-mode, wireless-WAN, upstream-SSID, four-address or EasyMesh/1905 identifiers in the APK JS corpus. These negative results support the traced call paths; they are not independent proof of hardware incapability. False positives: `4addr` inside IPv4 address names; `repeater` in animation code; `wisp` inside `currentViewIsPortrait`; controller/agent proximity in `AbortController` with `navigator.userAgent`.

The APK's cloud `rest-usp/agents/...` and `GetMeshNetworkTopology` operations are management/topology paths. “Agent” there does not establish EasyMesh agent enrollment. Hidden radio BSSIDs alone likewise establish no common backhaul protocol.

Nokia explicitly describes bridge-mode wireless backhaul as the link **between Beacons**, with the third-party router providing addresses. Its Beacon 2 guide mentions EasyMesh, but does not establish the necessary controller/agent pairing with TT-ND001. TaoTronics' vendor-authored guide describes adding TT routers to its own mesh, with wired, wireless and combined arrangements; it gives no cross-vendor enrollment procedure. [Nokia networking modes](https://wifi-helpcenter.nokia.com/hc/en-us/articles/4421210042263-Overview-of-networking-modes), [Beacon 2 guide](https://www.nokia.com/asset/i/215103/), [TT-ND001 guide, pages 5–7](https://fccid.io/2AVUHTT-ND001/User-Manual/User-Manual-4842956.pdf).

### Flutter/API decision

There is **no verified upstream method waiting for a missing Flutter button**. No application change or isolated configuration experiment is justified by this audit. Existing root-uplink warnings and Wi-Fi-bound diagnostics remain appropriate.

| Existing operation | Exact implementation and required verification |
|---|---|
| Owner authentication | `NokiaService` uses `/login_web_app.cgi?nonce`, vendor nonce/crypto exchange, session cookie and CSRF token, with identity/public-key checks. Reuse this implementation. |
| Nokia extender enrollment | `changeExtender`: encrypted POST `/mesh_web_app.cgi?add` with `SerialNumber` and `csrf_token`. Requires authenticated, identity-matched AP bridge root and capacity/duplicate checks. `result=0` acknowledges the request only. |
| Enrollment verification | Refresh `/mesh_status_web_app.cgi`: exact serial/MAC, root/extender relationship, connected state and wireless medium. Require reported backhaul signal if available; missing RSSI stays unknown. Verify actual client BSSID, DHCP/gateway, DNS and Wi-Fi-bound HTTPS through that node. Inventory presence alone is insufficient. |
| AP bridge mode | `enableBridge`: encrypted POST `/whw_beacon_mode_app_web_app.cgi`, `act=setWorkMode&brEnable=1&csrf_token=...`; read `/whw_beacon_mode_app_status_web_app.cgi?getWorkMode` after recovery. Changes forwarding mode, not upstream association. Already completed; do not repeat. |
| Direct TaoTronics Wi-Fi uplink | No verified authenticated scan, credential-submission, association or status sequence. Do not synthesize an endpoint or control. |

References: [service](../lib/services/nokia_service.dart), [provider](../lib/providers/nokia_provider.dart), [screen](../lib/screens/nokia_mesh_screen.dart). The provider already distinguishes enrollment listing from connectivity/backhaul verification; the screen warns that the root requires Ethernet.

## Smallest supported implementation path

**Prefer one Nokia root beside TaoTronics, connected by a short LAN → WAN cable, and a second Nokia at the coverage location using Nokia wireless backhaul.** No additional bridge hardware is needed if the second Beacon is compatible and the radio path is adequate. Power is needed at both locations. Identify the second unit by model and printed ALCL serial before enrollment.

- **Least disruption:** retain the configured root identity, reposition that root near TaoTronics during an approved interruption, and enroll the second Beacon as the remote extender. Test near the root first, then at its intended location. No role reversal is necessary.
- **If the first unit must stay remote:** the second Nokia can become the wired root and the first its wireless extender, subject to compatibility and supported provisioning. This changes which Nokia has the short cable; it does not let either root join TaoTronics Wi-Fi. Nokia's documented root-replacement procedure creates a new network and requires resetting the root and extenders, erasing settings. Do not assume a reversible role-toggle exists in TT Router. Record settings and obtain approval for that interruption/reset first. [Nokia root replacement](https://wifi-helpcenter.nokia.com/hc/en-us/articles/360060143514-Replace-the-root-device-in-your-Nokia-WiFi-network).

If neither Nokia can be placed near TaoTronics, evaluate the matched bridge pair below. It uses TaoTronics **LAN**, not its existing Wi-Fi SSID, for entry into a separate radio link. It is not native TaoTronics–Nokia mesh. No spare bridge hardware is available; no single client adapter has been qualified here.

## Cable-disconnection observation

At approximately 19:15 local time, after the owner reported disconnecting the root Ethernet cable:

- The Fold4 was initially on **TaoTronics** BSSID `80:c5:48:50:35:ae`, SSID `Nokia Wifi`, address `192.168.10.69`. Its connectivity was not evidence of a working Nokia path.
- The root API at its previous `192.168.10.97` address timed out from the household LAN.
- An explicit phone connection to `NOKIA-E6C0` associated with Nokia BSSID `b4:63:6f:db:e6:cd`, WPA2, 5 GHz, RSSI −18 dBm. **The phone had no IPv4 address.** Android subsequently disconnected and returned to TaoTronics. Existing Android logs also report DHCP failures for this profile. A strong radio signal did not provide a functioning uplink.
- No successful Nokia-bound internet check or wireless upstream association was established. The Nokia radios remain active; root-to-gateway reachability and a changed management IP cannot be established while its management path is unavailable. Do not invent an address or switch to static-IP/router mode to force a result.
- A gateway ping attempted without a Wi-Fi address selected a cellular source and failed. It is excluded as evidence of a correctly bound Nokia gateway test.
- Argon API stayed available: Ethernet `eth0` online via `192.168.88.1`, VPN off, gateway health OK. The Fold4 reacquired a TaoTronics lease after the unsuccessful Nokia association.

**Recovery verified:** the owner reconnected the same TaoTronics LAN → Nokia root WAN Ethernet cable. The same root identity replied at `192.168.10.97`; authenticated AP bridge read-back passed. Fold4 associated to root BSSID `b4:63:6f:db:e6:cd`, address `192.168.10.217`, with TaoTronics DHCP and gateway `192.168.10.1`. TT Router 1.9.2+19 connection diagnostics and the separate client-path verification both passed Wi-Fi-bound HTTPS. Client RSSI was −42 dBm at this location, not a backhaul/coverage measurement. Argon remained online on `eth0`, VPN off. No reset, broadcast/security change or speculative firmware command was used.

## Architecture decision

| Architecture | Assessment | Required hardware / status |
|---|---|---|
| A: TaoTronics LAN → Ethernet → Nokia root → wireless Nokia extender | Preferred. Wired root and phone internet were previously hardware-verified. Nokia-to-Nokia backhaul is supported, but this second unit is not enrolled/tested. | Root restored and phone internet reverified. Second-unit enrollment is outside the current owner-directed scope. |
| B: existing TaoTronics Wi-Fi → one client bridge → Nokia WAN | No specific device has been verified to meet transparent multi-MAC/DHCP requirements with TaoTronics. Do not deploy based on “client mode” marketing alone. | Owner confirms no spare bridge hardware. Additional hardware would be required; no compatible single-client model has been qualified. |
| B variant: TaoTronics LAN → short cable → bridge A ⇄ bridge B → short cable → Nokia WAN | A dedicated matched bridge link avoids requiring TaoTronics to implement a compatible wireless bridge protocol. It replaces the long cable, not all Ethernet. Hardware and placement remain untested here. | Matching bridge pair, approved power supplies/injectors, two short cables and a viable radio path. Keep production Argon separate. |

An ordinary station link does not provide transparent multi-MAC forwarding. MikroTik documents that pseudobridge uses MAC translation and has non-IP limitations; its true station-bridge mode requires a compatible RouterOS AP. Therefore a spare MikroTik client alone is not a verified transparent bridge to TaoTronics. [MikroTik station-mode documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/122388518/Wireless+Station+Modes)

The TP-Link TL-WR902AC provides client mode for Ethernet devices, but its guide does not establish transparent multi-client MAC forwarding for a bridged Nokia mesh. Treat it as unqualified for this requirement until tested; routed/WISP mode would introduce another routing/NAT layer. [TP-Link client-mode guide](https://www.tp-link.com/pl/support/faq/1504/)

A concrete matched-pair candidate is **TP-Link Omada EAP211-Bridge KIT**: the vendor documents automatic main/client pairing and multiple Ethernet ports. Its setup guide uses an upstream DHCP server. This supports evaluating the paired architecture; it is not proof of this household's DHCP/MAC transparency or radio coverage. The current product page selects V3, while the linked 2025 guide may cover an earlier revision: confirm the purchased regional revision, matching manual, power requirements and firmware before purchase. Local availability and household performance are unverified. [Product](https://www.omadanetworks.com/us/business-networking/omada-wifi-wireless-bridge/eap211-bridge-kit/), [setup guide](https://static.tp-link.com/upload/manual/2025/202504/20250418/Bridge%20AP%20Start%20Guide.pdf)

A dedicated pair needs appropriate placement and power; walls, distance and interference can make a nominal link unsuitable. No vendor range/PHY-rate claim is a measured household result.

Required capabilities: genuine bidirectional Ethernet bridging of multiple source MACs over the pair's documented radio protocol; no extra NAT, DHCP server or MAC pseudobridge; secured radio association; visible peer identity, RSSI/SNR and link state; persistent configuration and automatic reconnect after power/RF loss. Preserve Ethernet MTU, broadcast/multicast and any VLANs actually used. A single client device would instead need a verified compatible four-address mechanism at **both** it and TaoTronics; that prerequisite is missing. Two matching bridge endpoints avoid relying on TaoTronics' Wi-Fi implementation.

## Acceptance checks before replacing the long cable

1. Bench-test off the production LAN using an isolated test router/DHCP server and two clients with distinct MACs. Confirm intended peer BSSID/association, secured link, RSSI/SNR and counters. Disable any bridge DHCP server/NAT and set non-conflicting management addresses before a later household LAN test. Do not use Argon's interfaces as the test router.
2. With approval for the household attachment, leave the Nokia root's working uplink intact and connect only isolated test clients behind the pair. Both must obtain TaoTronics `192.168.10.x` leases and gateway/DHCP `192.168.10.1`. Check Ethernet source MACs, DHCP records and upstream ARP together: distinct lease client IDs alone do not prove transparency. Verify simultaneous bidirectional same-LAN access, lease renewal, DNS and internet. Check bridge configuration and client routes for absence of extra NAT; traceroute alone is insufficient.
3. Record source configurations, addresses and cabling. Prepare the original Ethernet path for immediate recovery. Do not connect parallel bridged paths and create a loop.
4. Only after a separate bench pass, schedule/approve the root uplink change, including root/extender management, DHCP, gateway, DNS and Wi-Fi-bound HTTPS checks from actual Nokia BSSIDs at cutover.
5. Check broadcast ARP, multicast mDNS/SSDP and required multicast services; test IGMP/MLD behavior where used. If IPv6 exists upstream, verify RA/SLAAC, NDP, DHCPv6 where offered, same-LAN reachability and internet. Otherwise record IPv6 as untested and use an isolated IPv6 lab before claiming support. Check MTU and VLAN preservation where relevant. Test each bridge reboot, both rebooting together, upstream restart in the isolated lab, and RF loss/recovery: the pair and clients must recover without manual configuration or stale DHCP state. Repeat recovery three times, then perform a 24-hour concurrent-client soak at the intended locations, recording loss, latency, throughput and outages. These are proposed acceptance tests, not completed measurements.
6. At approved cutover, use **break-before-make**: remove the old root uplink before inserting the bridge-fed cable, never create parallel forwarding paths. Retest the root and each enrolled extender with actual BSSID-bound clients. Walk between Beacons and record BSSID transitions and application continuity. Shared SSID alone proves neither backhaul nor roaming.
7. On any failed acceptance check, disconnect the replacement path and restore the original root cable. Preserve Argon Ethernet, VPN, NAT, DHCP, firewall, Tailscale and backup configuration throughout.

## Nokia mesh and broadcast changes

The owner has set the second unit aside and directed work to Beacon 1 only. No serial/model was supplied. Its association, backhaul medium/RSSI, internet and coverage remain unverified. The root is restored. Following explicit owner approval, both primary bands now broadcast `Nokia Wifi` with the existing household password and WPA2/AES; authenticated read-back and Fold4 Wi-Fi-bound HTTPS passed on both Nokia radios. See [current validation](NOKIA_BRIDGE_VALIDATION.md). No management-name write was sent. Distinct management names remain separate from a shared SSID.

## Audit validation

Documentation-only change: evidence JSON parses, source fingerprints/search counts were generated from the existing corpus, relative documentation links resolve and `git diff --check` passes. Flutter tests/build were not rerun because application code is unchanged. Physical results above are the recorded prior tests, not a new live health measurement. No enrollment, reset, broadcast change, bridge purchase or Argon configuration change occurred in this audit.

## Enrollment-level follow-up

See [Nokia enrollment protocol and Pi feasibility](NOKIA_ENROLLMENT_PROTOCOL.md) for the traced Add Beacon calls, version gates, firmware handshake boundary, spare-Pi requirements and deferred reference test. The app delegates enrollment to the Nokia root; the exact over-air authorization/key exchange remains unknown. No compatible TaoTronics controller or fully wireless Pi-to-Nokia path has been demonstrated. TT Router now observes the verified local mesh endpoint with bounded reads; no production network changes were made.
