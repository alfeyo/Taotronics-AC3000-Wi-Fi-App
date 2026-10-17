import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../models/wireless_network.dart';
import '../widgets/feedback.dart';
import 'setup_wizard_screen.dart';

class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  late final LivePauseToken _livePause;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RouterProvider>();
    _livePause = provider.pauseLiveUpdates('Wi-Fi settings');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.refreshWirelessSettings();
    });
  }

  @override
  void dispose() {
    _livePause.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Wi-Fi Settings'),
        backgroundColor: const Color(0xffc14524),
        foregroundColor: Colors.white,
        actions: [
          Consumer<RouterProvider>(
            builder: (_, p, _) => IconButton(
              icon: p.wirelessLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: p.wirelessLoading
                  ? null
                  : () => p.refreshWirelessSettings(),
            ),
          ),
        ],
      ),
      body: Consumer<RouterProvider>(
        builder: (context, provider, child) {
          if (!provider.isConnected) {
            return _notConnected(context);
          }

          if (provider.wirelessLoading &&
              provider.wirelessNetworksParsed.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.deepOrange),
                  SizedBox(height: 16),
                  Text('Loading Wi-Fi settings...'),
                ],
              ),
            );
          }

          final networks = provider.wirelessNetworksParsed;
          if (networks.isEmpty) {
            return _emptyState(provider);
          }

          return RefreshIndicator(
            onRefresh: provider.refreshWirelessSettings,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: networks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final network = networks[i];
                return _WifiNetworkCard(
                  network: network,
                  color: network.index == 0 ? Colors.blue : Colors.purple,
                  icon: network.index == 0
                      ? Icons.wifi_2_bar_rounded
                      : Icons.wifi_rounded,
                  onEdit: () => _showEditDialog(context, provider, network),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(RouterProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Wi-Fi networks found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Pull to refresh or check router connection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.refreshWirelessSettings(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notConnected(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Authentication Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pair the router to access Wi-Fi settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
                );
              },
              icon: const Icon(Icons.link),
              label: const Text('Pair Router'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    RouterProvider provider,
    WirelessNetwork network,
  ) {
    final ssidCtrl = TextEditingController(text: network.ssid);
    final pwCtrl = TextEditingController(text: network.password);
    bool showPw = false;
    bool saving = false;
    String? ssidError;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.wifi_rounded,
                  color: Colors.deepOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Edit Wi-Fi',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      network.bandLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ssidCtrl,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: 'Network name (SSID)',
                    prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                    errorText: ssidError,
                  ),
                  onChanged: (_) {
                    if (ssidError != null) setS(() => ssidError = null);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pwCtrl,
                  enabled: !saving,
                  obscureText: !showPw,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPw
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                      onPressed: () => setS(() => showPw = !showPw),
                    ),
                    helperText: network.encrypt > 0 ? 'Min 8 characters' : null,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.security_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        network.encryptionLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xfffff7ed),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xffffe2c8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xffb45309),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The router may briefly disconnect while applying changes.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final ssid = ssidCtrl.text.trim();
                      final password = pwCtrl.text;

                      if (ssid.isEmpty) {
                        setS(() => ssidError = 'SSID cannot be empty');
                        return;
                      }

                      if (network.encrypt > 0 && password.length < 8) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password must be at least 8 characters',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setS(() => saving = true);

                      final updated = network.copyWith(
                        ssid: ssid,
                        password: password,
                        create: 1,
                      );

                      final result = await provider.updateWirelessNetwork(
                        updated,
                      );

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (context.mounted) showSaveResult(context, result);
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WifiNetworkCard extends StatelessWidget {
  final WirelessNetwork network;
  final Color color;
  final IconData icon;
  final VoidCallback onEdit;

  const _WifiNetworkCard({
    required this.network,
    required this.color,
    required this.icon,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: network.isEnabled
                        ? color.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: network.isEnabled ? color : Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        network.bandLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        network.ssid.isEmpty ? 'Not configured' : network.ssid,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: network.ssid.isEmpty
                              ? Colors.grey
                              : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: network.isEnabled
                        ? const Color(0xff10b981).withValues(alpha: 0.12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: network.isEnabled
                              ? const Color(0xff10b981)
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        network.isEnabled ? 'On' : 'Off',
                        style: TextStyle(
                          color: network.isEnabled
                              ? const Color(0xff10b981)
                              : Colors.grey,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _infoChip(Icons.lock_rounded, network.encryptionLabel),
                const SizedBox(width: 8),
                _infoChip(
                  Icons.password_rounded,
                  network.password.isNotEmpty ? '••••••••' : 'Open',
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData iconData, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 13, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
