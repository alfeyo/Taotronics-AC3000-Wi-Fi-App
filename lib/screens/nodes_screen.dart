import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../models/device_entity.dart';
import 'setup_wizard_screen.dart';

class NodesScreen extends StatelessWidget {
  const NodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Nodes'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add mesh node',
            onPressed: () => _showAddNodeDialog(context),
          ),
          Consumer<RouterProvider>(
            builder: (context, provider, child) => IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: provider.refreshNodes,
            ),
          ),
        ],
      ),
      body: Consumer<RouterProvider>(
        builder: (context, provider, child) {
          if (provider.nodes.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.router, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No mesh nodes found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.refreshNodes,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.nodes.length,
              itemBuilder: (context, index) {
                final node = provider.nodes[index];
                return _buildNodeCard(context, node);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddNodeDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _AddNodeDialog(),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, NodeEntity node) async {
    final controller = TextEditingController(text: node.displayName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(node.isMaster ? 'Rename Router' : 'Rename Node'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();
    if (confirmed != true || name.isEmpty || !context.mounted) return;

    final success = await context
        .read<RouterProvider>()
        .renameNode(nodeSn: node.sn, name: name, isMaster: node.isMaster);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Renamed to "$name"' : 'Rename failed'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, NodeEntity node) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: node.isOnline ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.router,
                    size: 30,
                    color: node.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              node.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (node.isMaster) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Master',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _showRenameDialog(context, node),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        node.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: node.isOnline ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (node.isOnline)
                  _buildSignalIndicator(node.signalStrength),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  Icons.devices,
                  '${node.connectedDevices}',
                  'Devices',
                ),
                _buildStatItem(
                  Icons.memory,
                  node.model ?? 'N/A',
                  'Model',
                ),
                _buildStatItem(
                  Icons.update,
                  node.firmwareVersion ?? 'N/A',
                  'Firmware',
                ),
              ],
            ),
            if (node.ipAddress != null) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'IP: ${node.ipAddress}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  Text(
                    'SN: ${node.sn}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignalIndicator(int strength) {
    final bars = (strength / 25).ceil().clamp(1, 4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final isActive = index < bars;
        return Container(
          width: 4,
          height: 8.0 + (index * 4),
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: isActive ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _AddNodeDialog extends StatefulWidget {
  const _AddNodeDialog();

  @override
  State<_AddNodeDialog> createState() => _AddNodeDialogState();
}

class _AddNodeDialogState extends State<_AddNodeDialog> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<RouterProvider>();
    if (provider.wirelessNetworksParsed.isEmpty) {
      provider.refreshWirelessSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RouterProvider>();
    final enabled = provider.wirelessNetworksParsed
        .where((n) => n.ssid.isNotEmpty)
        .toList();
    final ssid = enabled.isNotEmpty ? enabled.first.ssid : '';
    final password = enabled.isNotEmpty ? enabled.first.password : '';
    final loadingCreds =
        provider.isConnected &&
        provider.wirelessLoading &&
        enabled.isEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_circle_outline,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Add Mesh Node'),
        ],
      ),
      content: Text(
        !provider.isConnected
            ? 'Connect to your router first, then come back to add a node.'
            : loadingCreds
            ? 'Place the new unit near your main router with its LED flashing green (setup mode) and keep your phone close to it.\n\nFetching your current Wi-Fi settings…'
            : 'Place the new unit near your main router with its LED flashing green (setup mode) and keep your phone close to it.\n\n'
                  'The wizard opens with your current Wi-Fi name and password pre-filled${ssid.isEmpty ? '' : ' ($ssid)'} — keep them unchanged. After Bluetooth setup, the app waits for the main router to detect the new unit (up to 90 seconds) and adds it to the mesh automatically. Keep the phone on the main Wi-Fi throughout.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              provider.isConnected && !loadingCreds
                  ? () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SetupWizardScreen(
                            prefillSsid: ssid.isNotEmpty ? ssid : null,
                            prefillPassword:
                                password.isNotEmpty ? password : null,
                          ),
                        ),
                      );
                    }
                  : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          child: loadingCreds
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Start Bluetooth Setup'),
        ),
      ],
    );
  }
}
