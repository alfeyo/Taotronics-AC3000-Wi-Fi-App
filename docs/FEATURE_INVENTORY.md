# Feature Inventory

Baseline: commit `8891fb1` (tag `known-good-internet-fix`), recorded 2026-10-17
before the stability/UX overhaul. Every control below must stay reachable.
"After" is the location in the redesigned app; the "Verified" column is ticked
once the control has been exercised on the finished build.

Router protocol: local MQTT over TLS, port 25678, topic `<meshId>/<appId><path>`,
replies on `<appId><path>`. Discovery: UDP broadcast on port 52011.
BLE provisioning: native `tt_router/ble_provisioning` channel (`MainActivity.kt`).

## Navigation shell

| Before | After |
| --- | --- |
| Splash → Discovery → Home (bottom nav: Dashboard, Settings) | Splash → Discovery → Home shell (Home, Devices, Wi-Fi, Settings); navigation rail on wide/unfolded screens |
| Back on Home/Discovery asks "Leave app?" | Unchanged |

## Discovery screen (`discovery_screen.dart`)

| Control / function | Service call | After |
| --- | --- | --- |
| Location permission request | `permission_handler` | Unchanged, with a recoverable "open settings" path |
| Wi-Fi name, phone IP, gateway IP | `network_info_plus` | Unchanged |
| Gateway reachability check (port 80 + DNS fallback) | `Socket.connect` | Replaced by TCP probe (80/443/25678; refused = reachable) |
| MQTT port check (25678) | `Socket.connect` | Unchanged |
| Continue to Dashboard / Pair Router / Continue read-only / Retry | navigation | Unchanged |
| Diagnostics (app bar + text button) | navigation | Unchanged |
| Pull to refresh | re-run checks | Unchanged, plus automatic re-check on connectivity change |

## Home / Dashboard (`home_screen.dart` `DashboardTab`)

| Control / function | Service call | After |
| --- | --- | --- |
| Router name + status in app bar | provider | Home hero |
| Diagnostics button | navigation | Home app bar |
| Refresh button | `refreshAll` | Home app bar + pull to refresh |
| Log out (confirm) | `logout` | Home app bar menu |
| Setup banner (Device/Gateway/MQTT/Access steps, Setup Router, Diagnostics) | navigation | Home, shown when not connected |
| Connection status card (Wi-Fi name, IP, Open Setup) | provider | Home hero |
| Connection path chips (Gateway, MQTT, Access) | provider | Home "Connection" details |
| Mesh nodes stat → Nodes screen | `GetSysConnectInfo` / `GetExistNode` | Home mesh card → Nodes screen |
| Devices stat → Devices screen | `GetSysConnectInfo` / `GetDevListInfo` | Home devices card + Devices tab |
| Network quality stat | `GetSysConnectInfo.NetworkQuality` | Home internet status |
| Live throughput (WAN or device sum) | `GetWanRateInfo`, device rates | Home throughput card (source labelled) |
| "Total Data Usage" (sum of device byte counters) | `GetDevListInfo` | Home, relabelled "Traffic of connected devices" |
| Quick action: Wi-Fi | navigation | Wi-Fi tab + Home quick action |
| Quick action: Storage | navigation | Home quick action + Settings |
| Quick action: Parental ("coming soon" placeholder, no function) | none | Listed under Settings → Not available (no fake control) |
| Quick action: Reboot (confirm) | `SetSystemRestartNow` | Home quick action + Settings |
| Error card with dismiss | provider | Home banner |
| Auth-required dialog → Setup wizard | navigation | Unchanged |

## Wi-Fi (`home_screen.dart` `WifiSettingsScreen`, `settings_screen.dart` `WifiSettingsDetailScreen`)

| Control / function | Service call | After |
| --- | --- | --- |
| List SSIDs per band, on/off, security, password masked | `GetWirelessInfoListV2` → `GetWirelessInfoList` | Wi-Fi tab |
| Edit SSID/password per network (dialog) | `SetWirelessInfoList` | Wi-Fi tab → edit sheet |
| 2.4/5 GHz form with enable switches, save | `SetWirelessInfoList` | Wi-Fi tab → "Edit both bands" |
| Refresh | `GetWirelessInfoList*` | Wi-Fi tab |
| Guest Wi-Fi link | `GetGuestInfo` / `SetGuestInfo` | Wi-Fi tab section + Settings |

## Devices (`devices_screen.dart`)

| Control / function | Service call | After |
| --- | --- | --- |
| Online/offline groups, summary | `GetDevListInfo` | Devices tab |
| Device name, IP/MAC, type icon, rates | `GetDevListInfo` | Devices tab + device detail sheet |
| Refresh + pull to refresh | `refreshDevices` | Devices tab |

No block/prioritise/schedule actions exist today; none will be added.

## Mesh nodes (`nodes_screen.dart`)

| Control / function | Service call | After |
| --- | --- | --- |
| Node list: name, master badge, online, clients, model, firmware, IP, SN | `GetExistNode` | Nodes screen |
| Signal bars (drawn even when the router reported none) | — | Shown only when the router reports a value |
| Refresh | `refreshNodes` | Unchanged |

## Settings (`settings_screen.dart`, `router_settings_screens.dart`)

| Entry | Service call | After |
| --- | --- | --- |
| Wi-Fi Settings | wireless | Settings → Network |
| USB Storage (USB3, SMB, anonymous, share address, disks) | `GetPrivateStorageV2`, `GetDiskInfo`, `GetVisitAddress`, `SetPrivateStorageV2` | Settings → Network |
| Guest Wi-Fi | `GetGuestInfo`, `SetGuestInfo` | Settings → Network |
| WAN & DNS (DHCP/Static/PPPoE/Bridge, DNS, VLAN) | `GetMWanInfo`, `SetMWanInfo` | Settings → Network |
| LAN (IP, mask, DHCP range, VLAN) | `GetLanInfoV3`/`GetLanInfo`, `SetLanInfoV3` | Settings → Network |
| Security & NAT (firewall, UPnP, DMZ, Fast NAT) | `Get/SetFirewallInfo`, `Get/SetUpnpDmz`, `Get/SetFastNatInfo` | Settings → Advanced |
| QoS | `Get/SetQosInfo` | Settings → Advanced |
| VPN client (PPTP / L2TP-IPsec, status) | `GetVpnInfo`, `GetVpnStatus`, `SetVpnInfo` | Settings → Advanced |
| Port forwarding (list, add, edit, delete) | `Get/Add/Set/DelVirServerList` | Settings → Advanced (delete now confirms) |
| DNS Settings (links to WAN) | — | Settings → Advanced |
| DDNS | `GetDdnsInfo`, `GetDdnsStatus`, `SetDdnsInfo` | Settings → Advanced |
| Firmware status (read-only) | `GetExistNode` | Settings → System |
| Router LEDs per node | `GetLedList`, `SetNodeLed` | Settings → System |
| Restart schedule + restart now | `Get/SetSystemRestartInfo`, `SetSystemRestartNow` | Settings → System |
| Backup & Restore (informational: unsupported) | none | Settings → Not available |
| Reboot (confirm) | `SetSystemRestartNow` | Settings → System |
| Factory reset (informational: use reset button) | none | Settings → Not available |
| About | — | Settings → About (version from build) |

## Setup and pairing

| Screen / control | Service call | After |
| --- | --- | --- |
| Setup wizard: quick start (BLE search → Wi-Fi → provision → join Wi-Fi → finish) | `discoverRouter`, `provisionRouter`, `openWifiPicker` | Unchanged flow, clearer errors and permission recovery |
| Setup wizard: guide (welcome, need, modem, LED + LED guide, Bluetooth, found, room, Wi-Fi, creating, connect Wi-Fi, finish) | same | Unchanged |
| Wi-Fi join verification (auto on resume) | `network_info_plus` | Unchanged |
| Pairing screen: BLE provisioning form | `provisionRouter` | Unchanged |
| Pairing screen: automatic / manual (mesh ID, IP, optional password) | MQTT connect | Unchanged |
| Pairing status rows | provider | Unchanged |

## Diagnostics (`diagnostics_screen.dart`)

| Control / function | After |
| --- | --- |
| Status overview (Wi-Fi, IP, gateway, reachability, MQTT port, MQTT auth, router SSIDs) | Unchanged + TLS verification state |
| Run diagnostics (interfaces, ports 80/443/25678, UDP, provider state) | Unchanged |
| Copy JSON export to clipboard (passwords excluded) + preview | Unchanged |
| Log list with counts | Unchanged |

## Background behaviour

| Behaviour | After |
| --- | --- |
| UDP discovery listener from app start | Unchanged |
| Auto-connect first discovered router | Unchanged |
| Reconnect with backoff 1/2/4/8 s for paired routers | Serialized, cancellable |
| Live refresh every 3 s (devices + telemetry), full refresh every 30 s | Unchanged cadence; paused in background; no overlapping requests |
| Saved pairings in SharedPreferences (with MQTT password) | Passwords moved to Android Keystore-backed storage, with migration |

## Verification record (build 1.1.0 (2), 2026-10-17)

Every row above was mapped to its new location and is reachable in the
finished build. Checked on the Galaxy Z Fold4: discovery checks and buttons,
diagnostics (run, findings, copy), dashboard (refresh, menu: diagnostics/log
out, metric tiles, quick actions, connection details), Devices (search,
filters, sort menu, details sheet), Wi-Fi (cards, reveal, edit sheet,
guest Wi-Fi and both-bands links), Settings (all groups; WAN read-only open),
setup wizard Bluetooth search. Write paths were tested against a fake router
in automated tests rather than on the live router.

New since baseline: Settings → Mesh nodes, Diagnostics, Set up a router;
device search/filter/sort/details; measured latency in diagnostics.
Replaced: Parental "coming soon" tile → Settings → Not available entry;
"Total Data Usage" card removed (router reports no per-device usage).

## 1.2.0 smart-home redesign (2026-10-17)

| Control | Location in 1.2.0 |
| --- | --- |
| Per-network on/off (every reported network, incl. index 2) | Wi-Fi tab → network card switch (confirmed) |
| Per-network name/password edit | Wi-Fi tab → card → Edit |
| Password show/copy | Wi-Fi tab → card → Show / copy icon |
| Network counts (reported / on / names broadcasting) | Wi-Fi tab header pills; Home hero and Wi-Fi panel |
| Edit both bands together | Wi-Fi tab → "Edit both bands together"; Settings → Wi-Fi settings |
| Guest Wi-Fi (state + manage) | Wi-Fi tab guest card; Home "Guest Wi-Fi" pill; Settings |
| Main router LED switch | Home → Quick controls → Router lights; Settings → Router LEDs card |
| Per-node LEDs | Settings → View all LED settings / Router LEDs entry; LED state on Mesh nodes |
| Diagnostics / Restart / Log out | Home header "…" menu; Home pills (Diagnostics, Restart); Settings → System |
| USB storage | Home "USB storage" pill; Settings → Network |
| Health and connection details (internet, quality, uptime, guest devices, storage, live statistics, address, certificate, saved password) | Home → Network health → Health details |
| Advanced settings (WAN, LAN, security, QoS, VPN, port forwarding, DNS, DDNS, firmware, restart schedule, setup, not-available items, about) | Settings (each entry verified present on device) |
