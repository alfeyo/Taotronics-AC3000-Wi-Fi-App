import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nokia_provider.dart';
import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/feedback.dart';
import '../widgets/hub_widgets.dart' show KvRow;
import '../utils/format.dart';

class NokiaMeshScreen extends StatefulWidget {
  const NokiaMeshScreen({super.key, this.controller});
  final NokiaProvider? controller;
  @override
  State<NokiaMeshScreen> createState() => _NokiaMeshScreenState();
}

class _NokiaMeshScreenState extends State<NokiaMeshScreen>
    with WidgetsBindingObserver {
  late final NokiaProvider n;
  final address = TextEditingController(),
      user = TextEditingController(),
      password = TextEditingController();
  bool reveal = false;
  Timer? _freshness;
  @override
  void initState() {
    super.initState();
    n = widget.controller ?? NokiaProvider();
    n.addListener(_changed);
    _freshness = Timer.periodic(const Duration(seconds: 15), (_) => _changed());
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null) n.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A temporary setup-network switch must not retain a stale owner session.
    if (state == AppLifecycleState.resumed) {
      n.service.clearSession();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _freshness?.cancel();
    n.removeListener(_changed);
    if (widget.controller == null) n.dispose();
    address.dispose();
    user.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final pi = context.read<PiProvider?>();
    final raw = pi?.gateway?['nokia'];
    final candidates = raw is Map && raw['candidates'] is List
        ? (raw['candidates'] as List)
              .whereType<Map>()
              .map((d) => d['ip'])
              .whereType<String>()
              .toList()
        : <String>[];
    await n.discover(address: address.text, candidates: candidates);
  }

  Future<void> _bridge() async {
    final ok = await confirmAction(
      context,
      title: 'Use AP bridge mode?',
      message:
          'The Nokia root will restart and its management address may change. TaoTronics remains the household router and DHCP server. A fresh mode read and a client internet check are required before setup is verified.',
      confirmLabel: 'Set AP bridge',
      icon: Icons.lan_rounded,
    );
    if (ok && mounted) await n.enableBridge();
  }

  Future<void> _addExtender() async {
    final serial = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a Nokia extender'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Continue only after the second Beacon has been powered on for enrollment. Enter its printed serial. The root must report enrollment and backhaul before mesh is verified.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: serial,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Second Beacon serial',
                  hintText: 'ALCL…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, serial.text.trim()),
            child: const Text('Enroll powered-on Beacon'),
          ),
        ],
      ),
    );
    // Let the dialog finish its reverse transition before disposing its field.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    serial.dispose();
    if (mounted && value != null) await n.changeExtender(value);
  }

  @override
  Widget build(BuildContext context) {
    final id = n.identity;
    final logged = n.service.authenticated;
    final theme = Theme.of(context);
    final reportedModel = n.device?['ModelName'];
    final rootTitle = reportedModel is String && reportedModel.isNotEmpty
        ? reportedModel
        : id == null
        ? 'Find your root Beacon'
        : id.model.isEmpty
        ? 'Nokia root identified'
        : id.model;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nokia Mesh'),
        actions: [
          IconButton(
            tooltip: 'Refresh Nokia',
            onPressed: n.busy
                ? null
                : logged
                ? n.refresh
                : n.savedAddress != null
                ? n.reconnect
                : _find,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: n.busy
            ? () async {}
            : logged
            ? n.refresh
            : _find,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.lg),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(Space.xl),
                    decoration: BoxDecoration(
                      color: const Color(0xff191b20),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _BeaconArt(),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'WHOLE-HOME NETWORK',
                                    style: TextStyle(
                                      color: Color(0xffffa25b),
                                      letterSpacing: 1.5,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    rootTitle,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    n.bridgeVerified
                                        ? 'AP bridge read-back verified'
                                        : id != null
                                        ? 'Identity verified · ${logged ? 'owner session active' : 'owner login needed'}'
                                        : 'Root connected by Ethernet · awaiting local identity',
                                    style: const TextStyle(
                                      color: Color(0xffc0c3cc),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'MikroTik  →  Argon  →  TaoTronics',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ethernet uplinks • Argon measures household traffic\nTaoTronics LAN → Nokia root → Nokia extender (pending)',
                          style: TextStyle(
                            color: Color(0xffc0c3cc),
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  if (n.busy) const LinearProgressIndicator(),
                  if (n.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: InfoBanner(
                        tone: Tone.warning,
                        icon: Icons.info_outline,
                        title: 'Setup needs attention',
                        message: n.error!,
                      ),
                    ),
                  if (n.message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(n.message!),
                    ),
                  if (id != null)
                    PanelCard(
                      child: Column(
                        children: [
                          KvRow('Root serial', id.serial),
                          KvRow('Root MAC', id.mac),
                          KvRow('Management', id.address.toString()),
                          KvRow(
                            'Model',
                            reportedModel is String && reportedModel.isNotEmpty
                                ? reportedModel
                                : id.model.isEmpty
                                ? 'Not reported yet'
                                : id.model,
                          ),
                          KvRow('Mode', n.mode ?? 'Not read'),
                          KvRow(
                            'Uptime',
                            n.device?['UpTime'] == null
                                ? 'Not reported'
                                : '${n.device!["UpTime"]} seconds',
                          ),
                          KvRow(
                            'Firmware',
                            _deviceValue(n.device, [
                              'softwareVersion',
                              'SoftwareVersion',
                              'swVersion',
                              'firmware',
                              'Active_SW',
                            ]),
                          ),
                          KvRow(
                            'Last read',
                            n.observedAt == null
                                ? 'Not observed'
                                : '${formatAge(n.observedAt)} · ${n.current ? 'current' : 'stale'}',
                            last: true,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: Space.lg),
                  Text('Root setup', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _Step(
                    number: 1,
                    title: 'Find Nokia Beacon',
                    detail: id == null
                        ? 'Factory SSIDs and LAN candidates are hints. The local API must identify the root.'
                        : 'The root reports this serial and MAC address.',
                    done: id != null,
                  ),
                  _Step(
                    number: 2,
                    title: 'Connect for setup',
                    detail:
                        'Join the factory Wi-Fi shown on the Beacon label, then return here to finish setup.',
                    done: id != null,
                  ),
                  if (!logged) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: n.busy ? null : _find,
                          icon: const Icon(Icons.radar),
                          label: const Text('Find root'),
                        ),
                        OutlinedButton.icon(
                          onPressed: n.busy
                              ? null
                              : () async {
                                  try {
                                    await n.service.transport.openWifi();
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Open Android Wi-Fi settings to join the Beacon.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.wifi),
                          label: const Text('Setup Wi-Fi'),
                        ),
                        if (n.savedAddress != null)
                          OutlinedButton(
                            onPressed: n.busy ? null : n.reconnect,
                            child: const Text('Reconnect saved root'),
                          ),
                      ],
                    ),
                    ExpansionTile(
                      title: const Text('Enter an observed address'),
                      children: [
                        TextField(
                          controller: address,
                          decoration: const InputDecoration(
                            labelText: 'http://192.168… or Wi-Fi IPv6 address',
                          ),
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ],
                  _Step(
                    number: 3,
                    title: 'Local owner login',
                    detail:
                        'Nokia administrator credentials are separate from TaoTronics and Argon. Saved only in this phone’s secure storage.',
                    done: logged,
                  ),
                  if (id != null && !logged)
                    PanelCard(
                      child: Column(
                        children: [
                          TextField(
                            controller: user,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Nokia local admin username',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: password,
                            obscureText: !reveal,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'Nokia local admin password',
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => reveal = !reveal),
                                tooltip: reveal
                                    ? 'Hide password'
                                    : 'Show password',
                                icon: Icon(
                                  reveal
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Local HTTP sends this login only over the selected Wi-Fi network to the identified Beacon. HTTPS uses normal certificate validation.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: n.busy
                                ? null
                                : () async {
                                    await n.login(user.text, password.text);
                                    if (n.service.authenticated) {
                                      password.clear();
                                    }
                                  },
                            child: const Text('Authorize this Beacon'),
                          ),
                        ],
                      ),
                    ),
                  _Step(
                    number: 4,
                    title: 'AP bridge mode',
                    detail: n.mode == 'CFG'
                        ? 'Factory configuration mode: initial WLAN setup is still required.'
                        : n.bridgeRequested
                        ? 'Change requested; waiting for reboot and fresh read-back.'
                        : 'TaoTronics must remain the router and DHCP provider.',
                    done: n.bridgeVerified,
                  ),
                  if (logged && id?.bridgeSupported == true && n.mode == 'RGW')
                    FilledButton.icon(
                      onPressed: n.busy ? null : _bridge,
                      icon: const Icon(Icons.lan),
                      label: const Text('Configure AP bridge'),
                    ),
                  _Step(
                    number: 5,
                    title: 'Verify client internet and DHCP',
                    detail: n.clientVerified
                        ? 'Verified on this phone: TaoTronics DHCP/gateway ${n.verifiedGateway}, HTTPS internet via the Nokia radio.'
                        : 'A client connected through Nokia must receive the TaoTronics lease/gateway and reach the internet. A bridge acknowledgment does not prove this.',
                    done: n.clientVerified,
                  ),
                  if (n.bridgeVerified)
                    OutlinedButton.icon(
                      onPressed: n.busy
                          ? null
                          : () => n.verifyClient(
                              context
                                      .read<RouterProvider?>()
                                      ?.currentRouter
                                      ?.ipAddress ??
                                  '',
                            ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Verify this client path'),
                    ),
                  _Step(
                    number: 6,
                    title: 'Save trusted root',
                    detail: n.savedMac == null
                        ? 'Saved after successful owner login and device read.'
                        : 'Identity saved securely; current reachability is verified separately.',
                    done: n.savedMac != null,
                  ),
                  _Step(
                    number: 7,
                    title: 'Add the second Beacon',
                    detail:
                        'Keep the second unit outside provisioning until root bridge and client internet checks pass. Activation requires your approval.',
                    done: false,
                  ),
                  if (n.clientVerified && n.service.usesWeb)
                    OutlinedButton.icon(
                      onPressed: n.busy ? null : _addExtender,
                      icon: const Icon(Icons.add),
                      label: const Text('Add powered-on extender'),
                    ),
                  _Step(
                    number: 8,
                    title: 'Verify Nokia mesh',
                    detail:
                        'Root/extender relationship and backhaul must be reported by Nokia. TaoTronics is a separate mesh.',
                    done: false,
                  ),
                  if (logged && n.clients?['device_cfg'] is List) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      'Nokia-reported devices',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      '${n.reportedClients.length} records from Nokia · kept separate from TaoTronics totals',
                    ),
                    for (final client in n.reportedClients.take(50))
                      PanelCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${client['HostName'] ?? client['MACAddress'] ?? 'Unnamed device'}',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              '${client['IPAddress'] ?? 'IP unreported'} · ${client['MACAddress'] ?? 'MAC unreported'}',
                            ),
                            Text(
                              '${client['Active'] == 1
                                  ? 'Active'
                                  : client['Active'] == 0
                                  ? 'Inactive'
                                  : 'Activity unreported'} · ${client['InterfaceType'] ?? 'Interface unreported'}',
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (logged && n.extenders != null) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      'Nokia mesh inventory',
                      style: theme.textTheme.titleLarge,
                    ),
                    if (n.extenders?['beacon_detail'] is List &&
                        n.meshNodes.isEmpty)
                      const Text('The root reports no enrolled extenders.'),
                    for (final node in n.meshNodes)
                      PanelCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KvRow(
                              'Serial',
                              '${node['SerialNumber'] ?? 'Not reported'}',
                            ),
                            KvRow(
                              'Name',
                              '${node['FriendlyName'] ?? 'Not reported'}',
                            ),
                            KvRow(
                              'Onboarding',
                              '${node['OnboardStatus'] ?? 'Not reported'}',
                            ),
                            KvRow(
                              'Backhaul',
                              '${node['BackhaulStatus'] ?? 'Not reported'}',
                            ),
                            KvRow(
                              'MAC',
                              '${node['MACAddress'] ?? 'Not reported'}',
                              last: true,
                            ),
                            if (n.current &&
                                n.service.usesWeb &&
                                node['SerialNumber'] is String &&
                                node['MACAddress'] is String)
                              TextButton(
                                onPressed: n.busy
                                    ? null
                                    : () async {
                                        if (await confirmAction(
                                              context,
                                              title: 'Remove this extender?',
                                              message:
                                                  'Remove ${node['SerialNumber']} from this Nokia root. Devices using it may disconnect.',
                                              confirmLabel: 'Remove extender',
                                              icon: Icons.remove_circle_outline,
                                            ) &&
                                            mounted) {
                                          await n.changeExtender(
                                            node['SerialNumber'] as String,
                                            removeMac:
                                                node['MACAddress'] as String,
                                          );
                                        }
                                      },
                                child: const Text('Remove extender'),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (logged && n.wirelessProfiles.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      'Nokia wireless networks',
                      style: theme.textTheme.titleLarge,
                    ),
                    for (final r in n.wirelessProfiles)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: PanelCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['SSID'] ?? 'Unnamed profile'}',
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                '${r['Enable'] == 1 ? 'On' : 'Off'} · ${r['WPAEncryptionModes'] ?? 'Security unreported'} · ${r['BeaconType'] ?? ''}',
                              ),
                              Text(
                                'Channel ${r['Channel'] ?? 'unreported'} · ${r['Standard'] ?? 'band unreported'}',
                              ),
                              Text(
                                'BSSID ${r['BSSID'] ?? 'unreported'}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (logged) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      'Nokia observations',
                      style: theme.textTheme.titleLarge,
                    ),
                    PanelCard(
                      child: Column(
                        children: [
                          KvRow(
                            'Wireless profiles',
                            n.wlan == null
                                ? 'Endpoint unavailable'
                                : 'Local response received; verified fields below',
                          ),
                          KvRow(
                            'Clients',
                            n.clients == null
                                ? 'Not reported'
                                : '${n.reportedClients.length} Nokia records · separate from TaoTronics totals',
                          ),
                          KvRow(
                            'Extender state',
                            n.extenders == null
                                ? 'Not reported'
                                : 'Local response available · mesh not yet validated',
                          ),
                          KvRow(
                            'Internet',
                            n.wan?['gwwanup'] == 1
                                ? 'Nokia reports uplink online; client check separate'
                                : n.wan?['gwwanup'] == 0
                                ? 'Nokia reports uplink offline'
                                : 'Not reported',
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Controls appear only when the current device reports a supported capability and its local response is understood. Firmware updates and radio/channel writes are unavailable until their complete payloads and read-back are verified.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (logged && n.savedAddress != null)
                    TextButton(
                      onPressed: n.busy ? null : n.reconnect,
                      child: const Text('Reconnect saved root'),
                    ),
                  if (n.savedAddress != null)
                    TextButton(
                      onPressed: n.busy
                          ? null
                          : () async {
                              if (await confirmAction(
                                    context,
                                    title: 'Forget Nokia login?',
                                    message:
                                        'Remove the saved Nokia owner credentials from this phone. The Beacon configuration is unchanged.',
                                    confirmLabel: 'Forget',
                                    icon: Icons.lock_reset,
                                  ) &&
                                  mounted) {
                                await n.forget();
                              }
                            },
                      child: const Text('Forget Nokia login'),
                    ),
                  const SizedBox(height: Space.xl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _deviceValue(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return 'Not reported';
  for (final k in keys) {
    final v = data[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return 'Not reported';
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
    required this.done,
  });
  final int number;
  final String title, detail;
  final bool done;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: done
              ? const Color(0xffb6642b)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: done
              ? const Icon(Icons.check, size: 17, color: Colors.white)
              : Text('$number', style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Neutral Beacon silhouette: no unverified model photograph is presented.
class _BeaconArt extends StatelessWidget {
  const _BeaconArt();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Nokia Beacon illustration',
    child: Container(
      width: 65,
      height: 104,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xfff3f3ee), Color(0xffbfc3c5), Color(0xffe6e7e1)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(5, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'NOKIA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xff41464c),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 26),
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xffe99856),
            ),
          ),
        ],
      ),
    ),
  );
}
