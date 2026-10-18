# Nokia ↔ TaoTronics mesh compatibility

Determination date: 2026-10-18. Inputs: TaoTronics protocol handoff and live router data, beacon-element radio scans from Argon and the OnePlus, and static analysis of the official Nokia WiFi app 3.260311.00 ([NOKIA_PROTOCOL_INVESTIGATION.md](NOKIA_PROTOCOL_INVESTIGATION.md); signer `CN=Nokia, O=Nokia`, Play source stamp).

## Determination

**There is no genuine shared mesh, and none can be built with supported mechanisms.** TaoTronics stays the primary standalone mesh. If coverage is needed, the Nokia Beacon can be added as an **independently managed bridged access point** on the TaoTronics LAN. That is not a unified cross-vendor mesh.

| Capability | TaoTronics TT-ND001 | Nokia Beacon (probably 1.1) | Shared? |
|---|---|---|---|
| EasyMesh controller | No evidence. Local MQTT protocol has no controller/agent, onboarding or 1905.1 commands; no vendor claim found | Nokia documents EasyMesh for Beacon 1.1. The Nokia app contains **no** EasyMesh/1905.1/Multi-AP strings, so it manages mesh through Nokia's own APIs | **No** (TaoTronics side unsupported) |
| EasyMesh agent | No evidence | Documented by Nokia (role details not verified) | No |
| Proprietary mesh enrollment | TaoTronics app/BLE flow (`TTBT*` setup, `SetMeshInitByBt`), TaoTronics nodes only | `whw_zerotouchonb_app.cgi act=AddBeacon` by **Nokia serial number** | No: each enrolls only its own vendor's nodes |
| Wireless backhaul | Hidden BSS `80:C5:48:50:35:AC` on 5 GHz ch 149 (inferred backhaul; 1 node, so unused) | Nokia mesh links (`MeshLinks` events) | No |
| Ethernet backhaul | TaoTronics satellites (vendor feature) | Supported for Beacons | Only within each vendor |
| Standard Wi-Fi roaming | Clients roam on signal; no 802.11k/v/r coordination observed across vendors | same | Same SSID/PSK only, so client-driven roaming without coordination |
| Access point / bridge mode | — | **Confirmed in the app:** `whw_beacon_mode_app.cgi` `getWorkMode` → `RGW`/`AP_BRIDGE`; `act=setWorkMode&brEnable=1` (then reboot) | Usable as a separate AP |

An app that can talk to both products would not make them one mesh. No identity spoofing, enrollment protection bypass or firmware modification is proposed.

## Fallback: Nokia Beacon as a bridged access point (prepared, not executed)

Prerequisites:
- **Device facts:** the Beacon's model and firmware from the device itself (Nokia app "About", or `get_devmap_cap_status_app.cgi` once it is reachable). The current evidence is the `NokiaWifi.com` web UI, MAC `b4:63:6f:db:e6:c0`, and the phone's saved setup SSID `Nokia Beacon 1.1`.
- **Cabling:** an Ethernet run from a TaoTronics LAN port to the Beacon.
- **What else uses the Nokia:** bridge mode removes its router role (DHCP/NAT for 192.168.18.0/24), so check this first.

Procedure (radio activation needs explicit approval):
1. Cable the Beacon's WAN/LAN port to a TaoTronics LAN port. Never cable it to Argon `eth1` or the MikroTik.
2. In the Nokia app (local login), set Work mode to **AP bridge** (`brEnable=1`) and let it reboot. Confirm it takes a 192.168.10.x lease from 192.168.10.1, and that no second DHCP server appears.
3. **(Approval)** Enable its radios with SSID `Nokia Wifi`, the same password, WPA2-PSK AES. Use 2.4 GHz ch 6 or 11 at 20 MHz. On 5 GHz, avoid TaoTronics ch 44 (36–48) and ch 149 (149–161); use 52–64 or 100–112.
4. Verify: one DHCP server, no double NAT (clients on 192.168.10.x with gateway 192.168.10.1), Argon still on eth0, `/devices` counts stable.
5. Rollback: disable the Beacon radios, or unplug its Ethernet.

Limits of this setup:
- **Separate management:** the TaoTronics app won't see Beacon clients, and the Nokia app won't see TaoTronics clients.
- **No coordinated roaming.**
- **Phone count:** the Pi's phone-supplied counts include Beacon clients only through the TaoTronics' client list, as wired-bridge clients.

## `Game Labs-2.4G`

**Determination: a client-facing 2.4 GHz network on the TaoTronics' own 2.4 GHz radio. It is not mesh backhaul.**
- **Same radio:** BSSID `80:C5:48:50:35:A9` on ch 2, with the same BSS Load (station count/utilisation) and identical MediaTek vendor elements as `…:A7`/`…:AA`.
- **Not backhaul:** it isn't hidden and carries no Multi-AP element.
- **Independent of index 1:** it was still broadcasting after index 1 was renamed to `Nokia Wifi`.
- **Outside the local API:** it isn't in `GetWirelessInfoList` (indices 0–2) or guest (`Game Labs-VIP`). The only infrastructure-looking BSS is the hidden `…:AC` on 5 GHz ch 149.

**Likely purpose (inferred):** a 2.4 GHz-only compatibility or IoT network created through the vendor app. Whether household devices rely on it can't be determined, because TaoTronics client records carry no SSID. It is left untouched. Retiring it requires the vendor app, a watch on device counts while it's disabled, and disabling rather than deleting.
