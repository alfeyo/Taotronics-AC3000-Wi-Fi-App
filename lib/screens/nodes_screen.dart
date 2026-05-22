import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../models/device_entity.dart';

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
                          Text(
                            node.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
