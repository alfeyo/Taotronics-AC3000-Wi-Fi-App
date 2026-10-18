# Nokia provisioning and Wi-Fi review — 18 October 2026

## Actual repositories and scope

Flutter: `feature/argon-pi-integration`, baseline `bfb2331`, release baseline `12e61a9` (1.8.0+16). Origin was verified as `git@github.com:alfeyo/Taotronics-AC3000-Wi-Fi-App.git`. New release is 1.9.0+17. Argon: `feature/taotronics-router-integration`, local HEAD `a8373a8`, production `51e49e5`; no configured remote. No Next.js UI or production system changes in this phase.

## Review findings addressed

CodeRabbit reviewed both baselines and the Flutter uncommitted implementation. Confirmed repairs:

- Precise Android location permission errors now explain the requirement instead of repeating a blocked scan.
- Wi-Fi writes require read-back even after ErrorCode 0; preserve firmware-normalized responses and compare isolation/VLAN/enable/security fields.
- Guest writes re-read current settings, preserve unrelated fields, and verify every submitted field including the password.
- Nokia transport rejects cross-origin paths before attaching a session cookie, disables redirects, bounds response/body sizes and accepts only private targets and verified CGI paths.
- Open networks do not display a password Show/Hide control.
- A test assertion that used the wrong service instance was corrected.
- Historical overview text incorrectly claimed 1.8 installation on OnePlus; only Fold4 installation was verified in that release run.

Hardware validation additionally found Nokia's successful HTTP 299 login, mixed-case `AP_Bridge` identity, changed post-bridge address and a separate `wlan_config_glb11ac` response. These are covered explicitly. Authenticated identity must match discovery; credentials are not sent to a different saved-address occupant.

## Unresolved Argon review issue — no production change

CodeRabbit identified a real VPN bootstrap problem: the global NetworkManager VPN DNS override points host resolution at tunnel-only resolvers before tun0 exists. Read-only inspection found London has a literal-IP primary remote, while other location profiles use hostname remotes. Those profiles can fail to resolve during cold startup/restart under the DNS guard.

The user's phase constraint explicitly prohibits modifying active Argon routing/firewall/NAT/DHCP/VPN/SSH and permits only necessary mobile backend changes. Therefore no speculative resolver, profile or VPN-service change was deployed or committed here. VPN remained off. Fixing and validating hostname bootstrap requires a separately scoped VPN change and a controlled startup/rollback test. Existing location UI is preserved; this report does not claim every location can start successfully.

## Final implementation review

CodeRabbit raised 2 issues in the final implementation review (1 major, 1 minor): automatic credential reuse trusted unauthenticated identity fields, and blocking DNS shared the API worker. Both were addressed: the owner-established RSA key is pinned and checked before password replay, legacy/unpinned credentials are not replayed, and DNS has a separate executor. A regression test with matching spoofed MAC/serial but a changed key verifies no password envelope/login is sent. A guest-save test also exposed delayed verification notifying a disposed RouterProvider; session-generation checks now cancel those results.

## Validation

Evidence is summarized in `NOKIA_BRIDGE_VALIDATION.md` and the 1.9.0 release record. Flutter analyzer reports no issues; all 215 tests pass. Release APK builds successfully. Signing certificate matches the existing release. Final in-place Fold4 installation and owner-session verification are recorded in the release log. The final CodeRabbit review completed and both issues were addressed with targeted regression coverage. OnePlus physical testing and second-Beacon mesh/backhaul validation remain explicitly separate from simulated layout/protocol tests.
