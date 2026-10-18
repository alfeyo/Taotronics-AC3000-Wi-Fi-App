# Nokia enrollment protocol and intermediary feasibility

18 October 2026. Baseline: installed TT Router 1.9.2+19, Nokia Beacon 2 `3FE49334IJJJ09` / CGI **5.5**, root `ALCLB4392160` in AP_Bridge at `192.168.10.97`. The root's Ethernet uplink and approved household `Nokia Wifi` configuration remain unchanged. The owner deferred the second-Beacon hardware test until later.

## Findings and evidence boundaries

The app initiates enrollment by submitting an extender serial **to the authorized root**. It observes the root's mesh inventory/events afterward. Phone setup-network switching is a separate Android operation. No app-side implementation of the radio handshake, backhaul key derivation or four-address forwarding was found. Those functions are delegated to device firmware; their exact implementation is **not established** by this APK.

This is a call-path reconstruction, not a claim that the two devices have now been enrolled. A complete packet-level sequence cannot honestly be supplied without the deferred reference enrollment or appropriate firmware implementation evidence. In particular, the absence of an app WPS/DPP call does **not** rule out WPS/DPP inside firmware. The older protocol note's “WPS not used” statement is narrowed accordingly.

Evidence levels:

- **Observed:** earlier authenticated responses/physical root tests, linked in [bridge validation](NOKIA_BRIDGE_VALIDATION.md).
- **Static:** exact calls/branches found in the existing APK or device-delivered WebGUI. This establishes implementation, not execution on this device.
- **Inference:** likely division of responsibilities, awaiting a radio capture or device report.
- **Unknown:** not present in the available evidence; never synthesized as success.

APK provenance and SHA-256 are in [the original investigation](NOKIA_PROTOCOL_INVESTIGATION.md); [the audit manifest](evidence/nokia-wireless-bridge-audit-2026-10-18.json) fingerprints the main sources. The previously decompiled APK was reused, not executed or decompiled again. Relevant native code is `nokia/prism/AndroidPlugin.java`; native libraries identified earlier are barcode/image/SQLCipher libraries, not an exposed Beacon backhaul implementation. BLE receiver code is a separate FastMile path.

The deeper trace has a separate [source-anchor manifest](evidence/nokia-enrollment-call-paths-2026-10-18.json), with SHA-256 and character offsets for the routed pages and version gates.

## Active call graph and firmware version gates

The route table in `assets/public/main.js` resolves these concrete components:

```text
NetworkDevicesPage.goToAddDeviceFlow       chunk-ZLHSKOKF.js
  ├─ CGI >= 6.6: onboarding-state gate    [not this CGI 5.5 root]
  └─ goToExtenderOnboardingFlow
       ├─ WiFi_Onboarding available → extender-tips / extender-guide
       └─ Ethernet-only capability → extender-scan
ExtenderScanPage / ExtenderSetSerialNumberPage
  chunk-V6S6RRMA.js / chunk-XRW5DKG6.js
  ├─ QR or manual serial (newer versions also use MAC)
  ├─ CGI >= 5.7: getExtendersList duplicate check
  └─ saveSerialNumber → API.setSerialNumberExtender
       → whw_zerotouchonb_app.cgi: act=AddBeacon&BeaconSrn=<serial>
       → result=0 OR reason=409 → extender-expand-network
ExtenderExpandNetworkPage                 chunk-KCTERXP4.js
  ├─ optional phone location test
  └─ skip → plugin-extender
PluginExtenderPage                        chunk-ZTLFBESH.js
  ├─ Ethernet flow → SearchExtenderPage
  └─ wireless → navigateToNextpage
       ├─ CGI >= 5.9 + MAC → beacon-name-edit
       └─ extender-connection-in-progress → network-devices map
```

The version constants in `chunk-C4KD4T5M.js` are explicit: BBDR2301 = **5.7**, BBDR2402 = **5.9**, BBDR2602 = **6.6**, BBDR2603 = **6.7**. Thus the current root does not qualify for the newer app onboarding-state writes (`OnBoardStatusMapp=InProgress` / timer reset). TT Router does not transplant them to CGI 5.5.

`chunk-ZTUP5JXS.js` still contains `zeroTouchOnboardingStart` and `zeroTouchOnboardPoll` request builders (`gmode=start|poll`), but searches of the inspected JS corpus found no external callers. They are **not** established required steps of this build's active Add Beacon route. In contrast, `SearchExtenderPage` (`chunk-VZCV73KJ.js`) actively reads `getExtendersList` every five seconds in its Ethernet path, with a 390-second screen timeout. It maps `NotDetected`, `Detected`, `Configured`, `ConfigurationFailed`, `ConfigurationSucceeded`; it even maps `ConfigurationFailed` to a configuring animation. TT Router must not copy those presentation shortcuts or assume those enums occur in the distinct WebGUI response.

## Enrollment sequence

The first half describes factory-root setup; it is already completed on the household root and must not be repeated. Dashed firmware arrows below are the unresolved reference-test boundary.

```mermaid
sequenceDiagram
    actor Owner
    participant Phone as Android / Nokia app or TT Router
    participant Root as Authorized Nokia root
    participant Ext as Factory-reset Nokia extender
    participant GW as TaoTronics DHCP / gateway
    Owner->>Phone: Select/scan root label, authorize local owner login
    Phone->>Phone: Join setup SSID using Android Wi-Fi
    Phone->>Root: Discovery + identity/capability reads
    Root-->>Phone: Serial, MAC, CGI version, readiness/capabilities
    Phone->>Root: Owner authentication (verified WebGUI crypto for CGI 5.5)
    Root-->>Phone: Authorized session
    Note over Phone,Root: Root SSID/AP_Bridge setup already verified; preserve it
    Root->>GW: Existing Ethernet LAN bridge path
    Owner->>Phone: Approve activation and supply second unit identity
    Phone->>Root: Add extender serial (authenticated)
    Root-->>Phone: Acknowledgment only
    Note over Root,Ext: Firmware-managed discovery, authorization, key exchange and radio association
    Root-->>Ext: Exact over-air exchange remains unobserved
    Ext-->>Root: Exact association/role/configuration exchange remains unobserved
    Phone->>Root: Read exact serial's inventory/topology/status
    Root-->>Phone: Reported onboarding/backhaul fields; missing fields remain unknown
    Owner->>Phone: Connect test client specifically through extender
    Phone->>GW: DHCP, gateway, DNS and Wi-Fi-bound HTTPS checks
    Note over Phone,Ext: Require actual BSSID/link evidence before declaring wireless success
```

## Operation and responsibility table

Live credentials and session values are deliberately omitted. Symbolic parameters describe the protocol, not runnable production commands.

| Operation | Calling component / controlled party | Endpoint or protocol | Authentication | Parameters | Expected response | Resulting state | Evidence source | Confidence |
|---|---|---|---|---|---|---|---|---|
| Read root label | QR scanner / phone | Camera QR or manual entry | Physical owner input | SSID, device model, serial; label credentials where encoded | Parsed label data | Candidate only, not trusted identity | `chunk-RZ4D673W`, native scanner | Static |
| Join setup network | AndroidPlugin / **phone interface** | Android WifiManager | Printed setup key entered by owner | SSID and key | Android association | Phone can attempt local management; no root uplink change | `AndroidPlugin.java:437–465` | Static + prior phone test |
| Discover root | API service / phone | `login_app.cgi?chk`; DHCP gateway, `www.webgui.Nokiawifi.com`, `nokiadevice.local`, HTTP/HTTPS candidates | Discovery | `chk` | `gwready`, `onboard`, identity/model/version fields | Root candidate and setup/readiness decision | `chunk-ZTUP5JXS`, `chunk-PP7IIVNU` | Static + observed identity |
| Capabilities | API service / root | `get_devmap_cap_status_app.cgi` | Discovery or session per firmware | None | `devapp_cap_info`, feature blocks | Identify serial/MAC/API and choose supported branch | `chunk-O5UGQCOY`, `NokiaService.identify` | Observed |
| Legacy app owner login | Nokia API service / root | POST `login_app.cgi` | Local owner credentials | `name`, `pswd`, `srip` | `cookie.sid/lsid` | Owner session | `chunk-ZTUP5JXS.loginLocal` | Static; not selected for WebGUI writes |
| Current local login | TT Router / root | POST `login_web_app.cgi?nonce`, then `login_web_app.cgi` | Owner credentials; fresh nonce/RSA/AES exchange; pinned key on reconnect | `userName`, vendor owner form, fresh response AES material | HTTP 299, result 0, sid, CSRF; authenticated serial match | Trusted local session | `NokiaService._loginWeb`; device crypto sources | Observed |
| Root network setup | Nokia API service / root radios | `whw_onboarding_app.cgi` | Owner session | `act=ConfigWhwPswd`, `wl_ssid`, `wpaKey`, `pswdNew` | Setup/status read-back | Broadcast network configured | `chunk-ZTUP5JXS.setWifiNamePassword/setOnboardFlag` | Static; existing migration separately observed |
| Root readiness | Nokia API service / root | `whw_onboarding_status_app.cgi?status`, `whw_gatewayrdy_status_app.cgi` | Local session where required | Status query | Readiness/onboarding fields | Continue setup/reconnect only when reported | `chunk-ZTUP5JXS` | Static |
| AP bridge/WAN | Nokia service / root forwarding | `whw_beacon_mode_app_web_app.cgi`; status counterpart `?getWorkMode`; legacy WAN `wan_list_app.cgi`, `wan_config_app.cgi` | Owner session, CSRF/encryption for WebGUI | `act=setWorkMode`, `brEnable=1`; WAN payload not used here | Mode read-back after restart | AP bridge; does not establish wireless uplink | `NokiaService.enableBridge`; WebGUI network module | Bridge observed; WAN static |
| Add Wi-Fi point | Scan/manual page → API / **root enrollment service** | POST `whw_zerotouchonb_app.cgi` | Root owner session or authenticated cloud relay chosen by API mode | `act=AddBeacon`, `BeaconSrn` | App accepts result 0 or reason 409; 415/507 error branches | Serial registered/request accepted, not online proof | `chunk-XRW5DKG6`, `chunk-V6S6RRMA`, `chunk-ZTUP5JXS` | Static |
| Current TT Router add | TT Router / root enrollment service | POST `mesh_web_app.cgi?add` | Identity-matched local owner session, encrypted CSRF form | `SerialNumber`, `csrf_token` | result 0; then read-back | Request acknowledged | Firmware `saveMeshData`, `NokiaService.changeExtender` | Static vendor write; physical second-node success pending |
| Radio negotiation/config sync | Root + extender **firmware** | Not exposed by app's add request | Exact trust/bootstrap/key mechanism unknown | Serial triggers root workflow; no backhaul PSK in app add payload | Expected device association/configuration | Extender joins root and receives configuration | Boundary after AddBeacon; no reference capture yet | Inference; protocol unknown |
| Local live topology | Nokia app / root reporting service | `websoc_session_app.cgi`, then WS port 8099 | Session start; first frame encodes owner credentials | `Session_START{Mobile}`, timeout 1800 | 200 OK/401; `MeshNetwork`, `MeshLinks`, `ExtenderAdded`, timeout events | Reported state updates | `chunk-SKC2FBIM` | Static, not enabled in TT Router |
| Current read-back | TT Router / root | `mesh_status_web_app.cgi` | Encrypted owner session response | GET | `root_info`, `beacon_detail`, `beaconEntries`; node serial, MAC, IP, name, onboarding/backhaul fields | Listed/unlisted/reported status, with freshness | Firmware `loadMeshData`; prior root response | Observed empty inventory; populated enum meanings pending |
| Cloud topology | Nokia API service / **cloud** | `home-hub/networks/{MAC}/mesh?live=...`; USP `rest-usp/agents/{endpoint}/message` | Owner account Bearer token / enrolled device | Root MAC; `GetMeshNetworkTopology()` operation | Mesh model, nodes/links | Remote observation | `chunk-ZTUP5JXS`, URL table | Static; no cloud dependency added |
| Client verification | TT Router / **phone interface** | Android Wi-Fi Network-bound context and HTTPS | Phone OS network access | Expected gateway, actual BSSID/network identity | DHCP/gateway/IP and HTTPS result on same Wi-Fi Network | Only that client path verified | `NokiaProvider.verifyClient`, `NokiaLocal.kt` | Root observed; extender pending |

Discovery does not use a verified Beacon BLE service or SSDP/UPnP discovery. `.local` is an OS-resolved hostname, not app service browsing. QR reads label data; it is not evidence of DPP. Root factory state is determined from discovery/readiness/capabilities, not an SSID prefix alone. TT Router's bounded candidate discovery includes saved LAN addresses and IPv6 candidates; a candidate must return matching device identity.

## What remains inside firmware

The official app stays on the root's reachable management network during Add Beacon; the traced serial flow does not join the extender setup SSID or transfer a backhaul key from Android. The root registers the requested serial, while the device-side services perform the enrollment. Whether this uses a temporary provisioning BSS, standard WPS/EasyMesh, DPP, a proprietary authorization exchange or a combination remains **unknown**. A serial is an enrollment selector, not evidence that it is itself a secret or sufficient over-air authorization.

The observed root has public BSSIDs ending `e6:c9` (2.4 GHz) and `e6:cd` (5 GHz), with hidden Nokia BSSIDs ending `cb:e6:c9` / `cb:e6:cd` recorded in prior scans. Hidden BSSIDs are **candidates**, not proven active backhaul. The physical netdev names, selected backhaul band, peer initiator, key establishment, retry interval and root-restart/reparenting behavior have not been observed with an extender. No whole-house coverage or recovery result is claimed.

The APK's `MeshNetwork` model contains root/beacon roles, `aps`, links, `isbackhaul-connected`, `backhaulQuality`, `isEthernetConnection`, and endpoint `bssid`, `remote-bssid`, `medium`, `metric`, `state`. These are richer than CGI 5.5 WebGUI inventory, whose own mesh page only displays serial, onboarding, backhaul, name, MAC and IP. Do not invent RSSI units or infer parent links from list membership. WS timeout events show the app can display failures; they do not disclose firmware retry/recovery algorithms.

## TaoTronics and Raspberry Pi implications

TaoTronics enrollment (`SetMeshInitByBt`, its node inventory and broadcast configuration) has no demonstrated counterpart for Nokia serial registration, device authorization or configuration synchronization. The missing integration begins at **enrollment/control**, before association, key establishment and transparent data forwarding can be credited. Matching SSIDs would only address ordinary client discovery. The two systems' actual radio interoperability remains unproven, independently of the WebGUI capability flags.

For a **fully wireless Pi intermediary**, the Pi would need a Nokia-accepted upstream controller/backhaul-AP role, compatible bootstrap authorization and keys, configuration synchronization, backhaul STA association and transparent forwarding. The requested topology also requires the current Nokia root to accept an upstream wireless role while serving its extender; the app does not expose that role transition. An ordinary Linux hotspot does not supply these functions.

As a standards-based research branch, hostapd/wpa_supplicant support Multi-AP-specific association information elements, backhaul four-address operation and WPS exchange of backhaul credentials; a separate daemon supplies the rest of Multi-AP control. This is a **conditional Linux mechanism**, not evidence that this Nokia firmware accepts it. No WPS or Multi-AP experiments were sent to household devices. [Upstream hostapd README, distributed in Debian](https://sources.debian.org/src/wpa/2:2.10-12%2Bdeb12u3/hostapd/README-MULTI-AP/). prplMesh supplies controller/agent implementations, but their existence is not certification of this Nokia–Pi pair. [prpl Foundation](https://prplfoundation.org/prplmesh/).

For hardware qualification on a **spare** Pi, record OS/kernel, radio chipset/driver/firmware, supported AP/STA modes, interface combinations, 4-address support and monitor support. Prefer separate upstream and backhaul radios to avoid same-channel concurrency constraints; a capture radio may be needed too. A generic Raspberry Pi model designation is insufficient to qualify its radio. Argon's existing radios are production resources and were not repurposed, detached or reconfigured.

A **Pi Wi-Fi receiver → short Ethernet → Nokia WAN** avoids the Nokia radio-enrollment problem but still has an upstream L2 problem: Linux transparent bridging requires compatible four-address behavior at the AP and station. TaoTronics has no verified matching interface. A one-Pi NAT hotspot adds a subnet/NAT layer; proxy ARP/relayd-style translation is not a proven transparent replacement for multiple MACs, IPv6 and multicast. These do not meet the stated transparent same-LAN target. [Linux wireless driver/4-address requirements](https://wireless.docs.kernel.org/en/latest/en/users/documentation/iw.html#using-4-address-for-ap-and-client-mode).

A credible separate research topology is **two controlled endpoints**: TaoTronics LAN → spare bridge endpoint ⇄ spare Pi receiver → short Ethernet → Nokia WAN. They can use a documented compatible four-address link, or an authenticated L2 tunnel over an IP underlay, with DHCP/NAT disabled on the bridge. That requires an endpoint on each side, MTU/multicast/recovery testing and loop prevention. It is not the requested single-Pi fully wireless Nokia controller. A purpose-built matched pair is simpler to qualify; see [bridge acceptance plan](NOKIA_WIRELESS_UPLINK_OPTIONS.md).

## Implementation and isolated test status

TT Router retains the verified encrypted WebGUI write and adds a user-visible **three-minute read-only enrollment observer**, five seconds between completed reads. It binds observation to the selected root and serial, presents raw firmware status changes, separates mesh freshness from WAN freshness, and discards late replies after stop/disposal. App lifecycle changes stop observation and invalidate client evidence. A lost write reply is explicitly unconfirmed; no automatic enrollment retransmission occurs. Stopping the observer sends no device-side cancel or reset.

The topology inventory displays root and reported extender identities/IPs. Parent/radio/RSSI and extender internet remain explicitly unverified when the supported schema does not supply them. Root client verification cannot be credited to the extender. No cloud secrets, proprietary account impersonation or speculative WS/auth downgrade were introduced.

Isolated software tests exercise root report progression, unavailable schema, root-identity change, delayed replies after cancellation/disposal, concurrent-start suppression, bounded timeout, lost write acknowledgment and mobile UI lifecycle/layout. They use synthetic responses and prove application behavior only. **No radio/interoperability proof of concept was run:** the Nokia bootstrap/association contract remains unknown, and no spare controlled bridge hardware was supplied. The earliest unpassed hardware stage is discovery/association of the intended peer; authorization, data forwarding, DHCP, internet and reconnection are consequently untested, not “failed in simulation.”

## Deferred controlled reference test

1. Owner supplies the second unit's exact model/serial and approves activation. Keep the working root cable and household SSID unchanged; do not reset the root. Power the factory-reset extender near it with Ethernet disconnected.
2. Use a dedicated passive capture interface if available, without changing Argon's interfaces. Record timestamps, channel/BSSID, advertised capabilities, association direction/status, Multi-AP/vendor information elements, EAPOL/WPS/DPP indicators and four-address data headers where observable. Look for IEEE 1905.1 only on a capture path that can actually see its Ethernet traffic; encrypted RF frames or a switched LAN port may hide it. Absence on an unsuitable capture point proves nothing. Keep packet files private; export metadata only, never credentials or key payloads.
3. Capture the authenticated root's before/after inventory. Enroll the exact serial once through TT Router, observe reports, and correlate the physical extender identity. Acknowledgment/list membership is not wireless success.
4. Require root/extender roles, real parent/link medium, peer BSSID and signal evidence from a supported diagnostic source. If WebGUI omits them, record the limitation and inspect an authorized reference source/capture; do not guess fields or enable the legacy WS protocol with unverified credentials.
5. Connect the Fold4 specifically to an extender BSSID corroborated by device/capture evidence. Verify TaoTronics DHCP/gateway, DNS, same-LAN management and Wi-Fi-bound HTTPS with cellular excluded. Record which node served the client.
6. With separate approval for brief extender interruption, test extender power/RF-loss recovery and relocation. Root reboot would interrupt working Nokia clients and requires its own approval; do not perform it as an implicit enrollment step. Record actual recovery times and roaming/application continuity. Stop on loss of household connectivity and retain the verified root cable.
7. Only after this reference reveals a credible supported bootstrap/association contract should a spare Linux lab attempt Nokia interoperability. Its success gates are discovery → association → authorized enrollment → backhaul → DHCP/gateway → internet → reconnect, with no extra DHCP/NAT or parallel bridge loop.

Next owner action is deferred: second-Beacon model/serial and activation approval. No further hardware permission is requested in this software-only phase.

## Software validation

- Full Flutter suite: **227 tests passed**, including six new enrollment observer/UI tests.
- Flutter analyzer: **no issues found**.
- CodeRabbit reviewed the tracked application diff and raised one minor issue: observation cleared foreground feedback. Fixed by separating read observation from foreground operations and queuing foreground work behind an in-flight read; a regression test and the full suite passed afterward. No second remote review was run.
- Targeted Nokia subset: **25 tests passed**, including narrow, Fold4-sized and landscape layouts.
- Documentation relative links and source-anchor JSON validated.
- Fold4 installed package was read back as **1.9.2+19**; the candidate is not installed as part of this phase.
- No production Pi configuration or router write was performed. These software results do not replace the deferred two-Beacon wireless reference test.

Candidate APK: `artifacts/releases/tt-router-1.9.3-20.apk`, manifest verified as 1.9.3+20. SHA-256: `63033829580fd96fc882025d1100beeee0947d0c28433e480f193e7210478469`. Build passed after the review fix; not installed. [Validation record](evidence/nokia-enrollment-validation-2026-10-18.json).
