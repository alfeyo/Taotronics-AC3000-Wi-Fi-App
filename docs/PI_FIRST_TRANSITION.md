# Pi-first transition (1.11.0+22, 24 October 2026)

TT Router now opens on **Argon** (the Raspberry Pi gateway) and takes all monitoring, statistics, devices and notifications from it. The TaoTronics router is a secondary *Managed router*. The phone touches the router only after the user deliberately takes **Direct Router Control**.

## Verified router → Argon data path

```
TaoTronics ND001 (192.168.10.1, MQTT/TLS 25678, LAN side only)
   │  one read-only management session, polled every 10 s
   ▼
Dell LAN observer  argon-tt-observer (Node, user cron @reboot + */5 watchdog, flock single instance)
   │  POST /api/v1/router/observation  (Tailscale, hashed per-relay bearer)
   ▼
Argon /api/v1/gateway.router  →  TT Router (LAN 192.168.50.1 → Tailscale 100.94.137.17 → Bluetooth)
```

* Authoritative source: `lan-observer:dell`. Source priority on Argon: fresh direct adapter → fresh LAN observer → fresh phone snapshot. If none is fresh, the newest is used and labelled stale. Older snapshots never replace newer ones (409 on out-of-order).
* Audited 16:52: snapshot 18 s old, 49 known / 23 online clients. Per-device estimated usage covered 99.2% of the day. Observer RSS 62 MB at 0.1% CPU. Household totals come from Argon eth1 nftables (SQLite history since 2026-09-25), VPN is the tun0 subset, and nothing is counted twice.
* Single-controller conflict seen live: 12:47–12:49, 28 reconnect cycles between the observer and another controller.
* **Outage at close-out:** the Dell went offline at about 17:12 (Tailscale "offline", LAN unreachable). Argon's router data is therefore stale. The app says so, and nothing replaces the collector. Power the Dell on to restore it. The observer restarts from cron.

## What changed in the app

| Area | Argon mode (default) | Direct Router Control |
|---|---|---|
| Start-up | Splash waits up to 8 s for Argon, then opens Home. No router discovery, MQTT or polling. | — |
| Home | Pi hero: transport, internet source, VPN and location, uptime, last update. Live eth1 rates, today's down/up/total with coverage, 14-day activity, device and event counts, Managed router card, controls | Same Home, plus a Direct Control banner |
| Devices | Argon client inventory: search, filters, sorting, details. Per-device usage shown as **Estimated usage** with coverage | Original router device list |
| Statistics | Argon real-time, period totals ("≥" when partial), history, VPN share, device activity, collection coverage | Original router statistics |
| Wi-Fi | Capability matrix. Every write needs Direct Control (Argon has no router write handler) | Original advanced Wi-Fi screen with WPA2 safeguards |
| Router details | As Argon observes it, plus Take Direct Router Control | Original router dashboard (hero, LEDs, mesh) |
| Settings | Router control card (Argon mode / Take control) | Live router settings plus Return to Argon |

### Direct-router paths: removed, disabled or override-only

* **Override-only:** router discovery beacons, MQTT connect/authenticate, live 5 s and 30 s polling, reconnect backoff, every router write, and phone → Argon snapshot sharing (`/api/v1/router/snapshot`). All are gated by `RouterAccessPolicy.directControlEnabled`, which is false from start-up (`RouterProvider(directControl: false)`).
* **Removed from start-up:** the splash's 12 s router reconnect wait. The "Connecting to your router…" text is gone.
* **Retained unchanged** for Direct Control: router-backed Devices, Statistics, Wi-Fi, Router settings, LEDs, mesh, USB and pairing screens.

## Direct Router Control

1. An explainer dialog states what pauses (router monitoring) and what keeps running (internet, VPN, NAT, DHCP, Tailscale, accounting).
2. The phone sends a signed (ArgonDevice v2) `POST /api/v1/router/lease {"action":"acquire"}`. It is refused (409) if another phone holds the lease.
3. Argon's next observation reply carries `control.yield`. The observer sends an MQTT DISCONNECT and checks the lease every 10 s. The phone polls until `handover` is `observer-yielded` or `observer-offline`, for at most 45 s. On timeout it releases the lease and shows the blocker.
4. The phone connects with its saved pairing. Nothing is re-paired or wiped. If the router still serves the previous holder, the banner says *Waiting for the router handover* (about 60–80 s).
5. Once active, the lease renews every 30 s. TTL is 120 s, with a 2-hour hard cap.
6. **Return to Argon** stops polling and reconnects, closes the MQTT session, releases the lease and refreshes Argon data. It then watches up to 3 minutes for a fresh observation ("Argon monitoring resumed" or a warning).
7. Backgrounding stops renewals. A lease that lapsed is detected on resume and ends Direct Control. Crashes and lost phones also expire after 120 s, so no permanent lock is possible.
8. If Argon cannot coordinate (unreachable, Bluetooth only, phone not paired), the dialog shows the exact blocker and offers a clearly labelled *Connect anyway*. Router reconnects stay capped at 6. The updated observer backs off from 5 s up to 5 min when its sessions keep being closed.

## Notifications

One notification center merges Argon events, Argon usage alerts and phone-local events, each labelled. Argon events cover VPN, uplink, collector, router reconnect/disconnect, stale inventory, direct-control start/end, temperature, and throttling (rate-limited to once per 15 min; it flapped every ~30 s live). Usage alerts are fetched every 60 s while the app is open with the phone's device signature, shown, then acknowledged. **There is no background push**, and nothing was verified as delivered to a closed app on the Fold4.

## Controls on Home

VPN on/off and location (existing signed, confirmed, read-back flow). Also: Refresh, Retry Argon, Diagnostics (Network Hub), and the Argon dashboard (Tailscale). No reboot, Wi-Fi or system commands.
