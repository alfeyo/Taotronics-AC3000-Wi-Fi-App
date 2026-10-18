import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pi_provider.dart';
import '../services/hub_links.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class NokiaMeshScreen extends StatelessWidget {
  const NokiaMeshScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final raw = pi.gateway?['nokia'];
    final data = raw is Map ? raw : null;
    final setup = data?['setup'];
    final detail = setup is Map ? setup['detail'] : null;
    final nodes = _maps(data?['nodes']);
    return Scaffold(
      appBar: AppBar(title: const Text('Nokia Mesh')),
      body: RefreshIndicator(
        onRefresh: pi.reconnect,
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const Icon(Icons.router_rounded, size: 72),
            const SizedBox(height: Space.lg),
            Text(
              data == null
                  ? 'Awaiting Argon setup report'
                  : 'Ready for staged setup',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Space.md),
            Text(
              detail?.toString() ??
                  'Connect to Argon to read the current Nokia setup state.',
            ),
            const SizedBox(height: Space.md),
            Text(
              'Argon: ${pi.connected ? 'connected' : 'unreachable'} · ${pi.gatewayFresh ? 'current report' : 'report unavailable or stale'}',
            ),
            const SizedBox(height: Space.lg),
            const Text(
              'Planned topology',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              (data?['topology'] is List ? data!['topology'] as List : [])
                  .whereType<String>()
                  .join(' → '),
            ),
            const Text(
              'TaoTronics remains the router and DHCP provider. The two Nokia Beacons form a separate Nokia mesh.',
            ),
            for (final n in nodes)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n['name']?.toString() ?? 'Beacon',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text('Factory-reset · not provisioned'),
                      for (final key in [
                        'model',
                        'firmware',
                        'managementIp',
                        'backhaul',
                        'signal',
                        'clients',
                        'observedAt',
                      ])
                        Text('$key: ${n[key] ?? 'Not observed'}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Space.lg),
            const Text(
              'Setup guide',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Reading these steps does not configure hardware or confirm validation.',
            ),
            for (final s in _maps(data?['steps']))
              ExpansionTile(
                title: Text(s['title'].toString()),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Text(s['detail'].toString()),
                  ),
                ],
              ),
            for (final g in _maps(data?['guides']))
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(g['title'].toString()),
                onPressed: () async {
                  try {
                    await HubLinks.open(g['url'].toString());
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open the Nokia guide.'),
                        ),
                      );
                    }
                  }
                },
              ),
            const SizedBox(height: Space.md),
            Text(
              data?['limitation']?.toString() ??
                  'Nokia monitoring is not yet verified.',
            ),
            Text(
              'Rollback: ${data?['rollback'] ?? 'Keep the Beacons powered off.'}',
            ),
          ],
        ),
      ),
    );
  }
}

List<Map> _maps(Object? value) =>
    value is List ? value.whereType<Map>().toList() : const [];
