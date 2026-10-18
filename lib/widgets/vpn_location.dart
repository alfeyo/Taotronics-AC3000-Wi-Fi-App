import 'package:flutter/material.dart';

import '../providers/pi_provider.dart';
import '../services/argon_status.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// Current VPN exit location with the "Change location" control. Every
/// location shown comes from Argon's `/api/v1/vpn/locations`.
class VpnLocationTile extends StatelessWidget {
  const VpnLocationTile({super.key, required this.pi, required this.onChange});

  final PiProvider pi;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final locs = pi.vpnLocations;
    final vpn = pi.vpn;
    final current = locs?.current;
    final label =
        current?.label ??
        vpn?.location ??
        (pi.vpnLocationsLoading ? 'Checking…' : 'Location not reported');
    final offLocked = locs != null && locs.vpnOff && !locs.canSwitchWhileOff;
    final busy =
        pi.locationInFlight ||
        pi.vpnInFlight ||
        pi.vpnPrompting ||
        locs?.busy == true ||
        vpn?.busy == true;
    final canChange = pi.connected && !busy && !offLocked;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(
                Icons.place_rounded,
                tone: Tone.info,
                size: 38,
                round: true,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locs?.vpnOff == true || vpn?.isOff == true
                          ? 'Exit location (used when VPN is on)'
                          : 'Exit location',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    Text(
                      label,
                      key: const ValueKey('vpn-current-location'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (current?.place != null)
                      Text(
                        current!.place!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Flexible(
                child: PillButton(
                  key: const ValueKey('vpn-change-location'),
                  label: 'Change location',
                  icon: Icons.travel_explore_rounded,
                  onPressed: canChange ? onChange : null,
                ),
              ),
            ],
          ),
          if (offLocked) ...[
            const SizedBox(height: Space.sm),
            Text(
              '$vpnLocationNeedsVpnOnMessage. Argon changes the exit location '
              'only while the VPN is on.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ] else if (pi.vpnLocationsError != null && locs == null) ...[
            const SizedBox(height: Space.sm),
            Text(
              pi.vpnLocationsError!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (pi.locationPhase != VpnCommandPhase.idle) ...[
            const SizedBox(height: Space.md),
            _LocationResult(pi: pi),
          ],
        ],
      ),
    );
  }
}

class _LocationResult extends StatelessWidget {
  const _LocationResult({required this.pi});

  final PiProvider pi;

  @override
  Widget build(BuildContext context) {
    final message = pi.locationMessage ?? '';
    switch (pi.locationPhase) {
      case VpnCommandPhase.idle:
        return const SizedBox.shrink();
      case VpnCommandPhase.sending:
      case VpnCommandPhase.verifying:
        return InfoBanner(
          tone: Tone.info,
          busy: true,
          title: pi.locationPhase == VpnCommandPhase.sending
              ? 'Sending to Argon…'
              : 'Waiting for confirmation…',
          message: message,
        );
      case VpnCommandPhase.confirmed:
        return InfoBanner(
          tone: Tone.success,
          icon: Icons.check_circle_rounded,
          title: message,
          onDismiss: pi.dismissLocationResult,
        );
      case VpnCommandPhase.failed:
        final issue = pi.locationIssue;
        final soft = {
          VpnCommandIssue.busy,
          VpnCommandIssue.unconfirmed,
          VpnCommandIssue.rateLimited,
          VpnCommandIssue.bluetooth,
          VpnCommandIssue.vpnOff,
        }.contains(issue);
        final permission = {
          VpnCommandIssue.tokenInvalid,
          VpnCommandIssue.needsToken,
          VpnCommandIssue.forbidden,
          VpnCommandIssue.keyChanged,
        }.contains(issue);
        return InfoBanner(
          tone: soft ? Tone.warning : Tone.danger,
          icon: Icons.error_outline_rounded,
          title: message,
          message: pi.locationRecovery,
          onDismiss: pi.dismissLocationResult,
          action: permission
              ? TextButton(
                  onPressed: pi.refreshVpnPermission,
                  child: const Text('Refresh permission'),
                )
              : issue == VpnCommandIssue.unknownLocation ||
                    issue == VpnCommandIssue.unconfirmed ||
                    issue == VpnCommandIssue.upstream
              ? TextButton(
                  onPressed: pi.refreshVpnLocations,
                  child: const Text('Refresh locations'),
                )
              : null,
        );
    }
  }
}

/// Searchable list of the exit locations Argon offers. Pops the chosen
/// [VpnLocation], or null.
class VpnLocationSheet extends StatefulWidget {
  const VpnLocationSheet({super.key, required this.pi});

  final PiProvider pi;

  @override
  State<VpnLocationSheet> createState() => _VpnLocationSheetState();
}

class _VpnLocationSheetState extends State<VpnLocationSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.pi.refreshVpnLocations(force: false);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return ListenableBuilder(
      listenable: widget.pi,
      builder: (context, _) {
        final pi = widget.pi;
        final locs = pi.vpnLocations;
        final offLocked =
            locs != null && locs.vpnOff && !locs.canSwitchWhileOff;
        final selectable = locs != null && locs.selectable;
        final items =
            locs?.locations.where((l) => l.matches(_query)).toList() ??
            const <VpnLocation>[];
        return SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.only(
              left: Space.xl,
              right: Space.xl,
              top: Space.sm,
              bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose exit location',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('vpn-locations-refresh'),
                      tooltip: 'Refresh locations',
                      onPressed: pi.vpnLocationsLoading
                          ? null
                          : pi.refreshVpnLocations,
                      icon: pi.vpnLocationsLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                Text(
                  locs?.current == null
                      ? 'Locations reported by Argon.'
                      : 'Locations reported by Argon · current: '
                            '${locs!.current!.label}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: Space.md),
                if (offLocked) ...[
                  const InfoBanner(
                    tone: Tone.warning,
                    icon: Icons.shield_outlined,
                    title: vpnLocationNeedsVpnOnMessage,
                    message:
                        'Argon changes the exit location only while the VPN '
                        'is on.',
                  ),
                  const SizedBox(height: Space.md),
                ] else if (locs?.busy == true) ...[
                  const InfoBanner(
                    tone: Tone.info,
                    busy: true,
                    title: 'A VPN change is already in progress on Argon.',
                  ),
                  const SizedBox(height: Space.md),
                ],
                if (pi.vpnLocationsError != null) ...[
                  InfoBanner(
                    tone: locs == null ? Tone.danger : Tone.warning,
                    icon: Icons.error_outline_rounded,
                    title: pi.vpnLocationsError!,
                    message: locs == null
                        ? null
                        : 'Showing the last list received.',
                  ),
                  const SizedBox(height: Space.md),
                ],
                TextField(
                  key: const ValueKey('vpn-location-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search country or city',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: Space.sm),
                Expanded(
                  child: locs == null
                      ? Center(
                          child: pi.vpnLocationsLoading
                              ? const CircularProgressIndicator()
                              : Text(
                                  'No location list yet. Tap refresh.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: muted,
                                  ),
                                ),
                        )
                      : items.isEmpty
                      ? Center(
                          child: Text(
                            locs.locations.isEmpty
                                ? 'Argon reported no locations.'
                                : 'No locations match "$_query".',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) => _LocationRow(
                            location: items[i],
                            current: items[i].id == locs.current?.id,
                            enabled: selectable,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.location,
    required this.current,
    required this.enabled,
  });

  final VpnLocation location;
  final bool current;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usable = enabled && location.available && !current;
    final details = [
      ?location.place,
      if (current) 'Current',
      if (!location.available) 'Unavailable',
    ].join(' · ');
    return Opacity(
      opacity: location.available ? 1 : 0.45,
      child: ListTile(
        key: ValueKey('vpn-location-${location.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
        enabled: usable,
        leading: Icon(
          current ? Icons.check_circle_rounded : Icons.public_rounded,
          color: current
              ? context.tone(Tone.success).foreground
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(location.label),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: current
            ? const StatusPill(label: 'Current', tone: Tone.success)
            : null,
        onTap: usable ? () => Navigator.pop(context, location) : null,
      ),
    );
  }
}

/// Asks before switching the exit location.
class ConfirmLocationDialog extends StatelessWidget {
  const ConfirmLocationDialog({
    super.key,
    required this.target,
    this.current,
    this.vpnOn = true,
  });

  final VpnLocation target;
  final VpnLocation? current;
  final bool vpnOn;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.travel_explore_rounded),
      title: Text('Switch to ${target.label}?'),
      content: Text(
        vpnOn
            ? 'Household VPN traffic will exit via ${target.label}'
                  '${current == null ? '' : ' instead of ${current!.label}'}. '
                  'Internet connections pause briefly while Argon reconnects '
                  'the tunnel. The kill switch keeps traffic off the direct '
                  'ISP path meanwhile.'
            : 'The VPN is off, so household traffic is not affected now. '
                  'Argon will exit via ${target.label} the next time the VPN '
                  'is turned on.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Switch location'),
        ),
      ],
    );
  }
}
