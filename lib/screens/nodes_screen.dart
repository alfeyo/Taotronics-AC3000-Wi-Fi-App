import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_entity.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/connection_banner.dart';

class NodesScreen extends StatelessWidget {
  const NodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final nodes = [...provider.nodes]
      ..sort((a, b) => a.isMaster == b.isMaster ? 0 : (a.isMaster ? -1 : 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh nodes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: provider.isConnected ? provider.refreshNodes : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refreshNodes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.xxl,
          ),
          children: [
            const ConnectionStatusBanners(),
            if (nodes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: EmptyState(
                  icon: Icons.hub_outlined,
                  title: 'No mesh nodes reported',
                  message: 'Pull down to refresh once the router is connected.',
                ),
              )
            else ...[
              Text(
                '${nodes.where((n) => n.isOnline).length} of ${nodes.length} '
                'online · updated ${formatAge(provider.nodesUpdatedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.sm),
              for (final node in nodes)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: ContentWidth(
                    child: _NodeCard(
                      node: node,
                      ledOn: provider.ledNodes
                          .where((l) => '${l['NodeSn']}' == node.sn)
                          .map(RouterProvider.isLedOn)
                          .firstOrNull,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, this.ledOn});

  final NodeEntity node;

  /// LED state from GetLedList; null when not reported for this node.
  final bool? ledOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = <(IconData, String, String)>[
      (Icons.devices_rounded, 'Clients', '${node.connectedDevices}'),
      if (node.uptimeSeconds > 0)
        (Icons.timer_outlined, 'Uptime', formatUptime(node.uptimeSeconds)),
      if (node.model != null) (Icons.memory_rounded, 'Model', node.model!),
      if (node.firmwareVersion != null)
        (Icons.system_update_alt_rounded, 'Firmware', node.firmwareVersion!),
      if (node.ipAddress != null) (Icons.lan_rounded, 'IP', node.ipAddress!),
      if (ledOn != null)
        (Icons.lightbulb_outline_rounded, 'LED', ledOn! ? 'On' : 'Off'),
    ];

    return PanelCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  Icons.router_rounded,
                  tone: node.isOnline ? Tone.success : Tone.neutral,
                  size: 52,
                  round: true,
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        children: [
                          StatusPill(
                            label: node.isOnline ? 'Online' : 'Offline',
                            tone: node.isOnline ? Tone.success : Tone.danger,
                          ),
                          StatusPill(
                            label: node.isMaster ? 'Main router' : 'Satellite',
                            tone: Tone.brand,
                            dot: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Only draw signal bars when the router reported a value.
                if (node.isOnline && node.signalStrength > 0)
                  _SignalBars(node.signalStrength),
              ],
            ),
            const SizedBox(height: Space.lg),
            Wrap(
              spacing: Space.xl,
              runSpacing: Space.md,
              children: [
                for (final (icon, label, value) in facts)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.xs),
                      Text(
                        '$label ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(value, style: theme.textTheme.labelLarge),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Serial ${node.sn}'
              '${node.wiredBackhaul == null ? '' : ' · LocalConn ${node.wiredBackhaul! ? 1 : 0}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars(this.strength);

  final int strength;

  @override
  Widget build(BuildContext context) {
    final bars = (strength / 25).ceil().clamp(1, 4);
    final active = context.tone(Tone.success).foreground;
    final inactive = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: 'Signal $bars of 4',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          return Container(
            width: 4,
            height: 8.0 + (index * 4),
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: index < bars ? active : inactive,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
