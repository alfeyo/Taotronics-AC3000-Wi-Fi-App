import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nokia_home/providers/nokia_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NokiaHomeApp());
}

class NokiaHomeApp extends StatelessWidget {
  const NokiaHomeApp({super.key, this.controller});
  final NokiaProvider? controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nokia Home',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: NokiaHomeScreen(controller: controller),
  );

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff1238b5),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff3f5fa)
          : const Color(0xff10131d),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

class NokiaHomeScreen extends StatefulWidget {
  const NokiaHomeScreen({super.key, this.controller});
  final NokiaProvider? controller;

  @override
  State<NokiaHomeScreen> createState() => _NokiaHomeScreenState();
}

class _NokiaHomeScreenState extends State<NokiaHomeScreen>
    with WidgetsBindingObserver {
  late final NokiaProvider n;
  final address = TextEditingController();
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  final gateway = TextEditingController(text: '192.168.10.1');
  final serial = TextEditingController();
  int tab = 0, _generation = 0;
  bool showPassword = false;
  Timer? freshness;

  @override
  void initState() {
    super.initState();
    n = widget.controller ?? NokiaProvider();
    n.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    freshness = Timer.periodic(const Duration(seconds: 15), (_) => _changed());
    if (widget.controller == null) unawaited(n.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from Wi-Fi settings requires new evidence and authentication.
    _generation++;
    _invalidateEvidence();
    _changed();
  }

  void _invalidateEvidence() {
    n.stopEnrollmentObservation();
    n.observedAt = n.meshObservedAt = n.clientVerifiedAt = n.diagnosticAt =
        null;
    n.service.clearSession();
    password.clear();
  }

  Future<void> _perform(Future<void> Function() operation) async {
    final generation = _generation;
    await operation();
    if (!mounted) return;
    if (generation != _generation) {
      _invalidateEvidence();
      n.message = null;
      n.error =
          'Connection context changed. Check Wi-Fi and reconnect to verify fresh results.';
    }
    _changed();
  }

  @override
  void dispose() {
    freshness?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    n.removeListener(_changed);
    n.stopEnrollmentObservation();
    if (widget.controller == null) n.dispose();
    for (final field in [address, username, password, gateway, serial]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _find() async {
    final input = address.text.trim();
    await _perform(
      () => n.discover(
        address: input.isEmpty || input.contains('://')
            ? input
            : 'http://$input',
      ),
    );
    if (mounted && n.identity != null && n.error == null) {
      setState(() => tab = 1);
    }
  }

  Future<void> _login() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the local administrator name and password.'),
        ),
      );
      return;
    }
    await _perform(() => n.login(username.text.trim(), password.text));
    if (mounted) password.clear();
  }

  Future<void> _enroll() async {
    final value = serial.text.trim().toUpperCase();
    if (!RegExp(r'^ALCL[A-Z0-9]{8}$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the printed 12-character ALCL serial.'),
        ),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enroll this Beacon?'),
        content: Text(
          'Register $value with ${n.identity?.serial}. The second Beacon must be powered on nearby and ready for setup. This starts Nokia enrollment; it does not give the root a new internet uplink.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enroll Beacon'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _perform(() => n.changeExtender(value));
    if (mounted && n.error == null) n.observeExtender(value);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_connect, _beacon, _devices];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nokia Home',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh current connection',
            onPressed: n.busy ? null : () => _perform(n.diagnoseConnection),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi_rounded),
            label: 'Connect',
          ),
          NavigationDestination(
            icon: Icon(Icons.router_outlined),
            label: 'Beacon',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_rounded),
            label: 'Devices',
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: ValueKey(tab),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                if (n.busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                if (n.error != null) _notice(n.error!, warning: true),
                if (n.message != null) _notice(n.message!),
                ...pages[tab](),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _connect() {
    final current = n.diagnosticsCurrent;
    final phone = current ? n.diagnosticPhone : <String, dynamic>{};
    final passed =
        current && n.diagnosticInternet == 'Passed' && n.diagnosticStable;
    final throughNokia =
        passed &&
        n.diagnosticNokiaRadio &&
        n.diagnosticRoot == 'Matching root replied';
    return [
      Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xff1238b5), Color(0xff122154)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.wifi_rounded, color: Color(0xff5ce6ce), size: 40),
            const SizedBox(height: 20),
            const Text(
              'Your home.\nYour connection.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Connect this phone to your Wi-Fi, then find and manage your Nokia Beacon locally.',
              style: TextStyle(color: Color(0xffd8e3ff), height: 1.6),
            ),
            const SizedBox(height: 22),
            FilledButton.tonalIcon(
              onPressed: n.busy
                  ? null
                  : () => n.run(n.service.transport.openWifi),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Choose Wi-Fi'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _section('1. Join your Wi-Fi', [
        const Text(
          'Choose “Nokia Wifi” in Android settings. For a factory Beacon, choose its printed NOKIA-… network and enter the label’s Wi-Fi key there. Return here to check the connection.',
        ),
        const SizedBox(height: 12),
        const Text(
          'The Wi-Fi name alone does not identify which router serves this phone.',
        ),
      ]),
      _section('2. Check this phone', [
        _status(
          throughNokia
              ? 'Internet verified through Nokia'
              : passed
              ? 'Phone Wi-Fi internet passed · Nokia path unverified'
              : current
              ? n.diagnosticInternet
              : 'Connection not checked',
          good: throughNokia,
        ),
        _row('Wi-Fi name', phone['ssid']),
        _row('Access point (BSSID)', phone['bssid']),
        _row('Phone address', phone['ip']),
        _row('Gateway', phone['gateway']),
        _row('DHCP server', phone['dhcpServer']),
        _row('Signal', phone['rssi'] == null ? null : '${phone['rssi']} dBm'),
        _row('Beacon response', current ? n.diagnosticRoot : null),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: n.busy ? null : () => _perform(n.diagnoseConnection),
          icon: const Icon(Icons.network_check),
          label: const Text('Check Wi-Fi internet'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Checks use this phone’s Wi-Fi connection, never cellular. Results expire after 90 seconds.',
        ),
      ]),
      _section('3. Find your Beacon', [
        const Text(
          'Discovery checks Nokia’s local device identity before asking for the administrator password.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Beacon address (optional)',
            hintText: 'Last known: 192.168.10.97',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: n.busy ? null : _find,
          icon: const Icon(Icons.search),
          label: const Text('Find Beacon'),
        ),
        if (n.savedAddress != null)
          TextButton(
            onPressed: n.busy ? null : () => _perform(n.reconnect),
            child: const Text('Reconnect to saved Beacon'),
          ),
      ]),
      _notice(
        'Beacon internet uplink: no supported connection from this Beacon 2 firmware to another brand’s Wi-Fi has been verified. Connecting the phone or sharing a Wi-Fi name does not establish that link.',
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Independent companion app · no Nokia cloud account needed',
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }

  List<Widget> _beacon() {
    final id = n.identity;
    final logged = n.service.authenticated;
    if (id == null) {
      return [
        _section('Find your Nokia Beacon', [
          const Icon(Icons.router_outlined, size: 64),
          const SizedBox(height: 20),
          const Text(
            'Join its Wi-Fi or home network first. Device identity and status appear after a real local response.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => tab = 0),
            child: const Text('Go to connection setup'),
          ),
        ]),
      ];
    }
    return [
      _section(id.model.isEmpty ? 'Nokia Beacon' : id.model, [
        _status(
          logged
              ? 'Local administrator session active'
              : 'Identity found · administrator login needed',
          good: logged,
        ),
        _row('Serial', id.serial),
        _row('MAC address', id.mac),
        _row('Management address', id.address.toString()),
        _row('Firmware', n.device?['SoftwareVersion']),
        _row('Reported mode', n.current ? n.mode : null),
        _row('Root uplink', n.uplinkHealth),
      ]),
      if (!logged)
        _section('Local administrator', [
          const Text(
            'Use this Beacon’s administrator credentials. This is device access, not a cloud account. Saved credentials are encrypted in this app’s private storage.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: username,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Administrator name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: !showPassword,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Administrator password',
              suffixIcon: IconButton(
                tooltip: showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                  showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: n.busy ? null : _login,
            child: const Text('Connect to Beacon'),
          ),
          if (n.savedAddress != null)
            TextButton(
              onPressed: n.busy ? null : () => _perform(n.reconnect),
              child: const Text('Use saved device login'),
            ),
        ]),
      if (logged) ...[
        _section('Broadcast Wi-Fi', [
          if (!n.current) const Text('Status is stale. Refresh the Beacon.'),
          if (n.wirelessProfiles.isEmpty)
            const Text('No radio details reported.'),
          for (final radio in n.wirelessProfiles) ...[
            _row('Wi-Fi name', radio['SSID']),
            _row('Radio BSSID', radio['BSSID']),
            _row('Enabled (reported)', radio['Enable']),
            const Divider(),
          ],
          OutlinedButton.icon(
            onPressed: n.busy ? null : () => _perform(n.refresh),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Beacon status'),
          ),
        ]),
        _section('Verify the root’s client connection', [
          const Text(
            'Join a radio reported by this Beacon, then verify DHCP, gateway and internet before enrolling another unit.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: gateway,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Expected household gateway',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: n.busy
                ? null
                : () => _perform(() => n.verifyClient(gateway.text.trim())),
            child: const Text('Verify Nokia client path'),
          ),
          if (n.clientVerified)
            const Text(
              'Root client path verified. This does not verify an extender.',
            ),
        ]),
        _section('Add a Nokia Beacon', [
          const Text(
            'Nokia enrollment registers the second unit’s serial with this root. The root must have a freshly verified internet connection first.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: serial,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 12,
            decoration: const InputDecoration(
              labelText: 'Second Beacon serial',
              hintText: 'ALCL…',
            ),
          ),
          FilledButton.icon(
            onPressed: n.busy || !n.clientVerified ? null : _enroll,
            icon: const Icon(Icons.add),
            label: const Text('Add Beacon'),
          ),
          if (n.enrollmentSerial != null) ...[
            const SizedBox(height: 12),
            Text(n.enrollmentStatus),
            TextButton(
              onPressed: n.watchingEnrollment
                  ? n.stopEnrollmentObservation
                  : n.busy
                  ? null
                  : () => n.observeExtender(n.enrollmentSerial!),
              child: Text(
                n.watchingEnrollment
                    ? 'Stop observation'
                    : 'Observe reported status',
              ),
            ),
          ],
        ]),
      ],
      if (n.savedAddress != null)
        TextButton.icon(
          onPressed: n.busy
              ? null
              : () async {
                  _generation++;
                  _invalidateEvidence();
                  await n.forget();
                  if (mounted) setState(() => tab = 0);
                },
          icon: const Icon(Icons.key_off),
          label: const Text('Forget saved device login'),
        ),
    ];
  }

  List<Widget> _devices() => [
    _section('Nokia mesh', [
      _status(
        n.meshCurrent
            ? 'Recent root inventory'
            : 'Inventory unverified or stale',
      ),
      const Text(
        'A listed Beacon is not proof of wireless backhaul or internet. Missing link information stays unknown.',
      ),
      if (n.meshCurrent && n.meshNodes.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('No extenders listed by this root.'),
        ),
      for (final node in n.meshNodes) ...[
        const Divider(height: 32),
        Text(
          NokiaProvider.reportedValue(node['FriendlyName']),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _row('Serial', node['SerialNumber']),
        _row('Address', node['IPAddress']),
        _row('Onboarding (reported)', node['OnboardStatus']),
        _row('Backhaul (reported)', node['BackhaulStatus']),
        _row('Wireless signal / parent', null),
        _row('Extender internet', 'Not verified'),
      ],
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: n.busy || !n.service.authenticated
            ? null
            : () => _perform(n.refresh),
        child: const Text('Refresh inventory'),
      ),
    ]),
    _section('Connected client records', [
      if (!n.current || n.clients?['device_cfg'] is! List)
        const Text(
          'Current client inventory unavailable. Connect to the Beacon and refresh.',
        )
      else if (n.reportedClients.isEmpty)
        const Text('Nokia returned no client records.')
      else ...[
        const Text(
          'Records reported by Nokia; presence alone does not prove a client is online.',
        ),
        for (final client in n.reportedClients) ...[
          const Divider(height: 28),
          Text(
            NokiaProvider.reportedValue(
              client['HostName'] ?? client['MACAddress'],
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          _row('MAC address', client['MACAddress']),
          _row('IP address', client['IPAddress']),
        ],
      ],
    ]),
  ];

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _notice(String text, {bool warning = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: warning
              ? Theme.of(context).colorScheme.onErrorContainer
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    ),
  );

  Widget _status(String text, {bool good = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          good ? Icons.check_circle_outline : Icons.info_outline,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _row(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      spacing: 10,
      runSpacing: 3,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          NokiaProvider.reportedValue(value),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}
