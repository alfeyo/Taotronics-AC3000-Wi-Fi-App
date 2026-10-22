import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/save_result.dart';
import '../providers/router_provider.dart';
import '../services/router_access_policy.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// Shows connection problems and configuration changes awaiting
/// confirmation. Renders nothing when everything is normal.
class ConnectionStatusBanners extends StatelessWidget {
  const ConnectionStatusBanners({super.key, this.onOpenSetup});

  final VoidCallback? onOpenSetup;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final banners = <Widget>[];

    if (provider.isRouterControlledByPi) {
      // Network Hub is the controller. Read-only by design, not a fault.
      banners.add(
        const InfoBanner(
          tone: Tone.info,
          icon: Icons.hub_rounded,
          title: RouterAccessPolicy.piOwnershipMessage,
          message: RouterAccessPolicy.piOwnershipDetail,
        ),
      );
    }

    if (provider.isReconnecting) {
      banners.add(
        InfoBanner(
          tone: Tone.warning,
          busy: true,
          title: 'Reconnecting to your router',
          message:
              'Values below may be out of date until the connection returns.',
          action: TextButton(
            onPressed: provider.reconnectNow,
            child: const Text('Retry now'),
          ),
        ),
      );
    } else if (provider.managedElsewhere) {
      // Router-side limit, not an app fault: one phone manages at a time.
      banners.add(
        const InfoBanner(
          tone: Tone.warning,
          busy: true,
          icon: Icons.phonelink_lock_rounded,
          title: 'Another phone is managing the router',
          message:
              'The router serves one phone at a time. This phone gets access '
              'automatically about a minute after TT Router on the other phone '
              'is closed or put in the background. Values below may be out of '
              'date until then.',
        ),
      );
    } else if (!provider.isConnected &&
        !provider.isRouterControlledByPi &&
        provider.authState != AuthenticationState.authenticating) {
      banners.add(
        InfoBanner(
          tone: Tone.danger,
          icon: Icons.link_off_rounded,
          title: provider.authState == AuthenticationState.authenticationFailed
              ? 'Router sign-in failed'
              : 'Not connected to the router',
          message:
              provider.errorMessage ??
              'Join the router Wi-Fi, then pair to unlock controls.',
          action: onOpenSetup == null
              ? null
              : TextButton(
                  onPressed: onOpenSetup,
                  child: const Text('Set up or pair'),
                ),
        ),
      );
    } else if (provider.errorMessage != null) {
      banners.add(
        InfoBanner(
          tone: Tone.danger,
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: provider.errorMessage,
          onDismiss: provider.clearError,
        ),
      );
    }

    for (final change in provider.pendingChanges) {
      banners.add(
        InfoBanner(
          tone: switch (change.status) {
            ChangeStatus.verifying => Tone.info,
            ChangeStatus.confirmed => Tone.success,
            ChangeStatus.mismatch => Tone.danger,
            ChangeStatus.unverified => Tone.warning,
          },
          busy: change.status == ChangeStatus.verifying,
          icon: switch (change.status) {
            ChangeStatus.confirmed => Icons.check_circle_rounded,
            ChangeStatus.mismatch => Icons.error_rounded,
            _ => Icons.help_outline_rounded,
          },
          title: switch (change.status) {
            ChangeStatus.verifying =>
              'Confirming ${change.label.toLowerCase()}',
            ChangeStatus.confirmed => '${change.label} confirmed',
            ChangeStatus.mismatch => '${change.label} not applied',
            ChangeStatus.unverified => '${change.label} unconfirmed',
          },
          message: change.message,
          onDismiss: change.status == ChangeStatus.verifying
              ? null
              : () => provider.dismissPendingChange(change),
        ),
      );
    }

    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final banner in banners)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: banner,
          ),
      ],
    );
  }
}
