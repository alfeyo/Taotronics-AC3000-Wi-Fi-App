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
- **Radio settings:** 2.4 GHz on ch 2, 20 MHz (HT operation element). 5 GHz low band on ch 44 at **80 MHz** (the Mac reports 802.11ac, ch 44, 80 MHz); the earlier 40 MHz estimate from advertised rates was wrong. A third radio (5 GHz high band, ch 149) also serves clients; see §10. The router's local API exposes no channel or width controls, so these were verified but not changeable.
- **Isolation:** client-to-client traffic works across the LAN (Mac → Fold4, Tab A9 and wired client reachable), so there is no station isolation in effect.

### 2.1 `Game labs` (index 1): kept enabled
It is a second client-facing dual-band network on the same router, not guest, backhaul or management. It was **not disabled** because its redundancy cannot be verified: the router's client list (`GetDevListInfo`) does not report which SSID a client uses, and at least one active client (the Galaxy Z Fold4 that runs TT Router) is still associated to it (`80:c5:48:50:35:ae`). Disabling it now could strand devices that only know `Game labs`. Its settings are intact for rollback. Disable it with the per-network switch in TT Router once remaining devices have moved; this needs no new code.

### 2.2 `Game Labs-2.4G`
Source: **a fourth virtual network on this TaoTronics' 2.4 GHz radio** (confirmed 2026-10-18 from beacon elements, not the name):
- BSSID `80:C5:48:50:35:A9`, 2417 MHz (ch 2, 20 MHz), WPA/WPA2-PSK CCMP, broadcast, country US.
- Its BSS Load element reports the same radio state as `Nokia Wifi` (`…:A7`) and `Game labs` (`…:AA`): 11 stations, 0 % utilisation. The vendor elements are identical (MediaTek `00:0c:43`/`00:0c:e7`).
- Signal matches its siblings (−19/−20 dBm at Argon, −41 dBm at the phone). A single −65 dBm reading was a scan artefact; `…:AA` showed the same dip.
- No Wi-Fi EasyMesh/Multi-AP element, no 5 GHz counterpart, not hidden: it is **client-facing, not backhaul**.
- Absent from the local `GetWirelessInfoList` (indices 0–2) and guest (`Game Labs-VIP`). Most likely a 2.4 GHz-only compatibility/IoT network created by the original vendor app.

It was left unchanged. Safe retirement procedure (needs the vendor app or router web UI, because the local protocol cannot address it):
1. Keep it running until 2.4-only devices (IoT, older devices) have joined `Nokia Wifi`. Its users can't be listed, because client records carry no SSID.
2. Watch the router client count and the dashboard for devices dropping when it is disabled; re-enable from the same tool if any do.
3. Disable it rather than delete it, so the settings stay recoverable.

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

## 10. Mesh topology and whole-home coverage (2026-10-18)

**Topology (router telemetry + scans):**
- **One physical TaoTronics unit** (ND001, SN `5702100B047E2E9D`, role `mpp`). `GetExistNode` reports 1 node of 1, so there are no child nodes and no backhaul links to assess. The node holds 19–21 clients, and its firmware version isn't reported.
- It is tri-band. Each router "index" is a network broadcast on every client radio:

| Radio | Channel / width | BSSIDs (Nokia Wifi · Game labs · other) |
|---|---|---|
| 2.4 GHz | ch 2, 20 MHz | `…:A7` · `…:AA` · `…:A9` Game Labs-2.4G |
| 5 GHz low | ch 44, 80 MHz | `…:A3` · `…:A5` |
| 5 GHz high | ch 149 | `…:AD` · `…:AE` (+ hidden `…:AC` seen 2026-10-17, probably the reserved mesh-backhaul BSS; inferred) |

- Argon's onboard radio does not see ch 149. The phone does (Fold4 associated to `…:AE`, 5745 MHz, earlier link 702/866 Mbit/s).

**Coverage sample (two fixed locations; no walk test was possible):**

| Location | Serving BSSID | Band | RSSI | Notes |
|---|---|---|---|---|
| Argon (beside router) | `…:A3`/`…:A7` | 5 / 2.4 | −8 / −20 dBm | reference |
| Fold4 position | `…:AE` (ch 149) | 5 GHz | −45 dBm | 2.4 GHz −41 dBm; 5 GHz low −47 dBm |
| Mac position | ch 44 | 5 GHz, 80 MHz | −46 dBm, SNR 43 dB | 802.11ac, tx 144 Mbit/s at sample time |

No roaming can occur: there is only one node. Throughput was not load-tested, to avoid disturbing the household.

**2.4 GHz channel:** ch 2 overlaps neighbour "Ethel" on ch 1 (−51 dBm at Argon), and ch 11 carries two neighbours (−57/−64 dBm). **Ch 6 was clear** and would be the best of 1/6/11 at 20 MHz. The local protocol has no channel or width control, so nothing was changed. Use the vendor app if it offers a channel setting.

**Recommendations for a large house:**
1. Genuine whole-home mesh needs a second TaoTronics TT-ND001 satellite, joined through the vendor's own enrolment. Place it about halfway to the weak area, within roughly two rooms of the main unit (target −65 dBm or better from the main unit on 5 GHz). Use Ethernet backhaul if a cable run exists.
2. Keep the main unit high and central, away from the Pi's metal case and other radios.
3. As a separate access point (not mesh), see the Nokia procedure in §11.

## 11. Nokia Beacon reuse (prepared, not executed)

**Evidence:** web UI `NokiaWifi.com` and gateway MAC `b4:63:6f:db:e6:c0` (2026-10-18 audit), plus the phone's saved setup network `Nokia Beacon 1.1`. The model is therefore *probably* Beacon 1.1. Firmware is **unknown**: the Beacon is unreachable now (radios off, not on Argon's path).

**Path check:** Argon's route is MikroTik 192.168.88.1 → (silent hop) → ISP CGNAT 172.16.250.14, and 192.168.18.1 is unreachable through it. So the Nokia is very likely **not** in Argon's internet path.

| Option | Verdict |
|---|---|
| 1. Join a TaoTronics EasyMesh network | **Not supported.** Nokia documents EasyMesh for the Beacon 1.1, but TaoTronics TT-ND001 has no documented EasyMesh and its protocol has no foreign-node onboarding. |
| 2. Bridged access point on the TaoTronics LAN | **Feasible** if the Beacon's bridge/AP mode is available in its app (documented for Beacon 1.1; verify on the device). |
| 3. Ethernet backhaul | Yes, as a wired AP: Beacon Ethernet → a TaoTronics LAN port. |
| 4. Same SSID and security, no DHCP/NAT conflict | Yes, only in bridge mode (DHCP and NAT off; it then gets 192.168.10.x from the TaoTronics). No coordinated roaming: clients roam on signal alone. |

**Procedure (needs approval at step 4, which turns Nokia radios on):**
1. In the Nokia WiFi app, identify the model and firmware and confirm bridge mode exists. Note what else is connected to the Nokia today, because converting it removes its router role.
2. Run Ethernet from the Beacon's WAN/LAN port to a TaoTronics LAN port (or a switch on the TaoTronics LAN). Never connect it to Argon `eth1` or the MikroTik.
3. Switch the Beacon to bridge mode with radios still off. Confirm it takes a 192.168.10.x lease and that the TaoTronics stays the only DHCP server.
4. **(Approval)** Set SSID `Nokia Wifi` with the same password, WPA2-PSK AES. Use 2.4 GHz ch 6 or 11 at 20 MHz, and a 5 GHz channel outside 36–48 and 149–161 (for example 100–112 DFS, or 52–64). Then enable its radios.
5. Verify: clients get 192.168.10.x from 192.168.10.1, no second DHCP server is offered, the device count on `/devices` holds, and Argon stays on eth0.
6. Rollback: disable the Beacon radios, or unplug its Ethernet.

## 12. Network Hub and VPN control (2026-10-18)
See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) §6 and argon-dashboard `docs/DEPLOYMENT-2026-10-18-network-hub.md`.

## 13. Limitations and rollback
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
