# Nokia uplink recovery and dedicated wireless bridge options

18 October 2026, Africa/Lusaka. **Current owner scope: Beacon 1 only; second-Beacon enrollment is set aside.** Preserve Argon production interfaces, routing, VPN, DHCP, Tailscale and OnePlus backup. No hardware purchase or new network configuration was performed.

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

A concrete matched-pair candidate is **TP-Link Omada EAP211-Bridge KIT**: the vendor documents automatic main/client pairing and multiple Ethernet ports. Its setup guide uses an upstream DHCP server. This supports evaluating the paired architecture; it is not proof of this household's DHCP/MAC transparency or radio coverage. Regional hardware revisions, regulatory suitability and stock need checking before purchase. [Product](https://www.omadanetworks.com/us/business-networking/omada-wifi-wireless-bridge/eap211-bridge-kit/), [setup guide](https://static.tp-link.com/upload/manual/2025/202504/20250418/Bridge%20AP%20Start%20Guide.pdf)

A dedicated pair needs appropriate placement and power; walls, distance and interference can make a nominal link unsuitable. No vendor range/PHY-rate claim is a measured household result.

## Acceptance checks before replacing the long cable

1. Bench-test the candidate pair separately with two clients of distinct MAC addresses. Confirm both obtain simultaneous TaoTronics `192.168.10.x` leases and gateway `192.168.10.1`; inspect upstream leases/ARP for actual client MAC visibility rather than one translated address.
2. Confirm bridged mode, no additional DHCP server or NAT, bidirectional LAN reachability, DHCP renewals and broadcast/multicast behavior. If IPv6 is used, test it explicitly too. An internet-only speed test is insufficient.
3. Record source configurations, addresses and cabling. Prepare the original Ethernet path for immediate recovery. Do not connect parallel bridged paths and create a loop.
4. Only after a separate bench pass, schedule/approve the root uplink change. Verify Nokia root and extender management, DHCP, gateway, DNS and Wi-Fi-bound HTTPS from actual Nokia BSSIDs.
5. Test concurrent clients, sustained throughput, loss/latency, bridge restart recovery and the intended locations. Then walk a real client between Beacons, recording BSSID transitions and connection continuity. Shared SSID alone proves neither backhaul nor roaming.
6. Revert to the original root cable on failed association, DHCP, management or internet checks. Preserve Argon configuration throughout.

## Nokia mesh and broadcast changes

The owner has set the second unit aside and directed work to Beacon 1 only. No serial/model was supplied. Its association, backhaul medium/RSSI, internet and coverage remain unverified. The root is restored. Keep `NOKIA-E6C0` WPA2/AES until an explicit impact review/approval covers migration to `Nokia Wifi`. Distinct management names are separate from a shared SSID. No naming or SSID write was sent.
