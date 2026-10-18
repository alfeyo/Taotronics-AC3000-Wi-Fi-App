# Nokia bridge and mesh validation

Verified 18 October 2026, Africa/Lusaka. This supersedes the earlier powered-off / official-app-only preparation notes.

## Root: verified on hardware

| Item | Observation |
|---|---|
| Model | Nokia WiFi Beacon 2; hardware 3FE49294BAAA |
| Identity | ALCLB4392160; root MAC b4:63:6f:db:e6:c0 |
| Firmware / local API | 3FE49334IJJJ09 / CGI 5.5 |
| Physical uplink | Existing TaoTronics LAN → root uplink, left in place |
| Factory state | NOKIA-E6C0; routed management 192.168.18.1; WAN 192.168.10.101 |
| Owner management | Printed local admin credentials; encrypted WebGUI nonce/RSA/AES exchange from TT Router; stored separately in Android secure storage |
| Mode change | Sent from TT Router through the verified local WebGUI bridge endpoint |
| Read-back | Same serial/MAC, AP_Bridge; management DHCP address 192.168.10.97 |
| Client | Fold4 on b4:63:6f:db:e6:c9 (2.4 GHz), then …:cd (5 GHz), SSID NOKIA-E6C0 |
| Client DHCP / gateway | 192.168.10.217/24; Android DHCP event reports server 192.168.10.1; default gateway 192.168.10.1 |
| Internet | Wi-Fi-bound HTTPS generate_204 returned 204 |
| Preserved controls | Fold4 retained TaoTronics pairing; live TaoTronics device inventory and Argon traffic visible through Nokia |

The client observation verifies a bridged path without a Nokia NAT hop for that client. It does not prove that no rogue DHCP server exists anywhere on the network. The LAN configuration CGI still exposes an enabled, old 192.168.18.x DHCP configuration, while actual AP-mode client provisioning came from TaoTronics. Do not infer active DHCP service from that stored configuration alone.

Factory SSID and security were retained. No household SSID/password, TaoTronics wireless profile, Argon routing/firewall/NAT/DHCP/VPN/SSH setting was changed in this phase. A household-SSID migration still needs owner approval.

## Second Beacon: pending owner activation

The root reports an empty `beacon_detail` list, 0 entries and maximum capacity 6. A single request for the second Beacon to be powered on near the root and for its printed ALCL serial has been sent. No second-node enrollment or removal has occurred.

TT Router prepares local encrypted `mesh_web_app.cgi?add` / `?del` commands verified from this root’s WebGUI. Addition requires a fresh bridge/client-path check, a distinct valid serial, available capacity and explicit UI confirmation that the unit is powered on. Acknowledgment is pending until the inventory is read back; listed enrollment alone is not mesh connectivity or backhaul verification. Backhaul, coverage, roaming and cross-model compatibility remain unverified.

## Validation limits

- OnePlus is not currently attached; no 1.9.0 installation or physical navigation claim is made for it.
- Narrow, Fold-sized and landscape rendering are covered by Flutter widget tests.
- Native IPv6 discovery remains a candidate path; this successful Android management session used IPv4. The factory IPv6 endpoint was independently reachable through phone-bound curl.
- Firmware/radio/guest write payloads are not fully validated for Nokia; there are no speculative buttons for them. Current radio/security/channel settings are read-only.
- The root’s local mobile login endpoint rejected this firmware’s owner login. The verified WebGUI flow is deliberately gated to Beacon 2 / CGI 5.5.
