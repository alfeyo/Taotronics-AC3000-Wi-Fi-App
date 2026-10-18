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

MQTT login succeeds for every phone. The refusal is at the command level, and it is not tied to a client ID, because two different OnePlus IDs were both refused while the Fold4 was served. Proven so far: **the router serves management reads to one phone at a time**. Not yet proven: the selection rule (most recent connection, most recent write, source IP, or first client after boot). `ErrorCode 5` does not appear in the original app or our protocol notes.

Required controlled test (needs the Fold4 on USB as well):
1. Both apps running, then stop the Fold4 app. Does the OnePlus receive data within one refresh?
2. Start the Fold4 again. Does the OnePlus go back to `ErrorCode 5`, or keep its access?
3. Repeat in the opposite order, and once after a Wi-Fi write from each phone.

Handling (planned once the rule is known): treat `ErrorCode 5` as "another phone is managing this router". Show that state instead of "0 devices", stop polling, and retry slowly, rather than competing in a way that knocks the other phone off. Not implemented yet, because the rule decides whether retrying can take the session over.

## 4. Related observation

At about 11:40 router index 1 was renamed from `Game labs` to `Nokia Wifi` from a phone (not by this investigation). Six BSSIDs now broadcast `Nokia Wifi`: both networks on all three radios.
