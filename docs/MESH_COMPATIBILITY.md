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

## Duplicate `Nokia Wifi` networks (audit 2026-10-18 12:25, read-only)

| | Index 0 | Index 1 |
|---|---|---|
| SSID | `Nokia Wifi` | `Nokia Wifi` (renamed from `Game labs` about 11:40) |
| Enabled | yes | yes |
| BSSIDs | `…:A7` (2.4 ch 2), `…:A3` (5 ch 44), `…:AD` (5 ch 149) | `…:AA` (2.4 ch 2), `…:A5` (5 ch 44), `…:AE` (5 ch 149) |
| Security (RSN element) | WPA/WPA2-PSK, CCMP only | byte-identical |
| Password | accepts the Nokia password | accepts the Nokia password |
| Observed clients | Fold4 (`…:AD`) | OnePlus (`…:AE`) |

The two networks share an SSID, security and passphrase, so they are **accidental duplicates**: two virtual networks per radio advertising the same network. The password evidence is that both phones joined with their single saved `Nokia Wifi` profile. Per-network client counts aren't available: the router's client records carry no SSID, and the BSS Load station count (10) is device-wide. Effects: double beacon overhead on every radio (six BSSIDs), and clients may switch between the two networks on one radio. No security impact.

**Smallest safe correction (needs approval):** switch **index 1 off** with TT Router's existing per-network switch (`Create=0`), leaving its settings intact so it can be re-enabled. Don't rename or delete it.
- **Expected effect:** clients on index 1 BSSIDs (at least the OnePlus) drop for a few seconds and rejoin the same SSID on index 0 with their saved password. Radios restart, so all clients may reconnect briefly.
- **Before:** note the device counts on `/devices`.
- **After:** check that the router's read-back shows index 1 off, and that the device count recovers within about 2 minutes.
- **Rollback:** switch index 1 back on.

`Game Labs-2.4G` (`…:A9`) is unchanged: the same radio, the same security, broadcast independently of index 1. Its purpose is still only inferred (a vendor-app 2.4 GHz compatibility/IoT network); confirming it needs the vendor app. Leave it on until no device depends on it.

## Recommended coverage solution

1. **Best unified option:** a second **TaoTronics TT-ND001** satellite, if one can still be obtained, enrolled through the vendor's own flow.
   - It's a real mesh: one SSID set, one management app, one client list. Backhaul runs over the dedicated 5 GHz-high radio (hidden `…:AC`) or Ethernet.
   - It costs nothing in configuration, but the satellite would share the router's one-phone management limit.
2. **Available now:** the Nokia Beacon as a **bridged access point** (below).
   - It adds coverage, but as a separately managed AP with client-driven roaming. It's not a mesh.

### Executable bridged-AP setup (Nokia Beacon; radios stay off until approved)

Topology:
`MikroTik → Argon eth0 … Argon eth1 → TaoTronics WAN │ TaoTronics LAN port ──Ethernet──► Nokia Beacon (AP bridge)`

1. **Survey (no change):** in the Nokia WiFi app (local login), record the model and firmware (`get_devmap_cap_status_app.cgi` data, shown in the app's device info). Also list anything still cabled to the Beacon.
2. **Cable:** a TaoTronics LAN port to the Beacon's port (WAN or LAN). Never connect it to Argon `eth1` or the MikroTik. One cable only, so no loop.
3. **Mode:** in the Nokia app, set Work mode to **AP bridge** (the app's `whw_beacon_mode_app.cgi act=setWorkMode&brEnable=1`, followed by a reboot). This turns off the Beacon's DHCP server and NAT. Use the official app only; don't send these calls manually.
4. **Verify bridging (radios still off):**
   - The Beacon takes a 192.168.10.x lease from 192.168.10.1.
   - A client on the Beacon's LAN port gets its address from 192.168.10.1. No 192.168.18.x appears, and there's no second DHCP offer or double NAT.
   - `/devices` lists the Beacon as a wired TaoTronics client.
5. **(Approval) Wi-Fi settings:**
   - SSID `Nokia Wifi`, the same password, WPA2-PSK AES (no WPA3-only).
   - 2.4 GHz on ch 6 or 11 at 20 MHz. 5 GHz on ch 52–64 or 100–112 at 80 MHz. TaoTronics uses 44 (36–48) and 149 (149–161).
   - Lower the transmit power if the Beacon is close to the router.
6. **Roaming:** there's no 802.11k/v/r coordination between vendors, so clients decide when to switch. Place the Beacon where the TaoTronics signal drops below about −70 dBm, not next to it. Expect a short reconnect when a client changes AP.
7. **Validate:** clients on both APs get 192.168.10.x, the internet works through the VPN, Argon stays on eth0, and device counts are stable.
8. **Rollback:** switch the Beacon's radios off, or unplug its Ethernet. Bridge mode can be reversed in the Nokia app (`brEnable=0`).

The shared SSID gives the same network name and password everywhere. It **does not** create a cross-vendor mesh.
