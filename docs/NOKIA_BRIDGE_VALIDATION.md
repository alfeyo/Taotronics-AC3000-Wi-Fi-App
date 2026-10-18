# Nokia bridge and mesh validation

Prepared 18 October 2026, Africa/Lusaka. **Not provisioned or validated yet.**

The owner reports both Beacons factory-reset and powered off. Their former
192.168.18.1 identity and saved setup SSID are historical evidence only.
TaoTronics currently broadcasts `Nokia Wifi`. Exact Beacon models and firmware
remain unknown; no cross-model compatibility is assumed.

## Approved software preparation

Argon has a dedicated `/nokia` destination and the app has Nokia Mesh in Network
Hub. They distinguish setup guidance from successful observations. No Nokia
credentials or speculative write endpoints are embedded. The APK analysis is a
protocol reference, not permission to issue unverified enrollment commands.

## Staged procedure (hardware activation approval required)

1. Read both model labels and port labels. Keep the extender off initially.
2. After approval, connect **TaoTronics LAN → root Beacon WAN**, one cable only.
   Use Nokia WiFi's official setup flow with a temporary validation SSID. Do not
   reuse the household SSID at this stage. Record reported model/firmware.
3. Set the root to AP bridge through Nokia WiFi. Enroll the second compatible
   Beacon with that app. For Ethernet backhaul use **root LAN → extender WAN**;
   wireless backhaul is conditional on verified models and adequate signal.
4. Verify one DHCP server (TaoTronics), a client lease in the TaoTronics LAN,
   TaoTronics as default gateway, no second NAT, and traffic visible at Argon.
   Check both Beacon roles/backhaul in Nokia WiFi, then test coverage beside the
   extender. Record actual response timestamps and authenticated schemas before
   implementing a Nokia telemetry adapter.
5. Only after those checks and **separate explicit approval**, apply existing
   household `Nokia Wifi` credentials through secure existing configuration.
   TaoTronics and Nokia remain separate Wi-Fi management systems; test roaming
   rather than promising seamless cross-vendor mesh.

Temporary impact: the Nokia setup SSID and the test phone may reconnect during
onboarding/bridge-mode changes. TaoTronics remains the household router; Argon
routing, DHCP, NAT, firewall, VPN, SSH and Tailscale are unchanged.

Rollback: unplug the Nokia uplink and power both Beacons off. Do not reset or
reconfigure TaoTronics or Argon. Do not add a second Layer 2 path.

## Evidence checklist

| Check | Status |
|---|---|
| Exact models / firmware | Awaiting physical labels and official onboarding |
| Root enrolled / extender enrolled | Not performed |
| AP bridge read-back | Not performed |
| One DHCP server / no second NAT | Not performed |
| Nokia mesh/backhaul quality | Not observed |
| Client internet via Argon | Awaiting isolated Nokia client |
| Extender coverage / roaming | Not measured |
| Production SSID approval | Not requested; isolated validation comes first |

## Official references

Nokia supports bridge mode using the upstream router's addressing, with a
LAN-to-WAN connection between Beacons. [Networking modes](https://wifi-helpcenter.nokia.com/hc/en-us/articles/4421210042263-Overview-of-networking-modes).
Ethernet backhaul works in bridge mode; connect a root LAN port to the added
Beacon's WAN port. [Ethernet backhaul](https://wifi-helpcenter.nokia.com/hc/en-us/articles/18613029582103-Ethernet-Backhaul).
Enrollment uses the Nokia WiFi app. [Root setup](https://wifi-helpcenter.nokia.com/hc/en-us/articles/18612285123607-Set-up-your-Nokia-WiFi),
[Add a Beacon](https://wifi-helpcenter.nokia.com/hc/en-us/articles/18612846449815-Extend-your-network-coverage-by-adding-a-Beacon-Wi-Fi-point-and-Ethernet-cable).
