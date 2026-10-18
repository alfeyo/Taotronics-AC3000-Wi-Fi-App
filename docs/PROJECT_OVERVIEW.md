# TT Router + Argon — project overview

Last verified: 2026-10-18 (Africa/Lusaka). Every statement below is labelled
**proven** (observed this run), **recorded** (from earlier validation logs) or
**unknown**. The requested source file `TT_Router_Argon_Project_Overview.md` was
not found on the development Mac, so this overview was written from the live
systems and both repositories.

## 1. Components

| Component | Where | State |
|---|---|---|
| TT Router (Flutter, Android) | this repo, `feature/argon-pi-integration` | 1.5.0+8 installed on Galaxy Z Fold4 (SM-F936B) |
| Argon dashboard (Next.js) | `~/projects/argon-dashboard`, `feature/taotronics-router-integration` | deployed build `XY_VnAYyNWKT9FvxvvwUq` on Argon |
| Argon | Raspberry Pi 4 Model B Rev 1.2, Debian 13, Tailscale `100.94.137.17` | up 1 d 18 h |
| TaoTronics AC3000 | one ND001 node, role `mpp`, mesh SN `5702100B047E2E9D` | WAN 192.168.50.181, LAN 192.168.10.0/24 |
| Nokia | Nokia WiFi Beacon (web UI identifies as NokiaWifi.com), gateway 192.168.18.1, MAC `b4:63:6f:db:e6:c0` | exact model **unknown** |

## 2. Proven current topology (read-only audit, 2026-10-18 09:52)

```
ISP ── ? (unknown) ── Nokia WiFi Beacon 192.168.18.1
                         │  Wi-Fi "Nokia Wifi" (WPA2, ch 112 5 GHz / ch 11 2.4 GHz)
                         ▼
                Argon wlan1 192.168.18.43 (primary, metric 600, ACTIVE_WAN)
                Argon wlan0 192.168.18.42 (secondary, metric 700)
                Argon eth0  — NO CARRIER (no cable or no link)
                         │
                Argon eth1 192.168.50.1/24, 1 Gbit/s, NM shared DHCP/NAT
                         ▼
          TaoTronics ND001 WAN 192.168.50.181
                         │  Wi-Fi "Game labs" (2.4 + 5 GHz), "TT-35A0" disabled
                         ▼
                 Household clients 192.168.10.0/24
```

- **Uplink is Wi-Fi only.** `eth0` has carrier 0, operstate down. There is no wired WAN today, even though `eth0` is designated preferred.
- **Ethernet profile already exists:** NM `Main LAN Ethernet` (eth0, DHCP, autoconnect yes, route metric 100, may hold default route). A cable delivering DHCP to `eth0` would immediately become the preferred route; plugging it in *is* the wired-WAN test and requires approval.
- **VPN:** mode `on`; downstream 192.168.50.0/24 uses table `downstream_vpn` (153) via Surfshark `tun0` (UK, London). Kill switch `argon_eth1_vpn` rejects downstream traffic leaving by any path other than tun, tailscale0 or the upstream LAN; 0 rejected packets observed. `argon_dns_guard` limits resolver traffic to tun0. Today's household traffic was 100 % through the VPN.
- **Tailscale:** `100.94.137.17`, no exit node, no routes advertised; listens on `eth0`/`wl*` UDP 41641.
- **Pi's own DNS:** `192.168.18.1` (the Nokia).
- **Live traffic:** `wlan1` carries upstream, `eth1`/`tun0` carry household traffic; `wlan0` is nearly idle.
- **Wired evidence:** Nokia MAC `b4:63:6f:db:e6:c4` was last seen on Argon `eth1` at 192.168.50.244 on 2026-10-06 19:42. A Nokia Ethernet port was therefore once cabled to Argon, but as a DHCP client of Argon (the wrong direction for a WAN feed).
- **Other Nokia BSSIDs:** hidden BSSIDs `b6:63:6f:cb:e6:cd` (ch 112) and `b6:63:6f:cb:e6:c9` (ch 11) are visible. These may be a second Beacon or Nokia backhaul; **unknown**.
- **Power:** Argon recorded active throttling about 13 h before the audit, recovered 40 min before. Monitor the power supply before adding load.

## 3. Ethernet WAN feasibility

| Question | Answer |
|---|---|
| Is a wired WAN in place? | **No** (proven: no carrier on eth0). |
| Can Argon take a wired WAN? | Yes in software: `Main LAN Ethernet` + WAN state machine prefer eth0 (recorded), firewall already admits DHCP/Tailscale on eth0 (proven). |
| Which Nokia port? | A Nokia Beacon LAN port (not its WAN/ISP port) → Argon eth0. Port labelling and free-port availability are **unknown** until inspected physically. |
| Must Nokia stay powered? | **Yes** if it is the box feeding eth0. It remains the ISP gateway/router and DHCP/DNS server for 192.168.18.0/24 even with radios off. |
| Can Nokia be powered off entirely? | Only if a different wired ISP source (ONT/modem handing DHCP directly to Argon) is proven first. The ISP equipment upstream of the Beacon is **unknown**, as is whether the ISP needs PPPoE/VLAN credentials held by the Nokia. |
| Can Nokia's radios be turned off while it keeps routing? | **Unknown**. It depends on the Beacon model and the Nokia WiFi app; verify in the app before planning on it. Any Nokia satellite using wireless backhaul would go offline. |

## 4. TaoTronics capabilities (from `ROUTER_PROTOCOL_HANDOFF.md` + live data)

- Wi-Fi edit is `SetWirelessInfoList` (V1; this firmware never answers V2). The full list must be written back with only the changed fields. Radios restart and clients drop for several seconds. The app verifies by read-back for up to 90 s.
- Supported per network: SSID, password, `Encrypt` 0 none / 1 WEP / 2 WPA-PSK / 3 WPA2-PSK / 4 WPA/WPA2 / 5 WPA3 (WPA3 inferred, untested), enable (`Create`), VLAN and isolation fields. Index 0 = 2.4 GHz, 1 = 5 GHz (inferred), 2+ = additional networks.
- Mesh: TaoTronics proprietary, one node online of one. **No interoperability with Nokia Beacon mesh.** Giving TaoTronics the Nokia SSID and password only lets clients that already know that network join it automatically. It does not join the Nokia mesh, make TaoTronics a Beacon, or allow roaming between the two. Running both with the same SSID would produce two unrelated networks on different subnets, with broken sessions when clients roam. No MAC/identity spoofing or firmware changes are planned.

## 5. Staged migration plan (NOT executed)

Target: ISP → Nokia (radios off, still powered) → **cable** → Argon eth0 → Argon eth1 → TaoTronics WAN → TaoTronics Wi-Fi broadcasting `Nokia Wifi`.

### Stage 0 — prerequisites (no network change)
1. Identify the Nokia Beacon model and its LAN port; confirm a free LAN port and a Cat5e/6 cable run to Argon.
2. Confirm in the Nokia WiFi app that radios can be disabled while routing stays up; note any satellite Beacons.
3. **Loop blocker:** Argon's `Argon WAN WiFi - Nokia (radio 1/2)` profiles match SSID `Nokia Wifi` with no BSSID lock. Before TaoTronics ever broadcasts that SSID, these profiles must be BSSID-locked to the Nokia (`b4:63:6f:db:e6:cd` / `…:c9`) or disabled. Otherwise Argon can join its own downstream router. This is an NM change and needs approval.
4. Record baseline: `/api/status`, `ip route`, `tailscale status`, VPN state, kill-switch counters, dashboard and app screenshots.

### Stage 1 — wired WAN test (requires explicit approval)
1. Plug Nokia LAN → Argon eth0 (no config change needed).
2. Expect: eth0 carrier + DHCP 192.168.18.x; after the ~30 s readiness window the state machine sets `ACTIVE_WAN=eth0`, and Wi-Fi uplinks are released per policy. Brief Tailscale/VPN re-establishment; the kill switch keeps downstream blocked during any tunnel gap.
3. Go checks (all must pass): `/run/argon-wan/active` = eth0; default route via eth0; `tun0` up and table 153 default via tun0; household clients have internet through VPN; `tailscale ping` from phone/Mac; dashboard `/devices` + `/network` 200; TT Router MQTT controls and Gateway screen live; kill-switch reject counter unchanged.
4. Rollback: unplug the cable. The state machine fails back to Wi-Fi; Wi-Fi WAN operation is proven by the current state. If routing does not recover within 60 s, restart nothing: use the dashboard WAN view and the runbook (`argon-dashboard/docs/RUNBOOK.md`).

### Stage 1 result (executed 2026-10-18 ~10:01–10:08, user-approved)
- A cable was connected to Argon eth0. **Its upstream is not the Nokia**: eth0 DHCP gave 192.168.88.250/24, gateway 192.168.88.1, MAC `d4:ca:6d:05:f5:89` (MikroTik OUI), DNS 192.168.88.1. The relationship between this MikroTik and the Nokia/ISP is **unknown**.
- Argon **rebooted unexpectedly** at 10:02:56 during the change. The previous boot's journal is not persistent, so the cause is unknown. After the reboot `throttled=0x0`.
- The USB Wi-Fi adapter (former `wlan1`, `00:13:ef:f3:13:97`) is **absent from the USB bus**. Only onboard `wlan0` remains as Wi-Fi fallback, released while Ethernet is active.
- Passed: ACTIVE_WAN=eth0 (stable from 10:05:51), default and VPN peer route via eth0, `tun0` up with table 153 via tun0, household egress country GB, kill-switch rejects 0, Tailscale reachable, `/devices`, `/network`, `/api/status` 200, router MQTT port reachable from LAN.
- Not passed: TT Router app MQTT reads timed out after the reboot (GetSysConnectInfo/GetNodeRateInfo/GetWanRateInfo), and phone telemetry was >7 min stale. Re-check after restarting the app.
- No rollback was performed: internet, VPN, kill switch, Tailscale and dashboard all stayed working on the wired uplink.

### Stage 2 — soak (24 h on wired WAN, Nokia Wi-Fi still on)
Monitor throttling, VPN reconnects, dashboard history continuity and phone telemetry.

### Stage 3 — Nokia Wi-Fi off (user performs; requires explicit final approval)
Preconditions: Stage 1–2 passed; Stage 0.3 loop guard in place. The user disables Nokia radios. Verify Argon stays on eth0, VPN/Tailscale up, clients unaffected. Argon then has **no Wi-Fi fallback** unless another approved WAN profile is added.

### Stage 4 — TaoTronics adopts the Nokia SSID (requires explicit approval)
1. In TT Router, set index 0 and 1 SSID = `Nokia Wifi`, same password, `Encrypt` 3 (WPA2-PSK, matching Nokia), keeping all other entries raw.
2. Expect all TaoTronics clients on `Game labs` to drop. Former Nokia clients join automatically. Every client gets 192.168.10.x behind double NAT (TaoTronics + Argon), so static IPs, port forwards or anything addressing 192.168.18.x must be checked.
3. Verify read-back, client counts on `/devices`, app pairing (mesh ID based, unaffected by SSID).
4. Rollback: rewrite SSID `Game labs` + previous password from the app, or re-enable Nokia radios.

### Migration result (2026-10-18, completed)
Stages 3 and 4 were carried out with the user. Final state and evidence are in
[NETWORK_MIGRATION_OVERVIEW.md](NETWORK_MIGRATION_OVERVIEW.md):
- The Nokia Beacon (inferred model 1.1) has its radios off and stays powered. Argon's wired WAN is a MikroTik (192.168.88.1), not a Nokia LAN port.
- TaoTronics index 0 = `Nokia Wifi` on both bands (WPA/WPA2 AES-only). Index 1 `Game labs` is kept until its clients are known to have moved.
- **Correction to §4:** router indexes are dual-band networks, not bands.
- Argon's Nokia Wi-Fi WAN profiles were renamed out of the `Argon WAN WiFi` prefix (retired, credentials kept). `Argon WAN WiFi - OnePlus 8T` is the sole Wi-Fi fallback.
- 17 of 20 known clients online; app, Pi and router counts agree.
- Nokia ↔ TaoTronics mesh pairing: no mutually supported standard; closed.

## 6. Application status

- **Flutter 1.5.0+8** (proven on device 2026-10-18): Pi board artwork with hardware model, Gateway connection (local network transport observed; Tailscale supported), Internet source `Nokia Wifi · wlan1`, VPN London, CPU/temperature/memory/throttling, household traffic labelled "Measured by Argon … (eth1)", device synchronization (6 clients shared), merged router + Argon notifications with source labels. Router MQTT with pinned CA, LED state and Wi-Fi read work. `flutter analyze` clean, 103/103 tests. Bluetooth monitoring fallback is implemented and unit-tested but was **not exercised live** this run.
- **Dashboard** (proven): `/devices` shows 6 real TaoTronics clients from the phone, labelled "Phone-supplied · 60 s expiry"; offline clients show `--`; router WAN traffic is shown separately as "combined traffic"; per-client daily usage is "Not measured". 111/111 tests, production build passes. The Pi gateway card now says "Loading…" until status arrives (committed, **not deployed**).
- **Telemetry limitation:** client inventory only arrives while TT Router is open on a paired phone. Permanent visibility needs a LAN-side observer on the TaoTronics network (not installed).

### 1.6.0+9 — Network Hub (2026-10-18, installed on the Fold4)
- **Navigation:** "Gateway" is now **Network Hub**, with the hero "Argon · Raspberry Pi 4 Model B". Automatic LAN/Tailscale/Bluetooth connection is kept; pairing moved to a sheet.
- **Traffic:** live rates (Mbps from 1 Mbit/s, KiB/s below), a 10-minute chart, today/last 7 days/this month, a 14-day chart, previous-period comparison only when both periods are ≥95 % measured, and VPN share shown as part of the total (never added to it).
- **VPN card:** mode, state, exit, tunnel, last change, kill switch and health. The toggle requires the **operator** token, which is kept in separate secure storage and used as a signed `ArgonOperator` HMAC request so the token never crosses the LAN. It has a confirmation, single-flight pending state, re-read before success, and 401/403/409/502 messages with recovery text. The Bluetooth bridge can't relay writes, so the app says so.
- **Home:** live rates, today/week/month, router device count labelled with source and age, Network Hub, internet and VPN status, recent notifications.
- **States:** Loading / Live / Stale / Unreachable / Not reported / Not measured, never 0 for unmeasured. Devices show live rates, mesh node and an explicit "historical per-device usage not measured".
- **Checks:** analyzer clean, 135 tests. Verified on the device: MQTT connected, 19 devices, sync shared 21 devices, VPN on/connected/London, kill switch enforced (0 packets), cover and emulated unfolded layouts.
- **Not done:** no live VPN toggle (not approved; mocked in tests). The operator token wasn't entered on the phone, so the signed write path was proven only against the staged server with invalid bodies.

### Pipeline audit (2026-10-18)
- **Path:** eth1 nftables counters (forward chain, 2 s) → `argon-device-monitor` → SQLite `usage_daily` → `/api/network/usage`, `/api/devices/live` → `/api/v1/gateway` → `PiProvider` → Home and Network Hub.
- **Units:** rates are bits/s, totals are bytes, and eth1 TX = household download. A 10 s kernel sample (2.3 Mbit/s down) agreed in magnitude with the 1-minute average; the 2 s instantaneous samples are bursty.
- **Totals:** gateway usage equals `/api/network/usage` byte for byte.
- **Scope:** kernel eth1 counters also include Pi-local traffic (dashboard and app polling), which the forward-chain accounting rightly excludes.

### Pi reboot and power review (existing logs only)
- **Reboot timing:** the unexpected reboot happened between 10:01:34 and about 10:02:35 on 2026-10-18, while the eth0 cable was connected and the USB Wi-Fi adapter disappeared.
- **No record:** the journal is volatile (`Storage=auto`, no `/var/log/journal`), so the previous boot left nothing. The hardware watchdog (1 min) is armed.
- **Power:** gateway events show active throttling from 2026-10-17 20:45 to 2026-10-18 09:15. Undervoltage flags are clear now (`0x0`, `uv=0`).
- **Clock:** the backwards timestamps after boot come from the restored clock before NTP.
- **Likely cause:** a supply dip from USB hot-plug (unproven).
- **Suggestions (not applied):** a persistent journal and an official 5.1 V/3 A supply. No system changes were made.

### 1.6.1+10: multi-phone and OnePlus investigation (2026-10-18)
- **Two-phone cause A (fixed):** V2 wireless probes were repeated every 30 s whenever the V1 fallback timed out, and each one stalled the router's single command queue for all phones. The verdict is now recorded on no-reply and persisted, and the telemetry timeout is 8 s. On the OnePlus: 0 V2 probes and 0 timeouts after restart. See [MULTI_DEVICE_CONNECTION_REVIEW.md](MULTI_DEVICE_CONNECTION_REVIEW.md).
- **Two-phone cause B (router limit, handled in 1.6.2+11):** the router serves one active phone at a time and answers `ErrorCode 5` to the others. Access moves 60–80 s after the holder goes idle and can't be taken over. The app now shows "Another phone is managing the router", backs off to one probe every ~21 s, and recovers automatically. This was validated on both phones.
- **OnePlus taps:** with a debug-only pointer/route probe, every injected tap reached Flutter and navigated, including the full first-run discovery → Continue → Home path. The original failure couldn't be reproduced. A dump taken during it returned another app's overlay controls (an unproven lead). Fixed defects: landscape `NavigationRail` overflow (regression test at 800×330) and a location prompt on every discovery scan.
- **Nokia and mesh:** [NOKIA_PROTOCOL_INVESTIGATION.md](NOKIA_PROTOCOL_INVESTIGATION.md) and [MESH_COMPATIBILITY.md](MESH_COMPATIBILITY.md). There is no shared mesh, and a bridged Nokia AP is the supported fallback. `Game Labs-2.4G` is a client-facing 2.4 GHz network on the TaoTronics radio.

## 7. Releases, branches and rollback

- APKs in `artifacts/releases/` (git-ignored): `tt-router-1.3.1-*.apk`, `tt-router-1.4.0-argon.apk`, `tt-router-1.5.0-8.apk` (SHA-1 `60d81c27a1db4f9e48bab4efd828ecde32a82154`), `tt-router-1.6.0-9.apk` (SHA-1 `aa6dd9ab64912ce59a8dbe09db51160bbc45b177`), `tt-router-1.6.2-11.apk` (SHA-1 `40260de606e72960ffbca06aae48b7dc6aff6a93`, installed on the Fold4 and the OnePlus; both signer SHA-256 `c5f7a819…00ab89`). Downgrade needs uninstall (loses pairing); prefer forward fixes.
- Flutter remote: `origin` (GitHub `alfeyo/Taotronics-AC3000-Wi-Fi-App`); branch not merged to `main`.
- Dashboard: no git remote; commits are local only. Pi rollbacks: `~/argon-backups/release-20261018-110003/rollback.sh` (Network Hub API, build `RMfC8snyfaHkDDD5P93Z1`), `~/argon-backups/release-20261018-091546/rollback.sh` (earlier dashboard), `~/argon-backups/btbridge-20261018-084451/rollback.sh` (Bluetooth bridge), `~/argon-backups/router-20261017-204546/rollback.sh` (router integration).

## 8. Future work

1. Physical survey of Nokia ports and ISP equipment (Stage 0).
2. Wired WAN test and soak after approval.
3. LAN-side observer for permanent client visibility.
4. Approved secondary WAN for Argon once Nokia Wi-Fi is off.
5. Deploy the dashboard "Loading…" fix; add a git remote for argon-dashboard.
