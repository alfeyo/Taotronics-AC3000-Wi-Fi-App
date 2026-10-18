import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../services/pi_api.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/home_widgets.dart';
import '../widgets/pi_board.dart';

/// Argon (Raspberry Pi gateway): the companion of My Router. Connection is
/// automatic (PiProvider); this screen only shows the Pi and its measurements.
class PiGatewayScreen extends StatelessWidget {
  const PiGatewayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final router = context.watch<RouterProvider>();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: pi.reconnect,
          child: ListView(
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
                    _Header(pi: pi, router: router),
                    const SizedBox(height: Space.md),
                    _Hero(pi: pi),
                    const SizedBox(height: Space.lg),
                    _SyncCard(pi: pi, router: router),
                    if (pi.connected || pi.gateway != null) ...[
                      const SizedBox(height: Space.lg),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _Traffic(pi: pi)),
                            const SizedBox(width: Space.lg),
                            Expanded(child: _System(pi: pi)),
                          ],
                        )
                      else ...[
                        _Traffic(pi: pi),
                        const SizedBox(height: Space.lg),
                        _System(pi: pi),
                      ],
                      const SizedBox(height: Space.lg),
                      _History(pi: pi),
                      const SizedBox(height: Space.lg),
                      _Events(pi: pi),
                    ],
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

String _linkLine(PiProvider pi) {
  return switch (pi.state) {
    PiLinkState.connected => 'Connected · ${pi.transportKind!.label}',
    PiLinkState.unreachable => 'Unreachable · retrying automatically',
    _ => 'Looking for Argon…',
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = pi.connected
        ? Tone.success
        : pi.state == PiLinkState.unreachable
        ? Tone.warning
        : Tone.neutral;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gateway',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: context.tone(tone).foreground,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _linkLine(pi),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        EventsButton(provider: router),
        const SizedBox(width: Space.sm),
        HeaderIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Manage connection',
          onPressed: () => showManageConnection(context),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = pi.gatewayInfo;
    final up = (g?['upstream'] as Map?) ?? const {};
    final vpn = (g?['vpn'] as Map?) ?? const {};
    final fresh = pi.gatewayFresh;
    final online = up['online'];
    final vpnState = vpn['state'] as String?;
    final model =
        (g?['model'] as String?)?.replaceAll(RegExp(r'\s+Rev\s+[\d.]+$'), '') ??
        'Raspberry Pi gateway';
    return Column(
      children: [
        SizedBox(
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.62,
                      colors: [
                        (pi.connected
                                ? Palette.amber
                                : theme.colorScheme.primary)
                            .withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                image: true,
                label:
                    'Raspberry Pi gateway, ${pi.connected ? 'connected' : 'not connected'}',
                child: PiBoard(
                  active: pi.connected,
                  dim: !pi.connected,
                  size: 250,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Argon',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          model,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            StatusPill(
              label: pi.connected
                  ? pi.transportKind!.label
                  : pi.state == PiLinkState.unreachable
                  ? 'Unreachable'
                  : 'Searching',
              tone: pi.connected
                  ? Tone.success
                  : pi.state == PiLinkState.unreachable
                  ? Tone.warning
                  : Tone.neutral,
              icon: switch (pi.transportKind) {
                PiTransportKind.bluetooth => Icons.bluetooth_rounded,
                PiTransportKind.tailscale => Icons.vpn_lock_rounded,
                _ => Icons.lan_rounded,
              },
            ),
            if (fresh && online != null)
              StatusPill(
                label: online == true ? 'Internet online' : 'No internet',
                tone: online == true ? Tone.success : Tone.danger,
              ),
            if (fresh && vpnState != null)
              StatusPill(
                label: vpnState == 'connected'
                    ? 'VPN protected'
                    : 'VPN $vpnState',
                tone: vpnState == 'connected'
                    ? Tone.success
                    : (vpn['mode'] == 'off' ? Tone.neutral : Tone.warning),
                icon: Icons.shield_rounded,
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        PanelCard(
          child: Column(
            children: [
              _Row(
                'Internet source',
                up['ssid'] != null
                    ? '${up['ssid']} · ${up['interface'] ?? ''}'
                    : (up['interface'] as String?) ?? '—',
              ),
              _Row(
                'VPN',
                vpnState == null
                    ? '—'
                    : [
                        vpnState == 'connected' ? 'Connected' : vpnState,
                        if (vpn['location'] != null) vpn['location'],
                      ].join(' · '),
              ),
              _Row(
                'Uptime',
                g?['uptimeSeconds'] is num
                    ? formatUptime((g!['uptimeSeconds'] as num).round())
                    : '—',
              ),
              _Row(
                'Last contact',
                pi.lastContact == null ? 'Never' : formatAge(pi.lastContact),
                last: true,
              ),
              if (!pi.connected && pi.lastError != null) ...[
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pi.lastError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    PillButton(
                      label: 'Retry',
                      icon: Icons.refresh_rounded,
                      onPressed: pi.reconnect,
                    ),
                  ],
                ),
              ],
              if (pi.gateway != null && !fresh)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Showing the last data received ${formatAge(pi.gatewayAt)}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.tone(Tone.warning).foreground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
            ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatefulWidget {
  const _SyncCard({required this.pi, required this.router});
  final PiProvider pi;
  final RouterProvider router;

  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _open = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.pi.pair(
        _code.text,
        deviceName:
            'TT Router · ${widget.router.currentRouter?.displayName ?? 'phone'}',
      );
      _code.clear();
      if (mounted) setState(() => _open = false);
    } on PiApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pi = widget.pi;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (pi.paired) {
      final status = !pi.syncEnabled
          ? 'Synchronization is off'
          : pi.sharedAt != null &&
                DateTime.now().difference(pi.sharedAt!).inSeconds < 60
          ? 'Shared ${pi.sharedCount ?? 0} router device${pi.sharedCount == 1 ? '' : 's'} ${formatAge(pi.sharedAt)}'
          : pi.syncError ?? 'Waiting to share router devices';
      return PanelCard(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.sm,
          Space.md,
        ),
        child: Row(
          children: [
            IconBadge(
              Icons.sync_rounded,
              tone: pi.syncActive && pi.syncError == null
                  ? Tone.success
                  : Tone.neutral,
              size: 40,
              round: true,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device synchronization',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Switch(value: pi.syncEnabled, onChanged: pi.setSyncEnabled),
          ],
        ),
      );
    }
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(
                Icons.devices_rounded,
                tone: Tone.accent,
                size: 40,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pi.credentialRejected
                          ? 'Pair again to resume sharing'
                          : 'Enable device synchronization',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      'Share your router\'s connected devices with Argon while the app is open.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (!_open)
                PillButton(
                  label: 'Set up',
                  onPressed: pi.connected
                      ? () => setState(() => _open = true)
                      : null,
                ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: Space.md),
            Text(
              'On Argon open Devices → Pair TT Router app, then enter the 6-digit code.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _pair(),
                  ),
                ),
                const SizedBox(width: Space.sm),
                PillButton(
                  label: _busy ? 'Pairing…' : 'Pair',
                  primary: true,
                  onPressed: _busy ? null : _pair,
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.tone(Tone.danger).foreground,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Traffic extends StatelessWidget {
  const _Traffic({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = pi.today;
    final down = (today?['downloadBytes'] as num?)?.toInt();
    final up = (today?['uploadBytes'] as num?)?.toInt();
    final vpn =
        ((today?['vpnDownloadBytes'] as num?) ?? 0) +
        ((today?['vpnUploadBytes'] as num?) ?? 0);
    final total = down == null || up == null ? null : down + up;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Household traffic'),
        Row(
          children: [
            Expanded(
              child: SparkCard(
                label: 'Download',
                icon: Icons.south_rounded,
                tone: Tone.brand,
                value: pi.householdDownBytesPerSec == null
                    ? null
                    : formatRate(pi.householdDownBytesPerSec!),
                samples: [for (final s in pi.liveSamples) s.down],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: SparkCard(
                label: 'Upload',
                icon: Icons.north_rounded,
                tone: Tone.accent,
                value: pi.householdUpBytesPerSec == null
                    ? null
                    : formatRate(pi.householdUpBytesPerSec!),
                samples: [for (final s in pi.liveSamples) s.up],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        PanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      total == null ? '—' : formatBytes(total),
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      total == null
                          ? ''
                          : '↓ ${formatBytes(down!)} · ↑ ${formatBytes(up!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Through VPN',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    total == null || total == 0
                        ? '—'
                        : '${(vpn / total * 100).round()}%',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Measured by Argon where traffic enters your router (eth1) · ${pi.liveFresh ? 'live' : 'not current'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _System extends StatelessWidget {
  const _System({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final g = pi.gatewayInfo;
    final cpu = g?['cpuPercent'];
    final temp = g?['temperatureC'];
    final mem = (g?['memory'] as Map?)?['usedPercent'];
    final throttled = g?['activeThrottling'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Raspberry Pi'),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.memory_rounded,
                value: cpu is num ? '${cpu.round()}%' : null,
                label: 'CPU',
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: StatTile(
                icon: Icons.thermostat_rounded,
                value: temp is num ? '${temp.toStringAsFixed(0)}°C' : null,
                label: 'Temp',
                tone: temp is num && temp >= 75
                    ? Tone.danger
                    : temp is num && temp >= 65
                    ? Tone.warning
                    : Tone.brand,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.sd_storage_rounded,
                value: mem is num ? '${mem.round()}%' : null,
                label: 'Memory',
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: StatTile(
                icon: Icons.bolt_rounded,
                value: throttled == null
                    ? null
                    : throttled == true
                    ? 'Active'
                    : 'None',
                label: 'Throttling',
                tone: throttled == true ? Tone.danger : Tone.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days =
        ((pi.gateway?['history'] as Map?)?['days'] as List?)
            ?.whereType<Map>()
            .toList() ??
        const [];
    final recent = days.length > 14 ? days.sublist(days.length - 14) : days;
    num total(Map d) =>
        ((d['downloadBytes'] as num?) ?? 0) + ((d['uploadBytes'] as num?) ?? 0);
    final max = recent.isEmpty
        ? 1
        : recent
              .map(total)
              .reduce((a, b) => a > b ? a : b)
              .clamp(1, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Daily usage'),
        PanelCard(
          child: recent.isEmpty
              ? Text(
                  'No measured history yet.',
                  style: theme.textTheme.bodyMedium,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 120,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final d in recent)
                            Expanded(
                              child: Tooltip(
                                message:
                                    '${d['day']}: ${d['measured'] == true ? formatBytes(total(d).toInt()) : 'not measured'}',
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: FractionallySizedBox(
                                    heightFactor: d['measured'] == true
                                        ? (total(d) / max)
                                              .clamp(0.02, 1.0)
                                              .toDouble()
                                        : 0.02,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: d['measured'] == true
                                            ? Palette.amber.withValues(
                                                alpha: 0.85,
                                              )
                                            : theme.colorScheme.outlineVariant,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(4),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${recent.first['day']}'.substring(5),
                          style: theme.textTheme.labelSmall,
                        ),
                        Text('Today', style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Measured household totals per day (local calendar). Grey = not measured.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.pi});
  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = pi.events.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Recent gateway events'),
        PanelCard(
          child: events.isEmpty
              ? Text(
                  'No VPN, uplink or monitoring changes observed.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final e in events)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          e.severity == 'warning' || e.severity == 'error'
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline_rounded,
                          color: context
                              .tone(
                                e.severity == 'warning' || e.severity == 'error'
                                    ? Tone.warning
                                    : Tone.info,
                              )
                              .foreground,
                        ),
                        title: Text(e.title),
                        subtitle: Text('${e.message} · ${formatAge(e.at)}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Advanced connection details and settings, out of the main flow.
Future<void> showManageConnection(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => const _ManageSheet(),
  );
}

class _ManageSheet extends StatefulWidget {
  const _ManageSheet();

  @override
  State<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<_ManageSheet> {
  final _manual = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _manual.text = context.read<PiProvider>().manualEndpoint?.toString() ?? '';
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _toggleBluetooth(PiProvider pi, bool value) async {
    if (value) {
      final status = await Permission.bluetoothConnect.request();
      if (!status.isGranted) {
        setState(
          () => _error =
              'Bluetooth permission was not granted; the fallback stays off.',
        );
        return;
      }
    }
    await pi.setBluetoothFallback(value);
  }

  @override
  Widget build(BuildContext context) {
    final pi = context.watch<PiProvider>();
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          Space.lg,
          0,
          Space.lg,
          Space.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Text('Gateway connection', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.md),
          PanelCard(
            child: Column(
              children: [
                _Row('Status', _linkLine(pi)),
                _Row(
                  'Route',
                  pi.connected
                      ? '${pi.transportKind!.label} · ${pi.transport!.describe}'
                      : '—',
                ),
                _Row(
                  'Trusted Argon',
                  pi.trustedId == null
                      ? 'Not yet'
                      : '${pi.trustedId!.substring(0, 8)}…',
                ),
                _Row(
                  'Order tried',
                  'Local 192.168.50.1 → Tailscale 100.94.137.17${pi.manualEndpoint != null ? ' → ${pi.manualEndpoint!.host}' : ''}${pi.bluetoothFallback ? ' → Bluetooth' : ''}',
                ),
                _Row(
                  'Synchronization',
                  pi.paired
                      ? (pi.pairedName ?? 'Paired')
                      : pi.credentialRejected
                      ? 'Pairing revoked'
                      : 'Not paired',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bluetooth fallback'),
            subtitle: Text(
              pi.bluetoothAddress == null
                  ? 'Available after Argon has been reached once over the network.'
                  : 'Read-only monitoring over Bluetooth when no network route works. Requires pairing.',
            ),
            value: pi.bluetoothFallback,
            onChanged: pi.bluetoothAddress == null
                ? null
                : (v) => _toggleBluetooth(pi, v),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _manual,
            decoration: const InputDecoration(
              labelText: 'Additional address (optional)',
              hintText: 'https://… or http://<private IP>',
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              PillButton(
                label: 'Save address',
                onPressed: () async {
                  try {
                    await pi.setManualEndpoint(_manual.text);
                    setState(() => _error = null);
                  } on FormatException catch (e) {
                    setState(() => _error = e.message);
                  }
                },
              ),
              const SizedBox(width: Space.sm),
              PillButton(
                label: 'Retry now',
                icon: Icons.refresh_rounded,
                onPressed: pi.reconnect,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.tone(Tone.danger).foreground,
                ),
              ),
            ),
          const SizedBox(height: Space.lg),
          if (pi.trustedId != null || pi.paired)
            PillButton(
              label: 'Forget this Argon',
              icon: Icons.link_off_rounded,
              onPressed: () async {
                await pi.forget();
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}
