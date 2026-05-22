import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../models/device_entity.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    final p = context.read<RouterProvider>();
    p.pauseLive();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) p.refreshDevices();
    });
  }

  @override
  void dispose() {
    try {
      context.read<RouterProvider>().resumeLive();
    } catch (_) {}
    super.dispose();
  }

  String _formatRate(int bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var value = bytesPerSec.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final f = value >= 100
        ? value.toStringAsFixed(0)
        : value >= 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2);
    return '$f ${units[unit]}';
  }

  IconData _deviceIcon(int type) {
    switch (type) {
      case 1:
        return Icons.phone_android_rounded;
      case 2:
      case 3:
        return Icons.phone_iphone_rounded;
      case 4:
      case 5:
        return Icons.laptop_mac_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f7fa),
      appBar: AppBar(
        title: const Text('Connected Devices'),
        backgroundColor: const Color(0xffc14524),
        foregroundColor: Colors.white,
        actions: [
          Consumer<RouterProvider>(
            builder: (_, p, _) => IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: p.refreshDevices,
            ),
          ),
        ],
      ),
      body: Consumer<RouterProvider>(
        builder: (context, provider, _) {
          if (provider.devices.isEmpty) {
            return RefreshIndicator(
              onRefresh: provider.refreshDevices,
              child: ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  _emptyState(),
                ],
              ),
            );
          }

          final online = provider.devices.where((d) => d.isOnline).toList();
          final offline = provider.devices.where((d) => !d.isOnline).toList();

          return RefreshIndicator(
            onRefresh: provider.refreshDevices,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _summaryCard(online.length, provider.devices.length),
                const SizedBox(height: 18),
                if (online.isNotEmpty) ...[
                  _sectionHeader('Online', online.length, Colors.green),
                  const SizedBox(height: 8),
                  ...online.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _deviceCard(d),
                    ),
                  ),
                ],
                if (offline.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _sectionHeader('Offline', offline.length, Colors.grey),
                  const SizedBox(height: 8),
                  ...offline.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _deviceCard(d),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: Colors.deepOrange.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.devices_other_rounded,
            size: 40,
            color: Colors.deepOrange,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'No connected devices found',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text('Pull to refresh', style: TextStyle(color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _summaryCard(int online, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xff10b981).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.devices_rounded,
              color: Color(0xff10b981),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$online online',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  '$total total on this network',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count, Color accent) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _deviceCard(DeviceEntity d) {
    final hasTraffic = d.uploadSpeed > 0 || d.downloadSpeed > 0;
    final iconBg = d.isOnline
        ? Colors.blue.withValues(alpha: 0.12)
        : Colors.grey.shade100;
    final iconColor = d.isOnline ? Colors.blue : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _deviceIcon(d.deviceType),
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.ipAddress ?? d.mac,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(d.isOnline),
            ],
          ),
          if (hasTraffic) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _rateChip(
                    icon: Icons.arrow_upward_rounded,
                    value: _formatRate(d.uploadSpeed),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _rateChip(
                    icon: Icons.arrow_downward_rounded,
                    value: _formatRate(d.downloadSpeed),
                    color: const Color(0xff10b981),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'MAC ${d.mac}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateChip({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool online) {
    final color = online ? const Color(0xff10b981) : Colors.grey.shade500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            online ? 'Online' : 'Offline',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
