# Network migration overview: Nokia Wi-Fi hosted by TaoTronics

Completed and verified: 2026-10-18, 10:22–10:35 CAT. Every item was observed
this run unless marked *recorded* (from earlier logs) or *unknown*. History and
the staged plan are kept in [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).

## 1. Final topology

```
Wired upstream: MikroTik 192.168.88.1 (MAC d4:ca:6d:05:f5:89)
        │  Ethernet
Argon eth0 192.168.88.250/24 (DHCP, NM "Main LAN Ethernet", ACTIVE_WAN)
        │  Argon routing, Surfshark VPN (tun0, UK London), kill switch
Argon eth1 192.168.50.1/24 (NM "eth1-share": DHCP + NAT for the router WAN only)
        │  Ethernet, 1 Gbit/s
TaoTronics ND001 WAN 192.168.50.181  (mesh SN 5702100B047E2E9D, role mpp)
        │  LAN 192.168.10.0/24, DHCP/DNS 192.168.10.1
Wi-Fi "Nokia Wifi" (2.4 + 5 GHz)  ·  "Game labs" (2.4 + 5 GHz, transitional)
```

- The Nokia WiFi Beacon's radios are off. Argon scans see no Nokia BSSIDs (`b4:63:6f:…`/`b6:63:6f:…`). The Nokia stays powered. Its role upstream of the MikroTik is *unknown*: Argon no longer reaches 192.168.18.0/24.
- There is one DHCP server per segment. The TaoTronics LAN is served by 192.168.10.1 (Mac lease); Argon `eth1` sees only the TaoTronics (`80:c5:48:50:35:a1`).

## 2. Active SSIDs and bands (fresh radio scan from Argon + router read-back)

| Router entry | SSID | State | Broadcast (BSSID, channel) |
|---|---|---|---|
| index 0 | **Nokia Wifi** | on | `80:C5:48:50:35:A7` 2.4 GHz ch 2 · `…:A3` 5 GHz ch 44 |
| index 1 | Game labs | on (kept, see §2.1) | `…:AA` 2.4 GHz ch 2 · `…:A5` 5 GHz ch 44 |
| index 2 | TT-35A0 | off | — |
| guest | Game Labs-VIP | off (unchanged) | — |
| not in router API | Game Labs-2.4G | broadcasting | `…:A9` 2.4 GHz ch 2 |

- **Correction:** a router "index" is a dual-band network, not a band. The handoff's "index 0 = 2.4 GHz, 1 = 5 GHz" inference was disproved by the scan; the app's band labels for index 0/1 are therefore misleading.
- **Security:** every network advertises WPA/WPA2-PSK with **CCMP (AES) only**, no TKIP. This is compatible with older WPA2 clients and with devices that saved the Nokia as WPA2. The app reports index 0 as WPA2-PSK. No change was made.
- **Radio settings:** 2.4 GHz on ch 2 with 20 MHz-class rates (130 Mbit/s); 5 GHz on ch 44 with 40 MHz-class rates (270 Mbit/s), non-DFS. The router's local API exposes no channel or width controls, so these were verified but not changeable.
- **Isolation:** client-to-client traffic works across the LAN (Mac → Fold4, Tab A9 and wired client reachable), so there is no station isolation in effect.

### 2.1 `Game labs` (index 1): kept enabled
It is a second client-facing dual-band network on the same router, not guest, backhaul or management. It was **not disabled** because its redundancy cannot be verified: the router's client list (`GetDevListInfo`) does not report which SSID a client uses, and at least one active client (the Galaxy Z Fold4 that runs TT Router) is still associated to it (`80:c5:48:50:35:ae`). Disabling it now could strand devices that only know `Game labs`. Its settings are intact for rollback. Disable it with the per-network switch in TT Router once remaining devices have moved; this needs no new code.

### 2.2 `Game Labs-2.4G`
Source: **this TaoTronics router** (BSSID `80:C5:48:50:35:A9` is in the router's own `80:c5:48:50:35:aX` block, same channel). It is not one of the networks the local API reports (indices 0–2, guest `Game Labs-VIP`). It is most likely a legacy network configured through the vendor app. It cannot be controlled through the verified local protocol, so it was left unchanged.

## 3. TaoTronics role and mesh status
- Primary standalone mesh: one ND001 node online of one (`mpp`). LED on, internet online, MQTT management via pinned CA working.
- The node restarted around 10:03 (uptime 1186 s at 10:22), matching the cable test and Wi-Fi changes.

## 4. Argon routing roles
- `eth0`: wired WAN, DHCP from 192.168.88.1, default route metric 100, VPN peer route via eth0. ACTIVE_WAN = eth0 since 10:05:51.
- `eth1`: downstream to the TaoTronics only (192.168.50.0/24), policy tables 152/153; VPN mode on, table 153 → `tun0`.
- Kill switch `argon_eth1_vpn`: 0 rejected packets. Household egress: GB, Hydra Communications (Surfshark).
- Tailscale `100.94.137.17` reachable; SSH via Tailscale works; `throttled=0x0`.

## 5. Nokia auto-connect restrictions
Argon's WAN controller (`50-argon-eth1-lan-route`, `lib/wan.js`) only considers NetworkManager Wi-Fi profiles whose name starts with `Argon WAN WiFi`. Changes, made while no Wi-Fi profile was active:

| Before | After |
|---|---|
| `Argon WAN WiFi - Nokia (radio 1)`: SSID Nokia Wifi, **unbound, no BSSID lock**, priority 100. This is the profile actually used at 10:01. | `Retired Nokia WiFi (former WAN radio 1)`: excluded from failover; credentials and settings kept |
| `Argon WAN WiFi - Nokia (radio 2)`: BSSID-locked to `B4:63:6F:DB:E6:CD` earlier today | `Retired Nokia WiFi (former WAN radio 2)`: excluded; credentials kept |
| `Nokia Wifi`: autoconnect no, not prefixed | unchanged (never selected) |

Since the TaoTronics now broadcasts `Nokia Wifi`, the unbound radio 1 profile was a live loop risk on any eth0 failure. The controller's post-association loop check was the only remaining guard; the profile is now out of the candidate set.

## 6. OnePlus backup
- `One Plus 8T` → **`Argon WAN WiFi - OnePlus 8T`**: SSID `One Plus 8T`, WPA-PSK with password stored (not displayed), autoconnect no (controller-managed), priority 100, unbound (any radio).
- `/api/wan` and the controller list it as the **only** fallback profile. `argon-network-state`: `ETH_READY=1`, `WIFI_RADIOS=wlan0:onboard`.
- Failover was **not** live-tested, because that would disconnect the household. It is used only when eth0 is unusable **and** the OnePlus hotspot is on; each association is then loop-checked.
- Only one Wi-Fi radio remains: the USB adapter (former `wlan1`) is absent from the USB bus.

## 7. Device inventory and monitoring
- Router reports 17 online of 20 known (12 Wi-Fi, 1 wired), phone-supplied snapshot 16 s old. TT Router Home shows "17 devices". These agree.
- `/devices` keeps the phone-supplied label and 60 s expiry; household traffic is measured by Argon on eth1.

## 8. Verified improvements (this migration)
- Nokia Wi-Fi clients now served by the TaoTronics on both bands, with the Nokia SSID and password (entered by the user; never stored in this repo).
- Wired WAN for Argon; Wi-Fi uplink loop risk removed; OnePlus enrolled as the sole Wi-Fi fallback.
- Router indexes documented correctly as dual-band networks.

## 9. Nokia mesh compatibility
- Nokia model: **Nokia WiFi Beacon 1.1** (inferred from the phone's saved `Nokia Beacon 1.1` setup network plus the earlier `NokiaWifi.com` web UI). Firmware is *unknown*: the Beacon is no longer reachable from Argon.
- Nokia documents the Beacon 1.1 as EasyMesh-compliant ([Nokia product page](https://www.nokia.com/networks/fixed-networks/home-wi-fi/wifi-beacon-1-1)).
- TaoTronics TT-ND001 (AC3000): no documented EasyMesh/Multi-AP support was found in reviews or vendor material ([mightygadget review](https://mightygadget.com/taotronics-tri-band-ac3000-mesh-wifi-router-review-tt-nd001/)). Its local protocol has no controller/agent onboarding for third-party nodes; the node reports no firmware version.
- **Result: no mutually supported mesh standard.** Cross-vendor pairing is closed. The TaoTronics runs as the standalone mesh, and no pairing experiment was attempted.

## 10. Limitations and rollback
- `Game labs` and `Game Labs-2.4G` remain broadcast (§2.1, §2.2).
- The MikroTik upstream and the Nokia's place in it are undocumented; the Nokia must stay powered until that is known.
- Argon rebooted unexpectedly at 10:02:56 (cause unknown; journal not persistent).
- The OnePlus fallback is untested live, and only one Wi-Fi radio is left.
- Client inventory is phone-supplied while TT Router is open.

Rollback, in order of reach:
1. Nokia Wi-Fi back: turn the Nokia radios on in the Nokia WiFi app (user action).
2. TaoTronics SSID: in TT Router set index 0 back to `Game labs` with its previous password.
3. Argon profiles (on Argon):
   ```
   sudo nmcli con modify b034200d-f8b9-4179-a632-fda2ee6e9dac connection.id "Argon WAN WiFi - Nokia (radio 1)"
   sudo nmcli con modify 6d27bd7c-1a78-42f6-9697-9f6e7cdd680e connection.id "Argon WAN WiFi - Nokia (radio 2)" 802-11-wireless.bssid ""
   sudo nmcli con modify fc7c6c86-7329-45ab-9052-b48e5abe1e38 connection.id "One Plus 8T" connection.autoconnect-priority 0 connection.interface-name wlan0
   ```
   Restore the Nokia profiles only when the TaoTronics no longer broadcasts `Nokia Wifi`.
4. Wired WAN: unplug eth0; the controller falls back to an approved Wi-Fi profile (OnePlus, if its hotspot is on).
