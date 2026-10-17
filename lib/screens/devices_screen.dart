import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/device_entity.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';

enum DeviceFilter {
  all('All'),
  online('Online'),
  active('Active'),
  offline('Offline');

  const DeviceFilter(this.label);
  final String label;

  bool matches(DeviceEntity d) => switch (this) {
    DeviceFilter.all => true,
    DeviceFilter.online => d.isOnline,
    DeviceFilter.active => d.isActive,
    DeviceFilter.offline => !d.isOnline,
  };
}

enum DeviceSort {
  name('Name'),
  activity('Current activity'),
  ip('IP address'),
  recent('Recently connected');

  const DeviceSort(this.label);
  final String label;
}

/// Sorting used by the devices list; exposed for tests.
List<DeviceEntity> sortDevices(List<DeviceEntity> devices, DeviceSort sort) {
  int byName(DeviceEntity a, DeviceEntity b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  int byActivity(DeviceEntity a, DeviceEntity b) {
    final rate = (b.uploadSpeed + b.downloadSpeed).compareTo(
      a.uploadSpeed + a.downloadSpeed,
    );
    return rate != 0 ? rate : byName(a, b);
  }

  final sorted = [...devices];
  sorted.sort(
    (a, b) => switch (sort) {
      DeviceSort.name => byName(a, b),
      DeviceSort.activity => byActivity(a, b),
      DeviceSort.ip => _ipKey(a.ipAddress).compareTo(_ipKey(b.ipAddress)),
      DeviceSort.recent =>
        (b.connectedSince?.millisecondsSinceEpoch ?? 0).compareTo(
          a.connectedSince?.millisecondsSinceEpoch ?? 0,
        ),
    },
  );
  return sorted;
}

int _ipKey(String? ip) {
  final parts = ip?.split('.').map(int.tryParse).toList();
  if (parts == null || parts.length != 4 || parts.contains(null)) {
    return 1 << 32;
  }
  return parts.fold<int>(0, (sum, p) => sum * 256 + p!);
}

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _search = TextEditingController();
  DeviceFilter _filter = DeviceFilter.all;
  DeviceSort _sort = DeviceSort.name;

  // Live polling keeps refreshing the device list while this screen is open,
  // so device rates stay current. The extra refresh fills the list at once.
  @override
  void initState() {
    super.initState();
    final p = context.read<RouterProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) p.refreshDevices();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final theme = Theme.of(context);
    final query = _search.text.trim().toLowerCase();
    final all = provider.devices;
    final visible = sortDevices(
      all
          .where(_filter.matches)
          .where((d) => query.isEmpty || d.searchText.contains(query))
          .toList(),
      _sort,
    );
    final online = all.where((d) => d.isOnline).length;
    final active = all.where((d) => d.isActive).length;

    final sortMenu = PopupMenuButton<DeviceSort>(
      tooltip: 'Sort',
      initialValue: _sort,
      onSelected: (sort) => setState(() => _sort = sort),
      itemBuilder: (context) => [
        for (final sort in DeviceSort.values)
          CheckedPopupMenuItem(
            value: sort,
            checked: sort == _sort,
            child: Text(sort.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SORT',
              style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1),
            ),
            const SizedBox(width: Space.xs),
            const Icon(Icons.sort_rounded, size: 18),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: provider.refreshDevices,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.lg,
                      Space.lg,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageHeader(
                          kicker: 'Network clients',
                          title: 'Devices',
                          subtitle: provider.isConnected
                              ? '$online connected · ${all.length - online} offline'
                              : 'Connect to the router to see devices',
                          trailing: IconButton(
                            tooltip: 'Refresh',
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: provider.isConnected
                                ? provider.refreshDevices
                                : null,
                          ),
                        ),
                        const SizedBox(height: Space.lg),
                        const ConnectionStatusBanners(),
                        SearchBar(
                          controller: _search,
                          hintText: 'Search name, IP or MAC',
                          leading: const Icon(Icons.search_rounded),
                          elevation: const WidgetStatePropertyAll(0),
                          trailing: [
                            if (_search.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear search',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.md),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final filter in DeviceFilter.values)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: Space.sm,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(
                                      '${filter.label} '
                                      '${all.where(filter.matches).length}',
                                    ),
                                    selected: _filter == filter,
                                    onSelected: (_) =>
                                        setState(() => _filter = filter),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Your devices',
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            sortMenu,
                          ],
                        ),
                        Text(
                          provider.isConnected
                              ? '$active active now · sorted by '
                                    '${_sort.label.toLowerCase()} · updated '
                                    '${formatAge(provider.devicesUpdatedAt)}'
                              : 'Device data appears once the router is connected.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Space.md),
                      ],
                    ),
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: all.isEmpty
                        ? Icons.devices_other_rounded
                        : Icons.search_off_rounded,
                    title: all.isEmpty
                        ? (provider.isConnected
                              ? 'No devices reported yet'
                              : 'Not connected')
                        : 'No devices match',
                    message: all.isEmpty
                        ? 'Pull down to refresh.'
                        : 'Try another filter or search term.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    120,
                  ),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Space.md),
                    itemBuilder: (context, i) => ContentWidth(
                      child: _DeviceTile(
                        device: visible[i],
                        onTap: () => showDeviceDetails(context, visible[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _linkIcon(DeviceLink link) => switch (link) {
  DeviceLink.wired => Icons.settings_ethernet_rounded,
  DeviceLink.wireless => Icons.wifi_rounded,
  DeviceLink.unknown => Icons.device_unknown_rounded,
};

String _linkLabel(DeviceLink link) => switch (link) {
  DeviceLink.wired => 'Wired',
  DeviceLink.wireless => 'Wi-Fi',
  DeviceLink.unknown => 'Link unknown',
};

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final DeviceEntity device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final d = device;
    final status = d.isOnline
        ? (d.isActive ? 'Active' : 'Online')
        : d.lastSeen == null
        ? 'Offline'
        : 'Offline · seen ${formatAge(d.lastSeen)}';
    final statusColor = d.isOnline
        ? context.tone(Tone.success).foreground
        : muted;

    return PanelCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, 20, Space.lg),
      child: Row(
        children: [
          IconBadge(
            d.link == DeviceLink.wired
                ? Icons.lan_rounded
                : Icons.devices_other_rounded,
            tone: d.isOnline
                ? (d.link == DeviceLink.wired ? Tone.success : Tone.brand)
                : Tone.neutral,
            size: 46,
            round: true,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (d.link != DeviceLink.unknown) _linkLabel(d.link),
                    d.ipAddress ?? d.mac,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          if (d.isActive)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Rate(Icons.south_rounded, d.downloadSpeed, Tone.brand),
                const SizedBox(height: 2),
                _Rate(Icons.north_rounded, d.uploadSpeed, Tone.accent),
              ],
            )
          else if (d.isOnline)
            Text('Idle', style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate(this.icon, this.rate, this.tone);

  final IconData icon;
  final int rate;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.tone(tone).foreground),
        const SizedBox(width: 2),
        Text(formatRate(rate), style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Bottom sheet with everything the router reports about [device].
Future<void> showDeviceDetails(BuildContext context, DeviceEntity device) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _DeviceDetails(device: device, controller: controller),
    ),
  );
}

class _DeviceDetails extends StatelessWidget {
  const _DeviceDetails({required this.device, required this.controller});

  final DeviceEntity device;
  final ScrollController controller;

  String _time(DateTime? t) {
    if (t == null) return 'Not reported';
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)} (${formatAge(t)})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = device;
    final rows = <(String, String, bool)>[
      ('IP address', d.ipAddress ?? 'Not reported', true),
      ('MAC address', d.mac.isEmpty ? 'Not reported' : d.mac, true),
      ('Host name', d.hostName ?? 'Not reported', false),
      if (d.nickName != null) ('Nickname', d.nickName!, false),
      (
        'Connection',
        d.link == DeviceLink.unknown
            ? 'Not reported (type ${d.raw['ClientType'] ?? '—'})'
            : '${_linkLabel(d.link)} (inferred from router client type)',
        false,
      ),
      ('Download now', d.isOnline ? formatRate(d.downloadSpeed) : '—', false),
      ('Upload now', d.isOnline ? formatRate(d.uploadSpeed) : '—', false),
      ('Connected since', d.isOnline ? _time(d.connectedSince) : '—', false),
      ('Last seen', _time(d.lastSeen), false),
      ('First seen', _time(d.firstSeen), false),
      (
        'Data usage',
        d.hasByteCounters
            ? '${formatBytes(d.downBytes)} down · ${formatBytes(d.upBytes)} up'
            : 'Not reported by this router',
        false,
      ),
    ];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xxl),
      children: [
        Row(
          children: [
            IconBadge(
              _linkIcon(d.link),
              tone: d.isOnline ? Tone.info : Tone.neutral,
              size: 52,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.displayName, style: theme.textTheme.titleLarge),
                  const SizedBox(height: Space.xs),
                  StatusPill(
                    label: d.isActive
                        ? 'Active'
                        : d.isOnline
                        ? 'Online'
                        : 'Offline',
                    tone: d.isOnline ? Tone.success : Tone.neutral,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        for (final (label, value, copyable) in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            subtitle: Text(value, style: theme.textTheme.bodyLarge),
            trailing: copyable && !value.startsWith('Not')
                ? IconButton(
                    tooltip: 'Copy $label',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$label copied')));
                    },
                  )
                : null,
          ),
        const SizedBox(height: Space.sm),
        Card(
          child: ExpansionTile(
            title: const Text('All router fields'),
            subtitle: const Text('Raw values from GetDevListInfo'),
            shape: const Border(),
            collapsedShape: const Border(),
            children: [
              for (final entry in d.raw.entries)
                ListTile(
                  dense: true,
                  title: Text(entry.key),
                  trailing: Text(
                    '${entry.value}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
