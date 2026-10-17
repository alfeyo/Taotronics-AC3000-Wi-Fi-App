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
      tooltip: 'Sort: ${_sort.label}',
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
      child: const Padding(
        padding: EdgeInsets.all(Space.sm),
        child: Icon(Icons.sort_rounded),
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
                      120,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageHeader(
                          kicker: 'Network clients',
                          title: 'Devices',
                          subtitle: provider.isConnected
                              ? 'Updated ${formatAge(provider.devicesUpdatedAt)}'
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
                        _Summary(
                          total: all.length,
                          online: online,
                          active: active,
                        ),
                        const SizedBox(height: Space.md),
                        SearchBar(
                          controller: _search,
                          hintText: 'Search name, IP or MAC',
                          leading: const Icon(Icons.search_rounded),
                          elevation: const WidgetStatePropertyAll(0),
                          constraints: const BoxConstraints(minHeight: 48),
                          trailing: [
                            if (_search.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear search',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            sortMenu,
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final filter in DeviceFilter.values)
                              ChoiceChip(
                                label: Text(
                                  '${filter.label} '
                                  '${all.where(filter.matches).length}',
                                ),
                                visualDensity: VisualDensity.compact,
                                showCheckmark: false,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                labelStyle: theme.textTheme.labelMedium
                                    ?.copyWith(
                                      color: _filter == filter
                                          ? theme
                                                .chipTheme
                                                .secondaryLabelStyle
                                                ?.color
                                          : null,
                                    ),
                                selected: _filter == filter,
                                onSelected: (_) =>
                                    setState(() => _filter = filter),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Your devices',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'by ${_sort.label.toLowerCase()}',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.sm),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xl),
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
                          PanelCard(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.xs,
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < visible.length; i++) ...[
                                  if (i > 0)
                                    const Divider(
                                      height: 1,
                                      indent: 72,
                                      endIndent: Space.lg,
                                    ),
                                  _DeviceTile(
                                    device: visible[i],
                                    onTap: () =>
                                        showDeviceDetails(context, visible[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
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

/// Total / online / active counts in one compact card.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.online,
    required this.active,
  });

  final int total;
  final int online;
  final int active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String value, String label, Color? dot) => Expanded(
      child: Semantics(
        container: true,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: theme.textTheme.headlineSmall),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (dot != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final divider = SizedBox(
      height: 36,
      child: VerticalDivider(width: 1, color: theme.dividerColor),
    );
    return PanelCard(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Row(
        children: [
          cell('$total', 'Total', null),
          divider,
          cell('$online', 'Online', context.tone(Tone.success).foreground),
          divider,
          cell('$active', 'Active', theme.colorScheme.primary),
        ],
      ),
    );
  }
}

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
        : 'Seen ${formatAge(d.lastSeen)}';
    final statusColor = d.isOnline
        ? context.tone(Tone.success).foreground
        : muted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.md,
        ),
        child: Row(
          children: [
            IconBadge(
              _linkIcon(d.link),
              tone: d.isOnline ? Tone.brand : Tone.neutral,
              size: 40,
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
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      d.ipAddress ?? d.mac,
                      if (d.link != DeviceLink.unknown) _linkLabel(d.link),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      d.isOnline ? 'Idle' : status,
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
