# Argon companion API v1

> Superseded in detail by the server-side contract `argon-dashboard/docs/contracts/argon-v1.md`. Its 24 October additions cover the router control lease (`/api/v1/router/lease`), `gateway.router.control`, new event kinds, and paired-phone signatures for usage alerts. TT Router 1.11.0 consumes those. Endpoint use by screen is in [PI_FIRST_TRANSITION.md](PI_FIRST_TRANSITION.md).

The browser keeps its existing sign-in-free monitoring. This API always requires `Authorization: Bearer <companion token>`, independently of ARGON_AUTH_MODE. Configure ARGON_COMPANION_TOKEN on the Pi; store the token in the phone's Keystore. The companion token grants read-only Pi monitoring and sanitized inventory upload, never router control. Use HTTPS with normal certificate validation, or the Pi's literal Tailscale IPv4 over an active private VPN. Never follow redirects with credentials. No credentials are bundled into the APK.

All times are Unix seconds in UTC, rates are **bits per second**, counters are **bytes**, durations seconds, temperatures Celsius, CPU percentage is across all cores. Null means unavailable, not zero. Responses use `{version:1,ok:true,generatedAt,...}`; errors use `{ok:false,error}` with 401 authorization, 400 invalid data, 409 replay/unsupported operation, 413 size limit, 503 unavailable. Responses are no-store. Poll at most once per 15 seconds in the foreground; retain clearly marked stale data on failure. No background push service.

## GET /api/v1/gateway

Returns `gateway` (host, uptimeSeconds, temperatureC, cpuPercent, activeThrottling, upstream {interface,ssid,online}, vpn {state,mode,location}), `traffic` (sampleAt, stale, aggregate {downloadBps,uploadBps}, today {downloadBytes,uploadBytes,vpnDownloadBytes,vpnUploadBytes}, source), `history` (local-date daily rows and measured coverage from SQLite), `router` (existing normalized router-monitor schema), and `events` ({id,at,kind,severity,message,source}). Each source retains its own sample time. An API response time is not a router observation time.

Events are generated and persisted by the server when this API is polled, from observed VPN/uplink/collector state transitions, active throttling, and temperature >=75C continuously observed for >=120 seconds with no observation gaps >45s. They are deduplicated and retained to 200 entries. They do not claim coverage while nobody is polling. The phone displays Pi unreachability as a local connection state, not a fabricated server event.

## POST /api/v1/router/snapshot

128 KiB maximum JSON. Version 1 payload: `{version:1,observedAt,router:{name,model,internet,devicesOnline,nodesOnline,nodesTotal,ledOn},clients:[{mac,ip,hostname,connectionType,online,rateRxBps,rateTxBps,nodeSn}],nodes:[{sn,name,model,role,online,clients,uptimeSeconds}],wifi:[{index,band,ssid,enabled,secured}],guest:{ssid,enabled},wan:{ip,gateway,protocol}}`.

The phone must have an authenticated, certificate-verified router session and inventory observed within 20 seconds. Optional fields are sent only when their source is fresh. The server validates and allowlists fields, caps lists (512 clients/32 nodes/16 SSIDs), rejects timestamps older than 60s or more than 5s in the future, and rejects replay/out-of-order uploads. Client MACs must be valid and unique. Passwords, pairing credentials and arbitrary raw router replies are never saved or returned.

Accepted snapshots are labelled **phone-supplied** with observedAt and receivedAt; status/rates expire 60 seconds after observedAt. Inventory is also passed to the existing `argon-telemetry-query ingest-clients <identified-router-id> flutter-phone` mechanism. No new traffic collector. A fresh direct LAN observer takes precedence; otherwise use the freshest valid phone observation. Failed ingestion returns 503 rather than claiming success. Historical per-client usage remains unmeasured.

## POST /api/v1/router/control

Always requires the separate operator ARGON_API_TOKEN, even with dashboard auth off. Currently returns 409 `Router writes unavailable: no verified direct management connection.` No MQTT write, firmware or blocking operations are implemented. This fail-closed endpoint documents the privilege boundary, not an unverified control capability. Password visibility is unavailable; passwords are excluded from monitoring.

## Source ownership

Pi eth1 nftables = household/WAN totals; VPN crossing tun0 = subset; SQLite = measured local-day history; vnStat = separate interface totals. Router MQTT = client inventory, Wi-Fi, mesh, LEDs, router internet status. Gateway detection is independent of management reachability. Router rate units follow the existing app's bytes/s interpretation, converted x8; vendor unit semantics remain inferred.
