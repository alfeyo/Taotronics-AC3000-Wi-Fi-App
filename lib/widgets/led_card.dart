import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final result = await provider.updateNodeLed(nodeSn: sn, led: on ? 1 : 0);
    if (mounted) showSaveResult(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final entry = provider.mainRouterLed;
    final sn = entry == null ? null : '${entry['NodeSn']}';
    final on = entry == null ? null : RouterProvider.isLedOn(entry);
    // Shared with the Home hero: a change started there shows here as pending.
    final requested = sn == null ? null : provider.ledRequested(sn);
    final pending = requested != null;
    final count = provider.ledNodes.length;

    final status = !provider.isConnected
        ? 'Connect to the router to change'
        : pending
        ? 'Turning ${requested == 1 ? 'on' : 'off'}…'
        : on == null
        ? (provider.ledsLoaded
              ? 'Router reported no LED'
              : 'LED state not reported yet')
        : [on ? 'On' : 'Off', if (count > 1) '$count mesh nodes'].join(' · ');

    return PanelCard(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.sm,
        Space.md,
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NodeLedSettingsScreen()),
      ),
      child: Row(
        children: [
          IconBadge(
            on == true
                ? Icons.lightbulb_rounded
                : Icons.lightbulb_outline_rounded,
            tone: on == true ? Tone.accent : Tone.neutral,
            size: 40,
            round: true,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Router LED', style: theme.textTheme.titleSmall),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          if (pending)
            const Padding(
              padding: EdgeInsets.all(Space.md),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          Semantics(
            label: 'Main router LED',
            toggled: on ?? false,
            child: Switch(
              activeTrackColor: Palette.amber,
              value: pending ? requested == 1 : (on ?? false),
              onChanged:
                  on == null ||
                      sn == null ||
                      !provider.isConnected ||
                      provider.ledBusy
                  ? null
                  : (value) => _set(provider, sn, value),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: muted),
        ],
      ),
    );
  }
}
