import '../services/wifi_scan.dart';
import 'wireless_network.dart';

/// How a network relates to what the router's local API can control.
enum NetworkKind {
  configured('Configured & controllable'),
  disabled('Disabled'),
  guest('Guest'),
  observed('Observed — not exposed by router API'),
  meshInternal('Mesh/internal'),
  unknown('Unknown');

  const NetworkKind(this.label);
  final String label;
}

/// Why an observed network cannot be edited here.
const observedOnlyReason =
    'Editing unavailable: not exposed by the router\'s local API.';

/// One row of the "All networks" list.
class InventoryEntry {
  const InventoryEntry({
    required this.kind,
    required this.name,
    this.network,
    this.radios = const [],
    this.note,
    this.unsecured = false,
    this.enabled,
  });

  final NetworkKind kind;
  final String name;

  /// The router entry, for configured/disabled rows.
  final WirelessNetwork? network;

  /// Access points this phone heard for this network, if scanned.
  final List<WifiScanResult> radios;
  final String? note;
  final bool unsecured;
  final bool? enabled;

  List<String> get bandsSeen =>
      {for (final r in radios) r.band}.toList()..sort();
}

/// The household network as people think of it: every enabled router entry
/// broadcasting the most common SSID.
class PrimaryNetwork {
  const PrimaryNetwork({required this.ssid, required this.entries});

  final String ssid;

  /// Enabled router entries with this SSID, lowest index first.
  final List<WirelessNetwork> entries;

  bool get anyUnsecured => entries.any((n) => n.isUnsecured);

  /// One label when every entry agrees, otherwise each distinct one.
  String get securityLabel =>
      {for (final n in entries) n.securityLabel}.join(' / ');

  String get entriesLabel => entries.length == 1
      ? entries.single.entryLabel
      : 'Router entries ${_joinIndexes(entries)}';
}

/// Two or more enabled router entries with the same SSID and security.
class DuplicateGroup {
  const DuplicateGroup({required this.entries});

  /// Sorted by index.
  final List<WirelessNetwork> entries;

  String get ssid => entries.first.ssid;
  String get securityLabel => entries.first.securityLabel;

  /// The entry that stays on (lowest index).
  WirelessNetwork get keep => entries.first;

  /// The entry consolidation would turn off (highest index).
  WirelessNetwork get retire => entries.last;

  String get entriesLabel => _joinIndexes(entries);
}

String _joinIndexes(List<WirelessNetwork> entries) {
  final n = [for (final e in entries) '${e.index + 1}'];
  if (n.length <= 2) return n.join(' and ');
  return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
}

abstract final class WifiInventory {
  /// Most common SSID among enabled entries (ties: the lowest index wins).
  static PrimaryNetwork? primary(List<WirelessNetwork> networks) {
    final enabled =
        networks.where((n) => n.isEnabled && n.ssid.trim().isNotEmpty).toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (enabled.isEmpty) return null;
    final counts = <String, int>{};
    for (final n in enabled) {
      counts[n.ssid] = (counts[n.ssid] ?? 0) + 1;
    }
    var best = enabled.first.ssid;
    for (final n in enabled) {
      if (counts[n.ssid]! > counts[best]!) best = n.ssid;
    }
    return PrimaryNetwork(
      ssid: best,
      entries: enabled.where((n) => n.ssid == best).toList(),
    );
  }

  /// Groups of ≥2 enabled entries sharing SSID and security.
  static List<DuplicateGroup> duplicates(List<WirelessNetwork> networks) {
    final groups = <(String, int, String), List<WirelessNetwork>>{};
    for (final n in networks) {
      if (!n.isEnabled || n.ssid.trim().isEmpty || !n.passwordKnown) continue;
      (groups[(n.ssid, n.encrypt, n.password)] ??= []).add(n);
    }
    return [
      for (final g in groups.values)
        if (g.length >= 2)
          DuplicateGroup(
            entries: g..sort((a, b) => a.index.compareTo(b.index)),
          ),
    ];
  }

  /// First five octets of a BSSID ("aa:bb:cc:dd:ee"): the router's radios
  /// share this block and differ only in the last octet.
  static String? bssidBlock(String? bssid) {
    final parts = bssid?.toLowerCase().split(':');
    if (parts == null ||
        parts.length != 6 ||
        parts.any((p) => !RegExp(r'^[0-9a-f]{2}$').hasMatch(p))) {
      return null;
    }
    return parts.sublist(0, 5).join(':');
  }

  /// Block of the access point this phone is joined to, when that access
  /// point broadcasts a network the router reports (so it is the router).
  static String? routerBlock(
    WifiScanSnapshot? scan,
    List<WirelessNetwork> networks, {
    String? guestSsid,
  }) {
    if (scan == null || scan.status != WifiScanStatus.ok) return null;
    final block = bssidBlock(scan.connectedBssid);
    if (block == null) return null;
    final names = {
      for (final n in networks)
        if (n.ssid.trim().isNotEmpty) n.ssid,
      ?guestSsid,
    };
    final connected = scan.connectedSsid;
    if (connected == null || !names.contains(connected)) return null;
    // Same SSID alone cannot identify a TaoTronics AP: bridged Nokia uses it
    // too. This is a vendor hint for radio observations, never device identity.
    if (!block.startsWith('80:c5:48:')) return null;
    return block;
  }

  /// Every network: router entries, guest, and what the phone heard from the
  /// router's own radios (same BSSID block as the connected access point).
  static List<InventoryEntry> build({
    required List<WirelessNetwork> networks,
    Map<String, dynamic>? guest,
    WifiScanSnapshot? scan,
  }) {
    final guestSsid = '${guest?['Ssid'] ?? ''}'.trim();
    final block = routerBlock(
      scan,
      networks,
      guestSsid: guestSsid.isEmpty ? null : guestSsid,
    );
    final heard = <String, List<WifiScanResult>>{};
    if (block != null) {
      for (final r in scan!.results) {
        if (r.ageSeconds != null && r.ageSeconds! > 120) continue;
        if (bssidBlock(r.bssid) != block) continue;
        (heard[r.ssid.trim()] ??= []).add(r);
      }
    }
    final claimed = <String>{};
    final rows = <InventoryEntry>[];

    final sorted = [...networks]..sort((a, b) => a.index.compareTo(b.index));
    for (final n in sorted) {
      final known = n.encrypt >= 0 && n.encrypt <= 5;
      final kind = n.ssid.trim().isEmpty || !known
          ? NetworkKind.unknown
          : n.isEnabled
          ? NetworkKind.configured
          : NetworkKind.disabled;
      claimed.add(n.ssid);
      rows.add(
        InventoryEntry(
          kind: kind,
          name: n.ssid.trim().isEmpty ? 'No name set' : n.ssid,
          network: n,
          radios: n.isEnabled ? heard[n.ssid] ?? const [] : const [],
          unsecured: n.isUnsecured,
          enabled: n.isEnabled,
          note: [
            n.entryLabel,
            n.securityLabel,
            n.isEnabled ? 'On' : 'Off',
          ].join(' · '),
        ),
      );
    }

    if (guest != null) {
      final on = '${guest['Enable']}' == '1';
      final name = guestSsid.isEmpty ? 'Guest Wi-Fi' : guestSsid;
      if (guestSsid.isNotEmpty) claimed.add(guestSsid);
      rows.add(
        InventoryEntry(
          kind: NetworkKind.guest,
          name: name,
          enabled: on,
          radios: guestSsid.isEmpty ? const [] : heard[guestSsid] ?? const [],
          note: 'Guest settings · ${on ? 'On' : 'Off'}',
        ),
      );
    }

    final hidden = heard[''] ?? const [];
    for (final entry in heard.entries) {
      if (entry.key.isEmpty || claimed.contains(entry.key)) continue;
      rows.add(
        InventoryEntry(
          kind: NetworkKind.observed,
          name: entry.key,
          radios: entry.value,
          unsecured: entry.value.every((r) => r.open),
          enabled: true,
          note: observedOnlyReason,
        ),
      );
    }
    if (hidden.isNotEmpty) {
      rows.add(
        InventoryEntry(
          kind: NetworkKind.meshInternal,
          name: 'Hidden network',
          radios: hidden,
          enabled: true,
          note:
              'Hidden SSID from the router\'s own radios, probably mesh '
              'backhaul. Not exposed by the router\'s local API.',
        ),
      );
    }
    return rows;
  }
}
