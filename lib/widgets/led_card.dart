import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/save_result.dart';
import '../providers/router_provider.dart';
import '../screens/router_settings_screens.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';
import 'feedback.dart';

/// Main-router LED switch backed by GetLedList / SetNodeLed, plus a link to
/// the per-node LED screen. Shows the state the router reports, never an
/// assumed one.
class RouterLedCard extends StatefulWidget {
  const RouterLedCard({super.key});

  @override
  State<RouterLedCard> createState() => _RouterLedCardState();
}

class _RouterLedCardState extends State<RouterLedCard> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RouterProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && provider.isConnected && !provider.ledsLoaded) {
        provider.refreshLeds();
      }
    });
  }

  Future<void> _set(RouterProvider provider, String sn, bool on) async {
    setState(() => _saving = true);
    final result = await provider.updateNodeLed(nodeSn: sn, led: on ? 1 : 0);
    if (!mounted) return;
    setState(() => _saving = false);
    showSaveResult(
      context,
      result.isConfirmed
          ? SaveResult.confirmed(
              on ? 'Router LED turned on.' : 'Router LED turned off.',
            )
          : result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final entry = provider.mainRouterLed;
    final sn = entry == null ? null : '${entry['NodeSn']}';
    final on = entry == null ? null : RouterProvider.isLedOn(entry);
    final count = provider.ledNodes.length;
    final master = provider.nodes.where((n) => n.isMaster).firstOrNull;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                Icons.lightbulb_outline_rounded,
                tone: on == true ? Tone.accent : Tone.neutral,
                size: 44,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Router LEDs', style: theme.textTheme.titleMedium),
                    Text(
                      count > 1
                          ? 'Lights on your $count mesh nodes'
                          : 'Indicator light on your router',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: Space.xl),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Main router', style: theme.textTheme.titleSmall),
                    Text(
                      !provider.isConnected
                          ? 'Connect to the router to change'
                          : on == null
                          ? (provider.ledsLoaded
                                ? 'Router reported no LED'
                                : 'LED state not reported yet')
                          : [
                              if (master?.model != null) master!.model!,
                              on ? 'LED on' : 'LED off',
                            ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(Space.md),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else
                Semantics(
                  label: 'Main router LED',
                  toggled: on ?? false,
                  child: Switch(
                    value: on ?? false,
                    onChanged: on == null || sn == null || !provider.isConnected
                        ? null
                        : (value) => _set(provider, sn, value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          PillButton(
            label: 'View all LED settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NodeLedSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
