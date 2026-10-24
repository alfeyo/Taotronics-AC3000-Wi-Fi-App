import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/managed_router.dart';

enum ArgonDeviceFilter {
  all('All'),
  online('Online'),
  offline('Offline'),
  wifi('Wi-Fi'),
  wired('Wired');

  const ArgonDeviceFilter(this.label);
  final String label;

  bool matches(ArgonClient c) => switch (this) {
    ArgonDeviceFilter.all => true,
    ArgonDeviceFilter.online => c.online == true,
    ArgonDeviceFilter.offline => c.online != true,
    ArgonDeviceFilter.wifi => c.connectionType == 'wifi',
    ArgonDeviceFilter.wired => c.connectionType == 'wired',
  };
}

enum ArgonDeviceSort {
  activity('Current activity'),
  usage('Usage today'),
  name('Name'),
  ip('IP address');

  const ArgonDeviceSort(this.label);
  final String label;
}

int _ipKey(String? ip) {
  final parts = ip?.split('.').map(int.tryParse).toList();
  if (parts == null || parts.length != 4 || parts.contains(null)) {
    return 1 << 32;
  }
  return parts.fold<int>(0, (sum, p) => sum * 256 + p!);
}

/// Filtering, search and sorting of Argon's client inventory (pure, tested).
List<ArgonClient> arrangeArgonClients(
  List<ArgonClient> clients, {
  ArgonDeviceFilter filter = ArgonDeviceFilter.all,
  ArgonDeviceSort sort = ArgonDeviceSort.activity,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  int byName(ArgonClient a, ArgonClient b) {
    // Named devices first, then by name.
    final named = (b.friendlyName != null ? 1 : 0).compareTo(
      a.friendlyName != null ? 1 : 0,
    );
    return named != 0
        ? named
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  final list = [
    for (final c in clients)
      if (filter.matches(c) &&
          (q.isEmpty ||
              [
                c.displayName,
                c.hostname,
                c.ip,
                c.mac,
              ].any((v) => v != null && v.toLowerCase().contains(q))))
        c,
  ];
  list.sort((a, b) {
    final online = (b.online == true ? 1 : 0).compareTo(
      a.online == true ? 1 : 0,
    );
    return switch (sort) {
      ArgonDeviceSort.activity =>
        online != 0
            ? online
            : b.totalBitsPerSec.compareTo(a.totalBitsPerSec) != 0
            ? b.totalBitsPerSec.compareTo(a.totalBitsPerSec)
            : byName(a, b),
      ArgonDeviceSort.usage =>
        (b.today?.totalBytes ?? -1).compareTo(a.today?.totalBytes ?? -1) != 0
            ? (b.today?.totalBytes ?? -1).compareTo(a.today?.totalBytes ?? -1)
            : byName(a, b),
      ArgonDeviceSort.name => byName(a, b),
      ArgonDeviceSort.ip => _ipKey(a.ip).compareTo(_ipKey(b.ip)),
    };
  });
  return list;
}

String coverageLabel(double? coverage) => coverage == null
    ? 'coverage unknown'
    : '${(coverage * 100).toStringAsFixed(coverage >= 0.995 ? 0 : 1)}% of the day observed';

/// Devices in Argon mode: Argon's normalized router-client inventory (from
/// its LAN observer), with per-device usage estimated from sampled rates.
class ArgonDevicesView extends StatefulWidget {
  const ArgonDevicesView({super.key});

  @override
  State<ArgonDevicesView> createState() => _ArgonDevicesViewState();
}

class _ArgonDevicesViewState extends State<ArgonDevicesView> {
  ArgonDeviceFilter _filter = ArgonDeviceFilter.all;
  ArgonDeviceSort _sort = ArgonDeviceSort.activity;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final theme = Theme.of(context);
    final view = pi.routerView;
    final all = view?.clients ?? const <ArgonClient>[];
    final shown = arrangeArgonClients(
      all,
      filter: _filter,
      sort: _sort,
      query: _search.text,
    );
    final estimated = view?.usageMethod == 'estimated';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: pi.refreshNow,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              120,
            ),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Devices', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      view == null
                          ? hubValue(pi.hubState, null)
                          : '${view.onlineCount ?? '—'} online · ${view.knownCount ?? all.length} known · '
                                '${routerMonitoringLabel(view)}'
                                '${view.observedAt == null ? '' : ', ${formatAge(view.observedAt)}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    if (view != null && !view.live)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: InfoBanner(
                          tone: Tone.warning,
                          icon: Icons.history_rounded,
                          title: routerMonitoringLabel(view),
                          message:
                              view.monitoringDetail ??
                              'Online status and rates are unknown until Argon '
                                  'observes the router again.',
                        ),
                      ),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search name, IP or MAC',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () =>
                                    setState(() => _search.clear()),
                              ),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in ArgonDeviceFilter.values) ...[
                            ChoiceChip(
                              label: Text(f.label),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                            const SizedBox(width: Space.sm),
                          ],
                          PopupMenuButton<ArgonDeviceSort>(
                            tooltip: 'Sort devices',
                            initialValue: _sort,
                            onSelected: (s) => setState(() => _sort = s),
                            itemBuilder: (_) => [
                              for (final s in ArgonDeviceSort.values)
                                PopupMenuItem(value: s, child: Text(s.label)),
                            ],
                            child: Chip(
                              avatar: const Icon(Icons.sort_rounded, size: 18),
                              label: Text(_sort.label),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    if (shown.isEmpty)
                      EmptyState(
                        icon: Icons.devices_other_outlined,
                        title: all.isEmpty
                            ? hubValue(pi.hubState, 'No devices reported')
                            : 'No matching devices',
                        message: all.isEmpty
                            ? 'Argon lists household devices once its router '
                                  'observer reports them.'
                            : 'Change the filter or search.',
                      )
                    else
                      PanelCard(
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Column(
                          children: [
                            for (final c in shown)
                              _ClientRow(client: c, estimated: estimated),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.md),
                    Text(
                      [
                        'Source: Argon · ${view?.sourceLabel ?? 'router inventory'}',
                        'rates in bits per second',
                        if (estimated)
                          'daily usage is estimated from sampled router rates, not metered',
                      ].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.estimated});
  final ArgonClient client;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = client;
    final muted = theme.colorScheme.onSurfaceVariant;
    final online = c.online;
    final rate = online == true && (c.downBitsPerSec != null)
        ? '↓ ${formatBitRate(c.downBitsPerSec!)} ↑ ${formatBitRate(c.upBitsPerSec ?? 0)}'
        : null;
    final usage = c.today?.totalBytes;
    return ListTile(
      onTap: () => showArgonClientDetails(context, c, estimated: estimated),
      leading: IconBadge(
        c.isWired ? Icons.settings_ethernet_rounded : Icons.wifi_rounded,
        tone: online == true
            ? Tone.success
            : online == false
            ? Tone.neutral
            : Tone.warning,
        size: 38,
        round: true,
      ),
      title: Text(
        c.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: c.friendlyName == null
            ? theme.textTheme.titleSmall?.copyWith(color: muted)
            : null,
      ),
      subtitle: Text(
        [
          online == true
              ? 'Online'
              : online == false
              ? 'Offline'
              : 'Status unknown',
          ?c.ip,
          ?rate,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
      trailing: usage == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${estimated ? '≈ ' : ''}${formatBytes(usage)}',
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  'today',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ),
    );
  }
}

Future<void> showArgonClientDetails(
  BuildContext context,
  ArgonClient c, {
  required bool estimated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      final maxDay = c.days
          .map((d) => d.totalBytes ?? 0)
          .fold<int>(1, (a, b) => a > b ? a : b);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          children: [
            Text(c.displayName, style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.md),
            PanelCard(
              child: Column(
                children: [
                  KvRow(
                    'Status',
                    c.online == true
                        ? 'Online'
                        : c.online == false
                        ? 'Offline'
                        : 'Unknown (no live observation)',
                  ),
                  KvRow('IP address', c.ip ?? 'Not reported'),
                  KvRow('MAC address', c.mac),
                  KvRow('Connection', switch (c.connectionType) {
                    'wifi' => 'Wi-Fi',
                    'wired' => 'Wired',
                    _ => 'Unknown',
                  }),
                  if (c.hostname != null && c.hostname != c.displayName)
                    KvRow('Hostname', c.hostname!),
                  KvRow(
                    'Current rate',
                    c.online == true && c.downBitsPerSec != null
                        ? '↓ ${formatBitRate(c.downBitsPerSec!)} · ↑ ${formatBitRate(c.upBitsPerSec ?? 0)}'
                        : 'Not available',
                  ),
                  KvRow(
                    'Observed',
                    c.lastSeen == null ? 'Not recorded' : formatAge(c.lastSeen),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              estimated ? 'Estimated usage' : 'Usage',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(
              estimated
                  ? 'Integrated from router rates Argon\'s observer samples '
                        'every ~10 s. Not a metered total; coverage shows how '
                        'much of each day was observed.'
                  : 'As reported by Argon.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.sm),
            if (c.days.isEmpty)
              Text(
                'No usage recorded for this device.',
                style: theme.textTheme.bodySmall,
              )
            else
              PanelCard(
                child: Column(
                  children: [
                    for (final d in c.days.reversed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(d.day)),
                                Text(
                                  d.totalBytes == null
                                      ? 'Not observed'
                                      : '${estimated ? '≈ ' : ''}${formatBytes(d.totalBytes!)}',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: (d.totalBytes ?? 0) / maxDay,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (d.downloadBytes != null)
                                  '↓ ${formatBytes(d.downloadBytes!)}',
                                if (d.uploadBytes != null)
                                  '↑ ${formatBytes(d.uploadBytes!)}',
                                coverageLabel(d.coverage),
                              ].join(' · '),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Space.md),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: c.mac)),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy MAC address'),
            ),
          ],
        ),
      );
    },
  );
}
