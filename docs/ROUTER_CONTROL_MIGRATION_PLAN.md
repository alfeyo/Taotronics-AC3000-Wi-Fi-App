# Router control ownership: architecture and migration plan

Status: proposed. Written 2026-10-22 against app 1.9.3+20 (`codex/nokia-home-app`).
Owner approval required for the topology prerequisite in §2.1 before Phase 2.

## 1. Decision

The Raspberry Pi (Argon) becomes the sole router controller. The mobile app becomes a
client of Argon's API and holds no router transport of any kind.

```
Phone app  ->  Pi API (HTTPS / Tailscale)  ->  Argon router agent  ->  TaoTronics MQTT
```

Invariants, each with an enforcement mechanism rather than a convention:

| # | Invariant | Mechanism |
|---|---|---|
| I1 | Exactly one process holds the router management lease | Pi `flock` + lease row; second instance exits |
| I2 | The app cannot open a router socket | Router transport deleted from the app; architecture test on the source tree |
| I3 | The app cannot fall back to direct control | `RouterGateway` has one production implementation, `PiRouterGateway`; no fallback branch exists |
| I4 | Router state shown is Argon's observation, never the app's | Snapshot upload path retired; every state field carries `observedAt` + source |
| I5 | A failed Pi link fails closed | App renders "router unavailable via Network Hub" and stops |

## 2. Verified current state

### 2.1 Topology gate (blocks Phase 2)

`docs/NETWORK_MIGRATION_OVERVIEW.md` records the live layout:

```
MikroTik 192.168.88.1
  └─ Argon eth0 192.168.88.250   (WAN, VPN tun0, Tailscale 100.94.137.17)
       └─ Argon eth1 192.168.50.1/24  (NAT for the router's WAN only)
            └─ TaoTronics WAN 192.168.50.181
                 └─ TaoTronics LAN 192.168.10.0/24  <- management port 25678 lives here
```

Argon sits **upstream** of the router. `docs/ROUTER_PROTOCOL_HANDOFF.md:328` requires the
Pi to be on the router's LAN. It is not, and `docs/MULTI_DEVICE_CONNECTION_REVIEW.md §4`
records the consequence: the control port is refused from the Pi's current position.

Argon therefore cannot become the controller until it has an interface on
`192.168.10.0/24`. Three options, in ascending cost:

- **A. Second interface on the router LAN.** USB Ethernet adapter on Argon cabled to a
  TaoTronics LAN port. Leaves WAN/VPN/routing untouched. Cheapest, lowest risk, and the
  only option that does not invert the household topology. Requires a free LAN port.
- **B. Move Argon behind the router.** Argon becomes a LAN client; the TaoTronics becomes
  the upstream router. Inverts WAN/VPN placement, changes double-NAT direction, moves the
  kill switch and Tailscale endpoint, and invalidates "household traffic measured at
  Argon eth1". A network redesign, not a config change.
- **C. Expose management to the WAN.** Not supported by the firmware and contradicts the
  handoff. Rejected.

Recommendation: **A**. It is reversible (unplug the adapter) and preserves every verified
network property. Do not start Phase 2 before a `nc -vz 192.168.10.1 25678` from Argon
succeeds.

### 2.2 What exists today

The app is the controller. `RouterProvider` owns a `MqttService` and a
`RouterDiscoveryService` (`lib/providers/router_provider.dart:64-65`), auto-connects at
startup, and performs every read and write. The Pi is a monitoring sink: the app uploads
router observations to `POST /api/v1/router/snapshot`
(`lib/providers/pi_provider.dart:862`, payload built in `lib/services/pi_snapshot.dart`).
The Pi's `POST /api/v1/router/control` returns `409` by design (`docs/ARGON_API_V1.md`).

## 3. Complete router communication inventory

### 3.1 Network egress from the app

| Transport | Endpoint | Code | Purpose |
|---|---|---|---|
| MQTT 3.1.1 over TLS, TCP 25678 | router IP | `lib/services/mqtt_transport.dart:75` | every router command |
| UDP 52011 | broadcast | `lib/services/router_discovery.dart:20-33` | router discovery |
| TCP 25678 / 80 / 443 | gateway | `lib/services/network_probe.dart` | reachability, "MQTT port open" |
| UDP bind (local) | — | `lib/screens/diagnostics_screen.dart:252` | socket availability check |
| HTTP/HTTPS | Argon `192.168.50.1`, `100.94.137.17`, manual | `lib/services/pi_api.dart:187` | **permitted** — Pi API |
| BLE SPP | Argon | `lib/services/pi_api.dart` `BluetoothPiTransport` | **permitted** — read-only Pi API |
| BLE GATT | new/reset router | `lib/services/ble_provisioning_service.dart` | router commissioning |
| HTTPS (encrypted form) | Nokia root `192.168.10.97` | `lib/services/nokia_service.dart` | Nokia Mesh control plane |

No router MQTT, socket, or discovery code exists in Kotlin; the only native sockets are
`ArgonBluetooth.kt` (Pi) and the Nokia platform channel. No background service or
WorkManager exists, so nothing connects to the router while the app is not in the
foreground.

### 3.2 Services that exist only to talk to the router

| File | Lines | Disposition |
|---|---|---|
| `lib/services/mqtt_service.dart` | 923 | delete from app; logic moves to Argon |
| `lib/services/mqtt_transport.dart` | 165 | delete; moves to Argon |
| `lib/services/router_discovery.dart` | 167 | delete |
| `lib/services/router_certificate_verifier.dart` | 354 | delete; moves to Argon |
| `lib/services/auth_pairing_service.dart` | 283 | delete; router credentials move to Argon |
| `lib/services/credential_store.dart` | 71 | delete; app stops holding router passwords |
| `lib/services/network_probe.dart` | 87 | delete; reachability becomes a Pi report |
| `lib/services/pi_snapshot.dart` | 109 | delete; direction is reversed once the Pi observes directly |

### 3.3 `RouterProvider` public surface (all direct-router)

Reads: `refreshAll`, `refreshTrafficStats`, `refreshLiveTelemetry`, `refreshSystemStatus`,
`refreshDevices`, `refreshNodes`, `refreshWirelessSettings`, `refreshWanSettings`,
`refreshLanSettings`, `loadGuestWifiSettings`, `loadFirewallSettings`,
`loadUpnpDmzSettings`, `loadQosSettings`, `loadFastNatSettings`, `loadVpnSettings`,
`loadVpnStatus`, `loadVirtualServers`, `loadDdnsSettings`, `loadDdnsStatus`,
`loadLedSettings`, `refreshLeds`, `loadRestartSchedule`, `refreshUsbStorage`,
`loadWanSettings`, `loadLanSettings`, `measureRouterResponse`.

Writes: `updateWirelessNetwork`, `setWirelessNetworkEnabled`, `saveWirelessNetworks`,
`setWirelessSettings`, `updateWanSettings`, `updateLanSettings`, `updateGuestWifiSettings`,
`updateFirewallSettings`, `updateUpnpDmzSettings`, `updateQosSettings`,
`updateFastNatSettings`, `updateVpnSettings`, `addVirtualServer`, `updateVirtualServer`,
`deleteVirtualServer`, `updateDdnsSettings`, `updateNodeLed`, `updateRestartSchedule`,
`updateUsbStorageSettings`, `rebootRouter`, `logout`.

Connection: `selectRouter`, `attemptAuthentication`, `reconnectNow`, `_initialize`,
`_onRouterDiscovered`, `_reconnectCurrentRouter`, `_startAutoRefresh`, `_liveRefresh`,
`updateNetworkState`, `pauseLiveUpdates`.

### 3.4 Screens and widgets with direct router dependencies

| File | Direct calls |
|---|---|
| `lib/screens/router_settings_screens.dart` | 15 load/update operations (firewall, UPnP/DMZ, QoS, Fast NAT, VPN, port forwarding, DDNS, LED, restart schedule) |
| `lib/screens/settings_screen.dart` | `rebootRouter`, `saveWirelessNetworks`, `updateUsbStorageSettings`, `refreshWirelessSettings`, `pauseLiveUpdates` |
| `lib/screens/wifi_screen.dart` | `loadGuestWifiSettings`, `setWirelessNetworkEnabled`, `updateWirelessNetwork`, `saveWirelessNetworks`, `refreshWirelessSettings` |
| `lib/screens/pairing_screen.dart` | `attemptAuthentication` at `:145`, manual IP default `192.168.10.1` at `:21`, `:134`, port 25678 at `:273` |
| `lib/screens/discovery_screen.dart` | `reconnectNow` at `:79`, gateway `192.168.10.1` at `:40`, port 25678 at `:41` |
| `lib/screens/diagnostics_screen.dart` | `measureRouterResponse`, `updateNetworkState`, MQTT port probe `:37`, UDP check `:252` |
| `lib/screens/splash_screen.dart` | waits on `provider.isConnected` to choose Home vs Discovery |
| `lib/screens/statistics_screen.dart` | `measureRouterResponse` |
| `lib/screens/overview_tab.dart`, `devices_screen.dart`, `nodes_screen.dart`, `network_hub_screen.dart` | read-only projections of router state |
| `lib/widgets/home_widgets.dart`, `led_card.dart`, `home_sheets.dart`, `connection_banner.dart` | `updateNodeLed`, `refreshLeds`, `rebootRouter`, `logout`, `dismissPendingChange` |

## 4. Startup, resume, reconnect, refresh and recovery flows

### 4.1 Startup

```
main() -> MultiProvider
  RouterProvider() construct -> _initialize()
    -> authService.loadSavedPairings()
    -> discovery.startDiscovery()            (UDP 52011, listens forever)
  PiProvider(autoStart) -> _load() -> _start() (1 s scheduler)
discovery packet -> _onRouterDiscovered
  -> first router found is selected WITHOUT user action   :599
  -> selectRouter -> _mqtt.connect(meshId, ip, password)   :695
  -> authenticated -> _startAutoRefresh + refreshAll        :630
Splash: waits <=12 s for isConnected -> Home else Discovery
```

The app acquires router ownership before it has any idea whether Argon exists.

### 4.2 Resume

`didChangeAppLifecycleState(resumed)` (`:546-557`) calls `refreshAll()` if connected, or
restarts the reconnect loop if not. Every foreground transition is an ownership bid.

### 4.3 Reconnect

`reconnectDelays = [1, 2, 4, 8] s`, clamped at 8 s and retried indefinitely (`:93-98`,
`_scheduleReconnect` `:793`). Additional triggers: discovery seeing the router broadcast
again (`_onRouterDiscovered`), `reconnectNow()` from the discovery screen's connectivity
listener (`discovery_screen.dart:71-81`), and app resume. There is no cap and no jitter.

### 4.4 Background

Router polling pauses on `paused`/`hidden` (`:558-566`); the MQTT socket stays open. The
router releases management 60–80 s after activity stops, so backgrounding frees the
session for another phone by design.

### 4.5 Refresh

30 s full refresh (`_startAutoRefresh` `:769`) and 5 s live polling (`liveInterval =
Duration(seconds: 5)` `:157`), each live tick issuing four commands. While refused, one
`GetDevListInfo` every 4 ticks (~20 s, `:879-886`). `PiProvider._sync()` adds
`refreshWanSettings()` and `loadGuestWifiSettings()` every 5 minutes
(`pi_provider.dart:848-850`) — the Pi link currently *causes* direct router traffic.

### 4.6 Write and recovery

Writes read before writing, send full raw lists, and verify by read-back within
`verificationWindow = 90 s` (`:102`). `PendingChange` entries surface as
"unverified" rather than success. `ErrorCode 5` marks `managedElsewhere`, skips full
refreshes, and shows the "Another phone is managing the router" banner.

## 5. Bypass analysis

Direct router traffic can reach the router today through all of these. Each must be
closed in Phase 4.

1. **Automatic startup connection** — discovery + auto-select (`:599`) needs no user
   action.
2. **Resume reconnect** — every foreground transition bids for ownership.
3. **Infinite reconnect** — 8 s retry forever.
4. **Manual pairing screen** — a user can type `192.168.10.1` and authenticate directly
   (`pairing_screen.dart:21`, `:145`).
5. **Discovery screen** — probes 25678, calls `reconnectNow`, selects a discovered router.
6. **Diagnostics** — probes 25678 and opens UDP sockets; `measureRouterResponse` sends a
   live command.
7. **Pi sync** — triggers router reads every 5 minutes.
8. **BLE commissioning** — directly provisions a new or reset router.
9. **A stale APK** — a 1.9.x install keeps connecting and will out-compete the Pi within
   60–80 s. This cannot be prevented from the server side; it is why deployment order
   matters (§11).
10. **The separate Nokia Home app** — independent direct control plane for the Nokia
    beacons on the same LAN. Out of scope for the TaoTronics router, but it must be named
    in any "sole controller" claim.

There is **no** hidden path: no native MQTT, no background worker, no webview, no
third-party plugin that speaks to the router.

## 6. Target architecture

```
┌─ Phone app ────────────────────────────────────────────┐
│ screens/widgets  -> RouterProvider (presentation cache) │
│                  -> RouterGateway (single interface)    │
│                     └── PiRouterGateway                 │
└───────────────────────────┬─────────────────────────────┘
                            │ HTTPS / Tailscale, companion or operator token
┌───────────────────────────▼─────────────────────────────┐
│ Argon router agent (systemd, single instance)            │
│  lease holder · command queue · verification · SQLite    │
│  MQTT/TLS 25678, pinned TaoTronics CA, per-path timeouts │
└───────────────────────────┬─────────────────────────────┘
                            │ 192.168.10.0/24
                        TaoTronics
```

The Pi owns: connection, reconnection, retry, caching, command ordering, read-back
verification, staleness, certificate verdict, and the V1-only Wi-Fi verdict.

## 7. `RouterGateway` abstraction

Screens keep their current call sites. `RouterProvider` keeps its public API and becomes
a cache and notification layer over one gateway. This is the key to a low-churn
migration: no screen needs rewriting, because `SaveResult` semantics are preserved.

```dart
/// The only way the app reaches a router. One production implementation.
abstract interface class RouterGateway {
  /// Argon's view of its own router link. Never throws; emits on change.
  Stream<RouterLink> get link;

  /// Latest observation, with per-field timestamps and source.
  Future<RouterSnapshot> snapshot({Set<RouterField> fields = const {}});

  /// Queues a command; returns an accepted handle, not a result.
  Future<CommandHandle> execute(RouterCommand command);

  /// Poll/stream status until confirmed, failed or expired.
  Future<CommandStatus> awaitCommand(String commandId, {Duration timeout});
}

enum RouterLinkState {
  connected, reconnecting, unreachable, certRejected, refusedByPeer, unpaired,
}

final class RouterLink {
  final RouterLinkState state;
  final String? owner;          // 'argon' | null; the app never sets this
  final DateTime? since;
  final DateTime? lastObservedAt;
  final String? detail;
}

sealed class RouterCommand {
  const RouterCommand({required this.idempotencyKey, this.confirm = false});
  final String idempotencyKey;
  final bool confirm;          // required for destructive operations
}

final class SetLed extends RouterCommand { /* nodeSn, on */ }
final class SetWifiEnabled extends RouterCommand { /* index, enabled */ }
final class UpdateWifiNetwork extends RouterCommand { /* full raw list + index */ }
final class UpdateSetting extends RouterCommand { /* op enum, list payload */ }
final class RebootRouter extends RouterCommand { /* confirm must be true */ }
```

Production wiring:

```dart
class PiRouterGateway implements RouterGateway { /* pi_api + operator/companion tokens */ }
```

`DirectRouterGateway` must not exist. A test-only `FakeRouterGateway` implements the same
interface for widget tests.

Enforcement test (`test/architecture/no_direct_router_test.dart`):

- no file outside `lib/services/pi_api.dart` may reference `25678`, `52011`,
  `MqttServerClient`, `RawDatagramSocket`, or `Socket.connect`;
- `RouterGateway` has exactly one implementer in `lib/`;
- no `catch` block in `lib/` constructs a router client.

## 8. Argon API v2

Extends `docs/ARGON_API_V1.md`. Same envelope, no-store, bearer tokens, no redirects.
Reads use the companion token; every write requires the operator token plus a capability
flag. No raw path/payload proxy: operations are a closed enum validated server-side.

```
GET  /api/v1/router/link
     -> {state, owner, since, lastObservedAt, observations:{devicesAt, wifiAt, ...},
         caps:{write:true, reboot:false}, queueDepth, lastError}

GET  /api/v1/router/state?fields=summary,devices,nodes,wifi,wan,led,guest,usb
     -> normalized snapshot; every field carries its own observedAt;
        omitted fields stay absent (never zero-filled)

GET  /api/v1/router/state/history?from=&to=&resolution=

POST /api/v1/router/commands
     {"op":"setLed","args":{"nodeSn":"...","on":true},
      "idempotencyKey":"<uuid>","confirm":false,"deadlineSeconds":30}
     -> 202 {commandId, acceptedAt, state:"queued", expiresAt}
     -> 409 {error:"busy"}  when the queue owns a conflicting write
     -> 403 {error:"forbidden"}  operator token or capability missing
     -> 422 {error:"invalid", field:"..."}

GET  /api/v1/router/commands/{commandId}
     -> {state: queued|sent|verifying|confirmed|failed|rejected|expired,
         sentAt, confirmedAt, observed:{...}, error:null}

POST /api/v1/router/commands/{commandId}/cancel       (queued only)

GET  /api/v1/router/capabilities
     -> {writes:[op...], destructive:[op...], firmware, caExpiresAt}

POST /api/v1/router/release        (operator only) -> 202 {releasedAt}
     Explicitly yields the lease for break-glass or maintenance.
```

Deprecations:

- `POST /api/v1/router/snapshot` — keep accepting during migration, label
  `phone-supplied`, never let it overwrite an Argon-observed value. Remove in Phase 4.
- `POST /api/v1/router/control` — replace the `409` stub with the command endpoint.
- Every `/api/v1/gateway` `router` field gains `source: "argon"` and per-field
  `observedAt`.

Semantics the Pi must implement (all learned from this app's incidents):

- one outstanding request per path, 15 s late-reply guard;
- persisted "V1-only wireless" verdict per mesh ID — a repeated `GetWirelessInfoListV2`
  probe stalls the router for ~10 s for every client;
- 8 s telemetry timeout, not 4 s;
- 5 s live cadence at most; the firmware serves one command at a time;
- `ErrorCode 5` means another manager holds the router: back off, do not retry hard;
- certificate rejection is terminal, never an auth retry;
- write = read → full raw list → read-back → confirmed/pending/failed.

## 9. Code to remove or refactor

**Delete** (2 159 lines of router-specific service code, plus 1 048 lines of screens and their tests):

- `lib/services/mqtt_service.dart`, `mqtt_transport.dart`, `router_discovery.dart`,
  `router_certificate_verifier.dart`, `auth_pairing_service.dart`,
  `credential_store.dart`, `network_probe.dart`, `pi_snapshot.dart`
- `lib/screens/pairing_screen.dart` (531) — replaced by Argon pairing in Network Hub
- `lib/screens/discovery_screen.dart` (517) — replace with a Network Hub connection
  screen; do not keep router discovery
- `pubspec.yaml`: drop `mqtt_client: ^10.2.1` — the only reason the app can speak to a
  router at all. `dart:io` `Socket`/`RawDatagramSocket` use disappears with
  `router_discovery.dart` and `network_probe.dart`.
- `test/services/mqtt_service_test.dart`, `test/services/auth_pairing_service_test.dart`,
  `test/services/router_certificate_verifier_test.dart`, `test/services/network_probe_test.dart`,
  and the direct-connection half of `test/providers/router_provider_test.dart`

**Refactor**:

- `lib/providers/router_provider.dart` (2 038) — keep the public API and `SaveResult`;
  replace every body with gateway delegation. Router connection state is derived from
  `RouterGateway.link`, not owned.
- `lib/providers/pi_provider.dart` — add `routerLink`, `routerSnapshot`, `execute`;
  delete `_sync()`'s snapshot upload and the `refreshWanSettings` /
  `loadGuestWifiSettings` calls at `:848-850`.
- `lib/main.dart` — Pi provider first; `RouterProvider` depends on the gateway, not on
  `MqttService`.
- `lib/screens/splash_screen.dart` — gate on the Pi link, not `provider.isConnected`.
- `lib/screens/diagnostics_screen.dart` — report Argon's link metrics; remove the 25678
  probe and the UDP socket check.
- `lib/screens/setup_wizard_screen.dart` + `ble_provisioning_service.dart` — either
  delegate commissioning to Argon or mark it explicit break-glass.
- `README.md` — the feature list and "Router discovery" claim must match reality.

**Unchanged by design**: the 17 screens/widgets in §3.4, because the provider API is
preserved. Only their failure and empty states change to "via Network Hub".

## 10. Startup and reconnect logic to disable

| Location | Action |
|---|---|
| `router_provider.dart:537-542` `_initialize` → `startDiscovery()` | remove; no discovery |
| `:570-616` `_onRouterDiscovered` auto-select and discovery-driven reconnect | remove |
| `:599` `selectRouter(_routers.first)` | remove |
| `:546-566` resume → `refreshAll` / `_scheduleReconnect` | replace with a Pi-link refresh only |
| `:683-721` `selectRouter`, `:723-760` `attemptAuthentication` | delete; Argon pairing replaces |
| `:793-830` `_scheduleReconnect` / `_reconnectCurrentRouter` | delete |
| `:769-781` `_startAutoRefresh` (30 s) | delete; Pi polls |
| `:879-890` `_liveRefresh` (5 s) + refused probe | delete; Pi probes |
| `:1952` `logout()` | becomes "forget Argon pairing", not a router disconnect |
| `discovery_screen.dart:71-81` connectivity → `reconnectNow` | delete with the screen |
| `diagnostics_screen.dart:249-258` UDP bind, `:230-247` port probe | delete |
| `pi_provider.dart:848-850` router reads inside `_sync` | delete |
| `mqtt_service.dart` `connect`, `disconnect`, `connectionStream` | deleted with the file |

## 11. Migration and deployment risks

1. **Topology is not ready (§2.1).** Without a Pi interface on `192.168.10.0/24`, Phases
   2, 3 and 5 cannot succeed. Decide A/B/C first.
2. **Old APKs will fight the Pi.** A 1.9.x install auto-connects on launch and on resume
   and will take management within 60–80 s of Pi silence. Every phone must be updated
   *before* the Pi is allowed to hold the lease, or the Pi will be starved and the two
   will oscillate.
3. **The Pi becomes a single point of failure.** Fail-closed means a dead Pi means no
   router control. The recovery path must be explicit: either a documented
   `systemctl stop argon-router` plus a break-glass handshake, or an app override that
   requires a typed confirmation and is logged. Decide before Phase 4, not after.
4. **Router firmware quirks are inherited, not solved.** The Pi must reproduce the
   V1-only verdict, the 8 s telemetry timeout, the 5 s cadence, and the one-command queue,
   or it reintroduces the ~10 s stall that once froze every client.
5. **Credential migration.** Router passwords currently live in the phone Keystore
   (`credential_store.dart`). They must be enrolled on Argon and then **deleted from the
   phone**; leaving them is a standing invitation to reconnect.
6. **CA expiry 2030-05-18** (`ROUTER_PROTOCOL_HANDOFF.md §4`). Argon needs the pinned CA,
   an expiry check surfaced in `/api/v1/router/link`, and a rotation plan.
7. **Double writers of state.** If `POST /api/v1/router/snapshot` stays active while
   Argon observes directly, two observations compete. Accept it only with an explicit
   precedence rule (Argon wins) and a removal date.
8. **Rollback.** Keep the Phase 2 app build and the current APK signing key. Every app
   phase must be revertible to "direct control" by installing the previous APK — which
   is only possible while the direct code exists, so Phase 4 is the point of no return.
9. **Test coverage shift.** 82 of the 194 test declarations under `test/` sit in files that
   exercise direct router paths (`router_provider_test`, `mqtt_service_test`,
   `wifi_controls_test`, `settings_safety_test`, `screens_test`, `wifi_screen_test`,
   `home_led_test`, `auth_pairing_service_test`, `network_probe_test`,
   `router_certificate_verifier_test`). They must be re-pointed at a fake gateway, not
   deleted, or write-verification coverage silently disappears.

## 12. Deployment sequencing

1. Owner approves topology option A; cable and verify `192.168.10.1:25678` from Argon.
2. Ship **app 1.10.0 Phase 1** (contention only, no loss of function) to every phone.
3. Deploy the Argon router agent read-only (Phase 2). Watch it take the lease; the phones
   should show "managed via Network Hub" rather than "another phone".
4. Ship **app 1.11.0** (Phase 2 read path). Router screens read Argon's snapshot; writes
   still direct and still gated.
5. Ship **app 1.12.0** (Phase 3 write path) after every write operation is confirmed by
   Argon read-back in staging.
6. Ship **app 1.13.0** (Phase 4 deletion). Verify the APK contains no MQTT library and no
   router socket symbols.
7. Run Phase 5 validation and record it in `docs/`.

Do not reorder 2 and 4: turning on the Pi before all phones yield guarantees an ownership
fight, and the router resolves it by starving the Pi.

## 13. Phased plan

### Phase 1 — Stabilization: stop ownership contention (app only, shippable now)

**Status: implemented 2026-10-22** (see §13.1 for the change record).

Goal: one phone competes less, and every direct path becomes gated by a single policy
seam so Phase 4 is a policy flip rather than a refactor. No functionality is removed.

- Add `RouterAccessPolicy` (one class, one decision point). Phase 1 rule: direct access is
  permitted only while Argon does not advertise `owner: "argon"`. All connects, polls,
  probes, and discovery start/stop go through it.
- Add `RouterGateway` interface with `DirectRouterGateway` (temporary) as the only
  implementer. `RouterProvider` delegates internally; screens untouched.
- Reconnect: cap at 60 s, add ±20 % jitter, stop on repeated `ErrorCode 5`.
- Remove resume-driven reconnect and discovery-driven reconnect; keep a single
  foreground retry.
- Reduce the refused probe from 20 s to 45 s.
- Stop `PiProvider._sync` from issuing `refreshWanSettings` / `loadGuestWifiSettings`
  every 5 minutes; re-source those fields from the existing 30 s refresh.
- Show "Router control is provided by Network Hub" whenever Argon reports ownership.

Exit criteria: two phones plus a restart storm produce ≤ 1 management claimant at a time;
no test regressions; `flutter analyze` clean.

#### 13.1 Phase 1 change record (2026-10-22)

New files:

- `lib/services/router_access_policy.dart` — `directControlEnabled`, `preferPiController`,
  `blockDirectOwnership`, `diagnosticsOnly`, with derived `mayDiscover`, `mayConnect`,
  `mayAuthenticate`, `mayProbe`, `mayRefresh`, `maySendCommands`, `mayWrite`,
  `mayAutoReconnect`, `isReadOnly`.
- `lib/services/router_gateway.dart` — `RouterGateway` interface (connection lifecycle,
  streams, the full command surface) and `DirectRouterGateway`, which wraps `MqttService`
  and refuses connect/read/write when the policy denies them. `RouterProvider` now holds
  `RouterGateway`, not `MqttService`; `MqttService? mqtt` is still accepted and wrapped, so
  behaviour is unchanged.
- `test/providers/router_access_policy_test.dart` — policy matrix, gateway enforcement,
  injected-gateway wiring, Pi ownership parsing.

Changed:

- `RouterProvider`: every connect, discovery start, authentication, reconnect, refresh, read
  and write consults `accessPolicy`; discovery beacons no longer reconnect; resume no
  longer reconnects; backoff is `[1,2,4,8,15,30,60] s` with ±20 % jitter and a six-attempt
  cap; the refused probe moved from 20 s to 45 s. `applyPiOwnership()` stops timers,
  unbinds discovery and writes an event; releasing it restores them.
- `PiProvider`: `_sync()` no longer calls `refreshWanSettings()` or
  `loadGuestWifiSettings()`; snapshots use cached data only. `reportsRouterOwnership()`
  accepts **only an explicit ownership field** (`router.owner`, `router.control`,
  `monitoring.owner`, `monitoring.control` equal to `argon`) and pushes that claim into
  `RouterProvider` after every gateway poll.

  The first build of this phase inferred ownership from
  `router.monitoring.state == "connected"`. On the live system that state means "router
  device monitoring connected" and is fed by a Dell LAN observer
  (`source: lan-observer:dell`). The detector fired, the app went read-only, and because
  polling was suppressed it never noticed when router access freed up: it sat on "Waiting
  for router access" indefinitely. Deployed and caught on device 2026-10-22; the inference
  was removed. Argon must publish `router.owner = "argon"` before this path becomes active
  (Phase 2), and `RouterProvider.applyPiOwnership()` now closes any established session
  rather than lingering.
- `ConnectionStatusBanners`: shows "Router control provided by Network Hub" and suppresses
  the misleading "not connected" banner while Argon owns the router.
- `diagnostics_screen` / `discovery_screen`: port probes and the router round-trip are
  skipped while the policy forbids them.

Known consequence, accepted for Phase 1: because the sync no longer refreshes them, the
snapshot's `wan` and `guest` blocks are null whenever no settings screen has read them
within their freshness window. Argon already treats null as unavailable. Phase 2 replaces
the upload entirely.

Verified: `flutter analyze` clean; `flutter test` 245/245 pass (18 new or rewritten cases).
Not verified: behaviour on a device, and the Pi-side ownership claim (Argon does not report
`monitoring.state = connected` today, so the blocked path has only been exercised by tests).

### Phase 2 — Pi read path

- Argon agent: MQTT client, pinned CA, lease (`flock`), command queue, SQLite cache,
  `/api/v1/router/link`, `/api/v1/router/state`, `/api/v1/router/capabilities`.
- App: `PiRouterGateway` read methods; router screens read Argon state.
- `/api/v1/gateway` router fields marked `source: argon`.
- Direct reads still exist but are policy-gated and log when used.

Exit criteria: 24 h with Argon holding the lease, zero `ErrorCode 5` from Argon, phone
screens rendering Argon `observedAt` timestamps; kill the Pi agent and confirm the app
reports unknown, not zero, and makes no router packets (capture proof).

### Phase 3 — Pi write path

- `/api/v1/router/commands` with the allowlist, idempotency, read-back verification,
  `confirmed|pending|failed`, and operator-token gating.
- App writes routed through the gateway; `PendingChange` semantics preserved from
  `router_provider.dart:1661-1782`.
- Destructive operations (WAN, LAN, reboot) require `confirm: true` and are disabled in
  `/capabilities` until the operator enables them.

Exit criteria: every write in §3.3 exercised against the real router through Argon, with
read-back evidence; a deliberately interrupted write reports `pending`, never success.

### Phase 4 — Remove direct router access

- Delete §9 files; remove router credentials from the phone; remove discovery, pairing
  screen, and manual IP entry.
- Retire `POST /api/v1/router/snapshot`.
- Add the architecture test; make it a required CI job.
- App fails closed: Argon unreachable ⇒ router screens show "unavailable via Network Hub".

Exit criteria: `grep -r "25678\|52011\|MqttServerClient\|RawDatagramSocket" lib/` returns
only `pi_api.dart` (no matches); APK dependency tree has no MQTT package; every router
screen reachable with the Pi only.

### Phase 5 — Prove the Pi is the only controller

- Run the app through startup, resume, background, network change, router reboot, and Pi
  restart; capture traffic at the Pi and from the phone.
- Retain one old APK on a test phone and confirm Argon reclaims the router within ≤ 80 s
  and the old app shows the management banner.
- 72 h soak: Argon only; assert zero unexplained MQTT logins from phone IPs in Argon's
  `conntrack` / router session logs.
- Record results in `docs/pi-integration-validation/` with the same rigour as the 1.9
  validation bundle.

## 14. Open decisions for the owner

1. Topology A, B or C (§2.1). Nothing in Phases 2–5 proceeds without this.
2. Break-glass policy when Argon is dead (§11.3).
3. Whether BLE commissioning of a *new* router remains in the app (it is inherently
   direct) or becomes an Argon operation.
4. Whether the Nokia Home app's direct control plane is in scope for "sole controller".
5. Retention of `POST /api/v1/router/snapshot` during migration, and its removal date.

## 15. What this plan does not claim

No code has been changed by this document. No test suite has been run against it. The
topology finding is from recorded addresses in `docs/`, not from a live probe; confirm it
from Argon before committing to a phase. The Argon agent does not exist yet — Phases 2–3
are new work in the Argon repository, not in this one.
