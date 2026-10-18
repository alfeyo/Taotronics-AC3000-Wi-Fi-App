# Multi-device connection review (TT Router on two phones)

Investigated 2026-10-18 on the Galaxy Z Fold4 (paired, app 1.6.0/1.6.1) and the OnePlus 8T (KB2003, Android 14; release `com.ttrouter.tt_router_flutter` and debug `com.ttrouter.tt_router_flutter.dev`) against TaoTronics ND001 `5702H5035a0eU6b9` at 192.168.10.1.

## 1. Client identity: not the cause (proven)

| Item | Finding | Evidence |
|---|---|---|
| MQTT client ID | `<appId>`: 32 random hex characters per install, persisted in SharedPreferences (`mqtt_app_id`) | `MqttService._loadAppId` |
| Observed IDs | Fold4 `47de…`, OnePlus release `ba57…`, OnePlus .dev `1dd3…` then `2b1e…` after reinstall | device logs |
| Username / password | mesh ID / `md5("dazoo"+meshId)` or the paired custom password; same for every phone by design | `ROUTER_PROTOCOL_HANDOFF.md` §5 |
| Subscriptions | `<appId>/+` only; replies are addressed to the requesting app's own topic | §3 and logs |
| Certificate | Router leaf verified against the pinned AIMMIT CA on every phone | `MqttTransport` logs |
| Clean session | Yes | `mqtt_transport.dart` |

No two installs share an ID, so MQTT session takeover by duplicate client ID cannot occur. Regression test: `two app instances keep separate client identities and replies` (`test/services/mqtt_service_test.dart`).

## 2. Cause A: repeated V2 probes stalled the router for every phone (fixed in 1.6.1)

The router processes commands one at a time, and an unanswered `GetWirelessInfoListV2` blocks its queue for about 10 s. The app was meant to try V2 once per router, but it only recorded "V2 unsupported" when the **V1 fallback also succeeded**. Under load the V1 read queued behind the stall and timed out, so the router was never marked and **V2 was re-sent on every 30 s full refresh**. Each probe stalled the router for all connected phones.

Measured with the debug build (`MqttService: <path> replied in N ms`, single client, about 1.5 min):

| Command | n | avg | max |
|---|---|---|---|
| GetDevListInfo | 12 | 947 ms | 5405 ms |
| GetSystemState | 3 | 3607 ms | 5395 ms |
| GetSysConnectInfo / GetNodeRateInfo / GetWanRateInfo | 9 each | ~860 ms | ~3990 ms |
| V2 probes in that session | 3 | — | each followed by a telemetry-timeout batch |

The other client on the same router (the OnePlus release app) logged telemetry timeouts in the same windows.

Fix (`lib/services/mqtt_service.dart`):
- **V2 verdict:** a V2 request with **no reply** while still connected to the same router marks it V1-only immediately, before the V1 read. An error reply still counts as supported. The verdict is persisted per mesh ID (`mqtt_wireless_v1_only`).
- **Timeouts:** telemetry timeout raised from 4 s to 8 s, because measured round trips reach 4–5 s. The live cycle guard went from 5 s to 10 s.

After installing 1.6.1+10 on the OnePlus:
- **First run:** 75 s, one V2 probe, recorded at once ("does not answer V2 wireless; using V1"), 0 telemetry timeouts.
- **After restart:** 50 s, **0 V2 probes, 0 timeouts**.

Regression tests: V2 is recorded even when V1 also times out; the verdict survives a new session; an error reply doesn't mark the router; telemetry waits for a 4.8 s reply.

## 3. Cause B: the router refuses all but one phone (`ErrorCode 5`), a genuine router limitation

1.6.1 logs router error replies, sanitized to path and code only. At 12:00–12:02:
- **OnePlus release** (`ba57…`): every read answered `ErrorCode 5` (`GetDevListInfo`, `GetExistNode`, `GetSysConnectInfo`, `GetNodeRateInfo`, `GetLedList`, `GetMWanInfo`, `GetSystemState`, …). The app showed "0 devices, Updated never".
- **OnePlus .dev** (`2b1e…`): also 0 devices. It had received 19–20 devices from the same router at 11:17–11:41.
- **Fold4 at the same moment:** served normally. Argon received its phone snapshot (companion `707531d0…`) 4 s old with 20 clients.

MQTT login succeeds for every phone, and the refusal is at the command level.

### Controlled test (both phones on USB, 12:05–12:10)

| Step | Action | Result |
|---|---|---|
| T0 | Both apps in the foreground | Fold4 served (Argon snapshot 13 s old, 20 devices). OnePlus refused (32 × `ErrorCode 5`, "0 devices") |
| T1 | Force-stop the Fold4 app (data kept) | OnePlus refused until **12:06:26**, about 55–60 s later, then served ("Online", 20 devices) |
| T2 | Restart the Fold4 app | **Fold4 refused** (0 devices, Argon sync stopped). OnePlus keeps access with 0 code-5 replies, so a newcomer **cannot take over** |
| T3 | OnePlus app to the background (MQTT still connected, polling paused) | Fold4 served again 45–85 s later |
| T4 | OnePlus back to the foreground | OnePlus refused (38 × `ErrorCode 5`) while the Fold4 keeps access |

**Router rule (proven):** the TaoTronics serves management requests, reads and writes alike, to **one active phone at a time**. Every request from other phones gets `ErrorCode 5`. Access moves to a waiting phone about **60–80 s after the holder stops sending requests** (app closed or backgrounded). It follows activity, not the MQTT connection, and a refused phone cannot take it by retrying.

### Handling in 1.6.2+11

- `MqttService.managedElsewhere`: set by any `ErrorCode 5` reply, cleared by the next `ErrorCode 0` reply or on disconnect. The log records state changes only.
- `RouterProvider`: while refused, full refreshes are skipped and live polling sends **one light `GetDevListInfo` every 7 ticks (~21 s)**. When access returns it runs a full refresh at once. MQTT stays connected and pairing is untouched.
- All router screens show the banner **"Another phone is managing the router"**, explaining that access arrives about a minute after the other phone closes or backgrounds TT Router. Last-known values remain on screen, marked as possibly out of date.
- Tests: `ErrorCode 5 marks the router as managed by another phone` and `another phone managing the router: back off, then recover` (≤ 4 probes per minute, no other commands, full refresh on recovery).

### Physical validation with 1.6.2+11 on both phones (12:15–12:19)

- Fold4 started first: served, with V2 probed **once** and recorded. OnePlus started next: refusal detected within 4 s and the banner shown.
- Fold4 backgrounded at 12:16:16. OnePlus logged "management available" at **12:17:32** (76 s): banner cleared, "Online, 20 devices".
- Fold4 foregrounded again: banner shown, **pairing intact**, last values (20 devices, Nokia Wifi, LED on) kept.
- OnePlus (holder): router LED switched off and back on, each confirmed by the app's read-back.
- Argon: eth0 uplink, VPN (GB egress), Tailscale, `/devices` and `/network` unaffected.

## 4. Related observation

At about 11:40 router index 1 was renamed from `Game labs` to `Nokia Wifi` from a phone (not by this investigation). Six BSSIDs now broadcast `Nokia Wifi`: both networks on all three radios.
