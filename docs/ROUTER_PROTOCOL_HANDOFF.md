# TaoTronics AC3000 — Local Router Protocol Handoff

This document describes how the TT Router app talks to a TaoTronics AC3000 mesh
router over the local network, so the same control can be built from another
client, such as a Raspberry Pi service. It reflects app 1.3.0 and observations
from one live router (October 2026).

**Confidence markers**

| Marker | Meaning |
|---|---|
| ✅ Verified | Observed on the live router, or exercised end to end by the app |
| 🧪 Tested | Covered by automated tests against a fake broker, not exercised live |
| ⚠️ Inferred | Taken from the original APK's payloads or field names; not confirmed live |

All identifiers below are placeholders: `<meshId>`, `<appId>`, `<router-ip>`,
`<password>`. No real credentials, serials or addresses appear in this file.

Source of truth in the codebase:

| Area | File |
|---|---|
| Discovery | `lib/services/router_discovery.dart` |
| MQTT envelope, queueing, commands | `lib/services/mqtt_service.dart` |
| TLS transport | `lib/services/mqtt_transport.dart` |
| Certificate check | `lib/services/router_certificate_verifier.dart` |
| Pairing and credentials | `lib/services/auth_pairing_service.dart`, `lib/services/credential_store.dart` |
| Polling, reconnection, verification | `lib/providers/router_provider.dart` |
| BLE provisioning (new or reset routers) | `android/app/src/main/kotlin/.../MainActivity.kt` |

---

## 1. Discovery (UDP) ✅

- The router broadcasts UDP datagrams on **port 52011**. The client binds
  `0.0.0.0:52011` with broadcast enabled and listens; it sends nothing.
- Packet layout: an optional envelope that starts with the marker
  `AA BB CC DD`. The TLV body starts **12 bytes after the start of the
  marker**. Some firmware sends the TLV body without an envelope, so the
  client falls back to parsing from byte 0.
- The TLV body is a sequence of `type (1 byte) · length (1 byte) · value`.

| Tag | Meaning | Decoding |
|---|---|---|
| `0C` | Mesh ID | ASCII, NUL bytes dropped |
| `04` | Router IPv4 | 4 bytes, **little-endian** (reverse byte order) |
| `06` | Status | Raw hex; meaning unknown ⚠️ |
| `13` | VLAN capable | Presence only ⚠️ |

- A packet counts as a router only if tag `0C` is present. If tag `04` is
  absent, use the datagram's source address.
- Pi note: other software that binds 52011, such as a second instance, stops
  discovery from working. Use `SO_REUSEADDR`, or run one listener only.

## 2. MQTT over TLS ✅

| Setting | Value |
|---|---|
| Broker | The router itself: `<router-ip>`, **TCP 25678**, TLS |
| MQTT library used | `mqtt_client` (MQTT 3.1.1) |
| Client ID | `<appId>`: 32 hex characters, random per install, persisted |
| Username | `<meshId>` |
| Password | See §5 |
| Keep-alive | 30 s |
| Connect timeout | 10 s |
| QoS | 0 (at most once) for publishes |
| Clean session | Yes (`startClean`) |

TCP 80/443 are refused, because there is no web UI. Reachability checks must
use 25678 ✅.

## 3. Topics ✅

| Direction | Topic |
|---|---|
| Request (client → router) | `<meshId>/<appId><path>`, e.g. `<meshId>/<appId>/GetExistNode` |
| Reply (router → client) | `<appId><path>`, e.g. `<appId>/GetExistNode` |
| Subscription | `<appId>/+` (subscribe once after connecting) |

`<path>` always starts with `/`, so `<appId>` and the path are joined with no
separator.

## 4. Certificates ✅

- The router presents a leaf certificate signed by a **TaoTronics local CA**.
  The CA certificate is public and was extracted from the original Android
  app. It is embedded as `_pinnedAuthorityPem` in `mqtt_service.dart`. This
  document deliberately does not reproduce it.
- The leaf's subject does not match the router's IP, so ordinary hostname
  verification always fails. Do **not** disable verification. Instead, verify
  as the app does (`RouterCertificateVerifier`):
  1. The leaf's issuer DN equals the pinned CA's subject DN (DER bytes).
  2. Both signature-algorithm fields are `sha256WithRSAEncryption`.
  3. The PKCS#1 v1.5 SHA-256 signature over `tbsCertificate` verifies with
     the CA's RSA public key.
  4. The current time falls within the leaf's validity period.
- The CA is valid until **2030-05-18**. After that date, a strict validity
  check of the CA would fail. The app checks only the leaf's validity
  period ⚠️.
- Python sketch: load the CA with `cryptography`, accept the TLS handshake
  without hostname checks (`check_hostname=False`, `CERT_NONE`), and then
  manually check `ssl_sock.getpeercert(binary_form=True)` against the steps
  above **before** sending CONNECT credentials. Alternatively, pass a custom
  `SSLContext` with the CA loaded and `check_hostname=False`. That works only
  if the leaf chains cleanly to it; test this.

## 5. Pairing and credentials ✅

- **Default router password:** `md5("dazoo" + <meshId>)` as lowercase hex.
  This works on a router that still uses its factory MQTT credentials.
- The app also accepts a user-supplied password per router. The password is
  stored per mesh ID in Android Keystore-backed secure storage, with a
  preference-file fallback only when the Keystore write fails.
- The app keeps no cloud account. Pairing is local: once MQTT CONNECT is
  accepted with the username and password above, the client is paired.
- On a Pi, store the password with root-only file permissions (0600) or use
  a secret store. Never log it.
- New or reset routers are provisioned over BLE, not MQTT. The UUIDs and the
  message format are in `MainActivity.kt` (`BleResponseParser`). This is out
  of scope for a Pi controller of an already-installed mesh.

## 6. Request envelope, correlation and timeouts ✅

Every request publishes this JSON:

```json
{
  "AppId": "<appId>",
  "Timeout": 0,
  "ErrorCode": 0,
  "Data": <command-specific object or array>,
  "Timestamp": 1792240000
}
```

- `Timestamp` is in epoch **seconds**. `Timeout` is a router-side hint in
  seconds; the app sends 2 for telemetry and 0 otherwise ⚠️.
- **Replies carry no request ID.** A reply is matched to its request only by
  its topic (`<appId><path>`). Consequences:
  - Allow only **one outstanding request per path**. The app chains requests
    to the same path in a queue.
  - Identical concurrent requests (same path and payload) share one network
    request.
  - If a **write** times out, its reply can still arrive late and would then
    be mistaken for the reply to the next write on that path. After a write
    timeout, the app waits up to **15 s** for that late reply (and discards
    it) before sending the next write on the same path.
- Success means `ErrorCode == 0`. Any other value, or no reply, counts as a
  failure.
- Client timeouts used by the app:

| Command class | Timeout |
|---|---|
| Default | 10 s |
| Telemetry (`GetSysConnectInfo`, `GetNodeRateInfo`, `GetWanRateInfo`) | 4 s |
| `SetWirelessInfoList` | 8 s |
| WAN, LAN, guest and VPN writes | 15 s |

## 7. Command reference

Status: ✅ verified live · 🧪 tested with a fake broker only · ⚠️ payload shape inferred.

### Read commands

| Path | Request `Data` (shape) | Notes | Status |
|---|---|---|---|
| `/GetExistNode` | `[{NodeSn,OnLine,NickName,ClientNum,Role,Uptime,Model,LocalConn,AddTime}]` with blank or zero values | Mesh nodes. `Role` `mpp` is the main router. `Uptime` is in seconds. No firmware version is reported. | ✅ |
| `/GetDevListInfo` | `[{GroupId:"",GroupName:"",GroupType:0,Devices:[{}]}]` | Clients: `HostName`, `NickName`, `Mac`, `Ip`, `AliveOnline`, `UpRate`, `DownRate`, `ClientType`, `ConnTime` (epoch s). There are no byte counters. | ✅ |
| `/GetSysConnectInfo` | `{Internet,OnlineNodeCount,TotalNodeCount,OnlineDev,OnlineGuestDev,NetworkQuality}` all 0 | Internet: 1 means online | ✅ |
| `/GetWanRateInfo` | `[{UpRate:0,DownRate:0}]` | WAN throughput | ✅ (unit ⚠️: treated as bytes/s) |
| `/GetNodeRateInfo` | `[{MeshNodeName:"",Rate:0}]` | Per-node rate | ✅ |
| `/GetWirelessInfoList` (V1) | `[{Ssid,Encrypt,Password,Vlanid,VlanEnable,SsidIsolate,StaIsolate,Index,Create}]` | Wi-Fi networks | ✅ |
| `/GetWirelessInfoListV2` | The V1 fields plus `Disable,ConfStatus,NodeSn` | **Never answered** on the tested firmware; see §8 | ✅ (unanswered) |
| `/GetLedList` | `[{NodeSn:"",NickName:"",Led:0}]` | `Led` 1 means on | ✅ |
| `/GetMWanInfo` | Two template entries (`WanProto, WanIp, WanMask, WanGateway, ManualDns, WanDns, WanDnsbak, Pppoe*, Vlan*`) | WAN configuration | ✅ read |
| `/GetLanInfoV3`, fallback `/GetLanInfo` | `[{LanMode,LanIp,…},{DhcpDisabled,DhcpStartAddr,DhcpEndAddr},{VlanEnable,Vlanid}]` (V1 takes the first two) | LAN and DHCP | 🧪 |
| `/GetGuestInfo` | Template list | Guest Wi-Fi | ✅ read |
| `/GetSystemState` | `{}` | Returns an empty list on the tested firmware | ✅ |
| `/GetFirewallInfo`, `/GetUpnpDmz`, `/GetQosInfo`, `/GetFastNatInfo`, `/GetVpnInfo`, `/GetVpnStatus`, `/GetVirServerList`, `/GetDdnsInfo`, `/GetDdnsStatus`, `/GetSystemRestartInfo`, `/GetPrivateStorageV2`, `/GetDiskInfo`, `/GetVisitAddress` | See `mqtt_service.dart` | Advanced settings | ⚠️ / 🧪 |
| `/GetSumOfNetworkFlowDaily`, `/GetSumOfNetworkFlowMonthly` | `{}` | Usage totals. Not relied on; the app shows no daily or monthly totals. | ⚠️ |

### Write commands

| Path | `Data` | Notes | Status |
|---|---|---|---|
| `/SetNodeLed` | `{NodeSn:"<sn>",Led:0\|1}` | Read back with `GetLedList` | ✅ (on and off, live) |
| `/SetWirelessInfoList` | Full list of networks: each entry is the **raw entry as read** with edits merged | See §8 | ✅ (band off/on recovery once in stage 1); 🧪 otherwise |
| `/SetGuestInfo` | `[guest]` | | 🧪 |
| `/SetMWanInfo` | WAN list as read, with edits | Disruptive | 🧪 (never sent live) |
| `/SetLanInfoV3` | LAN list | Disruptive | 🧪 (never sent live) |
| `/SetFirewallInfo` | `{Enable:0\|1}` | | 🧪 |
| `/SetUpnpDmz`, `/SetQosInfo`, `/SetFastNatInfo`, `/SetVpnInfo`, `/AddVirServerList`, `/SetVirServerList`, `/DelVirServerList`, `/SetDdnsInfo`, `/SetPrivateStorageV2`, `/SetSystemRestartInfo` | See `mqtt_service.dart` | | 🧪 / ⚠️ |
| `/SetSystemRestartNow` | `[{SysRebootNow:1}]` | Reboots all nodes | ⚠️ (never sent live) |

No local commands were found for backup or restore, factory reset, or
parental controls. The app does not send any.

## 8. Wi-Fi V1 and V2 ✅

- Try V2 once per router. If V2 gets **no reply** while V1 succeeds, mark
  the router as V1-only for the session. An unanswered V2 request blocks the
  router's serial command queue for about 10 s.
- Each `Index` is a separate **dual-band** network (verified 2026-10-18 by radio
  scan: index 0 and index 1 each broadcast on 2.4 GHz and 5 GHz). The original
  app labelled index 0 "2.4 GHz" and index 1 "5 GHz"; that inference was wrong.
- `Encrypt`: 0 none, 1 WEP, 2 WPA-PSK, 3 WPA2-PSK, 4 WPA/WPA2, 5 WPA3 ⚠️.
- Enable or disable: V1 uses `Create` (1 means broadcasting). V2 also has
  `Disable` ⚠️.
- Writing: always send **every** network the router reported, each as the
  raw object read, with only the changed fields replaced. Partial lists or
  re-typed objects risk dropping networks or resetting fields.
- After a write, the router restarts its radios. Clients drop for several
  seconds and replies may be slow. The app polls `GetWirelessInfoList` for up
  to **90 s** and reports *confirmed*, *pending verification* (fields
  missing), or *failed* (the router still reports the old values).

## 9. LED control ✅

1. Read `GetLedList` and pick the entry whose `NodeSn` matches the node with
   `Role == "mpp"`. If roles are unknown, use the first entry.
2. Send `SetNodeLed {NodeSn, Led}`.
3. On `ErrorCode 0`, read `GetLedList` again. Report success **only** if
   the read-back value equals the request. If the router does not answer,
   keep the previous state as "pending"; if the router still reports the old
   value, report failure.
4. Allow one LED command at a time.

## 10. Devices, mesh, WAN, LAN and telemetry

- **Polling cadence used by the app:** every 3 s it sends `GetDevListInfo`
  and the three telemetry reads. A full refresh (nodes, Wi-Fi, LEDs, guest)
  runs every 30 s. Polling pauses while a settings screen is writing.
- **Telemetry stalls ✅:** about every 12–24 s, the router stops answering
  for 4–5 s. After 3 consecutive missed telemetry batches, the app backs off
  telemetry; the full refresh keeps retrying. Data counts as stale after
  20 s without an update.
- **Device link type ⚠️:** `ClientType` 0 was observed on an Ethernet-only
  device and 2 on Wi-Fi clients. Treat this as a hint, not a guarantee.
- **WAN type ⚠️:** `WanProto` 0 DHCP, 1 static, 2 PPPoE, 3 bridge.
- **Usage:** the router exposes rates, not per-device byte counters. Any
  transfer totals must be integrated from rate samples and labelled as
  estimates (the app skips sample gaps longer than 15 s).
- **Upstream:** the router reports only its own WAN (type, IP, gateway,
  DNS). It does not identify the upstream device or ISP.

## 11. Reconnection and sequencing ✅

- Unexpected drops trigger reconnect attempts with a backoff of
  **1, 2, 4 and 8 s**, then every 8 s. Once per outage, the app re-runs
  discovery in case the router's IP changed.
- Reconnecting while backgrounded is suspended (mobile-specific; a Pi service
  should keep retrying).
- Connection attempts are serialized: a new connect cancels and tears down
  the previous transport before the new one subscribes.
- After a reconnect, re-subscribe to `<appId>/+`; subscriptions are not
  persisted.
- A certificate rejection is reported as its own event and is **not**
  retried with weaker checks.

## 12. Firmware limitations (tested unit)

- Commands are processed strictly serially, so slow commands delay all others.
- V2 Wi-Fi reads are unsupported (no reply).
- Periodic 4–5 s stalls.
- `GetSystemState` is empty. `GetExistNode` reports no firmware version, so
  a firmware status display can show only what nodes report.
- There are no per-device byte counters.
- There is no HTTP interface.

## 13. Sanitized examples

Read the mesh nodes:

```
PUBLISH <meshId>/<appId>/GetExistNode
{"AppId":"<appId>","Timeout":0,"ErrorCode":0,
 "Data":[{"NodeSn":"","OnLine":0,"NickName":"","ClientNum":0,"Role":"",
          "Uptime":0,"Model":"","LocalConn":0,"AddTime":0}],
 "Timestamp":1792240000}

REPLY on <appId>/GetExistNode
{"ErrorCode":0,"Data":[{"NodeSn":"<node-sn>","OnLine":1,"ClientNum":7,
  "Role":"mpp","Uptime":86400,"Model":"<model>","LocalConn":1}]}
```

Turn the main router's LED off, then verify:

```
PUBLISH <meshId>/<appId>/SetNodeLed   {"…":"…","Data":{"NodeSn":"<node-sn>","Led":0}}
REPLY   <appId>/SetNodeLed            {"ErrorCode":0}
PUBLISH <meshId>/<appId>/GetLedList   {"…":"…","Data":[{"NodeSn":"","NickName":"","Led":0}]}
REPLY   <appId>/GetLedList            {"ErrorCode":0,"Data":[{"NodeSn":"<node-sn>","NickName":"","Led":0}]}
```

Minimal Python (paho-mqtt) outline (for illustration; the TLS check is
described in §4):

```python
import hashlib, json, ssl, time, uuid
import paho.mqtt.client as mqtt

mesh_id, router_ip = "<meshId>", "<router-ip>"
app_id = uuid.uuid4().hex                        # persist this per install
password = hashlib.md5(f"dazoo{mesh_id}".encode()).hexdigest()  # or the custom one

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE                   # then verify the leaf manually (§4)

c = mqtt.Client(client_id=app_id, protocol=mqtt.MQTTv311)
c.username_pw_set(mesh_id, password)
c.tls_set_context(ctx)
c.on_connect = lambda c, *_: c.subscribe(f"{app_id}/+")
c.on_message = lambda c, u, m: print(m.topic, json.loads(m.payload))
c.connect(router_ip, 25678, keepalive=30)

def send(path, data):
    c.publish(f"{mesh_id}/{app_id}{path}", json.dumps({
        "AppId": app_id, "Timeout": 0, "ErrorCode": 0,
        "Data": data, "Timestamp": int(time.time())}))
```

## 14. Raspberry Pi considerations

- **Network:** the Pi must be on the router's LAN, either directly or through
  a mesh node. Everything is local and nothing needs internet access. Do not
  expose 25678 or a Pi API to the WAN; this app intentionally implements no
  remote access.
- **One request per path:** replicate the per-path queue and the 15 s
  late-reply guard (§6). Running the phone app and the Pi at the same time is
  safe only because each uses its own `<appId>`, and replies go to
  `<appId>/…`. The router's serial processing still means one client's slow
  command delays the other's.
- **Polling:** 3 s is the most the firmware tolerates comfortably. A
  headless service could poll telemetry every 5–10 s and devices every 15–30 s.
- **Clock:** `Timestamp` should be roughly correct. Run NTP; the router's
  tolerance for skew is unknown ⚠️.
- **Certificate expiry:** plan for the CA's 2030-05-18 expiry (§4).
- **Writes:** reuse the app's rules. Always read before writing, send full
  raw lists, verify by reading back, and never write WAN or LAN or reboot
  without an explicit operator action.
- **Discovery:** optional on a Pi if the router has a DHCP reservation; then
  configure `<router-ip>` and `<meshId>` directly.
- **Libraries:** `paho-mqtt` (Python) or `mqtt.js` (Node) both support
  MQTT 3.1.1 over TLS with a custom verification hook.

## 15. Open questions ⚠️

- The exact unit of `UpRate`/`DownRate` (treated as bytes/s, matching the
  original app's display).
- The meaning of discovery tag `06` and of `Timeout` in the envelope.
- V2 Wi-Fi support on newer firmware.
- The semantics of `GetSumOfNetworkFlow*`, and whether its values are
  reliable.
- Restart, WAN and LAN writes have never been sent to a live router by this
  project.
