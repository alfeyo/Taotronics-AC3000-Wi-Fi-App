/// Defensive views over Argon's `/api/v1/gateway` and `/api/v1/vpn` payloads.
///
/// Every field may be absent on an older Argon. Absent or malformed values
/// parse to null so the UI can say "Not reported" instead of inventing a 0.
library;

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
bool? _bool(Object? v) => v is bool ? v : null;
int? _int(Object? v) => v is num && v.isFinite ? v.round() : null;
double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;
DateTime? _unix(Object? v) => v is num && v > 0
    ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round())
    : null;

/// Argon's household VPN (Surfshark over WireGuard on tun0).
class ArgonVpn {
  const ArgonVpn({
    this.mode,
    this.state,
    this.location,
    this.interface,
    this.interfaceUp,
    this.tunnelIp,
    this.lastChangeAt,
    this.killSwitchEnforced,
    this.rejectedPackets,
    this.healthOk,
    this.healthDetail,
    this.busy,
  });

  /// 'on' or 'off' — the requested household routing mode.
  final String? mode;

  /// Connection state as Argon describes it (e.g. 'connected').
  final String? state;
  final String? location;
  final String? interface;
  final bool? interfaceUp;
  final String? tunnelIp;
  final DateTime? lastChangeAt;
  final bool? killSwitchEnforced;
  final int? rejectedPackets;
  final bool? healthOk;
  final String? healthDetail;

  /// A mode change is already running on Argon.
  final bool? busy;

  bool get isOn => mode == 'on';
  bool get isOff => mode == 'off';
  bool get connected => (state == 'connected' || state == 'on');

  static ArgonVpn? parse(Object? raw) {
    final v = _map(raw);
    if (v == null) return null;
    final kill = _map(v['killSwitch']);
    final health = _map(v['health']);
    final control = _map(v['control']);
    final mode = _str(v['mode']);
    return ArgonVpn(
      mode: mode == 'on' || mode == 'off' ? mode : null,
      state: _str(v['state']),
      location: _str(v['location']),
      interface: _str(v['interface']),
      interfaceUp: _bool(v['interfaceUp']),
      tunnelIp: _str(v['tunnelIp']),
      lastChangeAt: _unix(v['lastChangeAt']),
      killSwitchEnforced: _bool(kill?['enforced']),
      rejectedPackets: _int(kill?['rejectedPackets']),
      healthOk: _bool(health?['ok']),
      healthDetail: _str(health?['detail']),
      busy: _bool(control?['busy']),
    );
  }
}

/// One VPN exit location Argon offers (`/api/v1/vpn/locations`).
class VpnLocation {
  const VpnLocation({
    required this.id,
    required this.label,
    this.country,
    this.city,
    this.available = true,
  });

  final String id;
  final String label;
  final String? country;
  final String? city;

  /// False when Argon lists the location but cannot use it right now.
  final bool available;

  /// "City, Country" when both are known; otherwise whichever is.
  String? get place =>
      [?city, ?country].where((s) => s != label).join(', ').ifBlank();

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [label, ?country, ?city].any((s) => s.toLowerCase().contains(q));
  }

  static VpnLocation? parse(Object? raw) {
    final v = _map(raw);
    final id = _str(v?['id']);
    if (v == null || id == null) return null;
    final country = _str(v['country']);
    final city = _str(v['city']);
    return VpnLocation(
      id: id,
      label: _str(v['label']) ?? [?country, ?city].join(' — ').ifBlank() ?? id,
      country: country,
      city: city,
      available: _bool(v['available']) ?? true,
    );
  }
}

/// Argon's `/api/v1/vpn/locations` answer. Locations always come from Argon;
/// the app never supplies its own list.
class VpnLocations {
  const VpnLocations({
    this.mode,
    this.state,
    this.current,
    this.locations = const [],
    this.busy = false,
    this.canSwitchWhileOff = false,
    this.generatedAt,
  });

  final String? mode;
  final String? state;
  final VpnLocation? current;
  final List<VpnLocation> locations;
  final bool busy;
  final bool canSwitchWhileOff;
  final DateTime? generatedAt;

  bool get vpnOff => mode == 'off';

  /// Selection is possible unless the VPN is off and Argon only switches
  /// location while it is on.
  bool get selectable => !busy && (!vpnOff || canSwitchWhileOff);

  static VpnLocations? parse(Object? raw) {
    final v = _map(raw);
    if (v == null) return null;
    final list = v['locations'];
    final mode = _str(v['mode']);
    return VpnLocations(
      mode: mode == 'on' || mode == 'off' ? mode : null,
      state: _str(v['state']),
      current: VpnLocation.parse(v['current']),
      locations: [
        if (list is List)
          for (final item in list) ?VpnLocation.parse(item),
      ],
      busy: _bool(v['busy']) ?? false,
      canSwitchWhileOff: _bool(v['canSwitchWhileOff']) ?? false,
      generatedAt: _unix(v['generatedAt']),
    );
  }
}

extension on String {
  String? ifBlank() => trim().isEmpty ? null : this;
}

/// Household totals over one period. VPN bytes are a subset of the totals.
class UsagePeriod {
  const UsagePeriod({
    this.downloadBytes,
    this.uploadBytes,
    this.totalBytes,
    this.vpnBytes,
    this.vpnShare,
    this.coverage,
    this.days,
    this.measured,
  });

  final int? downloadBytes;
  final int? uploadBytes;
  final int? totalBytes;
  final int? vpnBytes;
  final double? vpnShare;
  final double? coverage;
  final int? days;
  final bool? measured;

  /// Usable as a figure: Argon says it was measured and gave a total.
  bool get hasTotal => measured == true && total != null;

  int? get total =>
      totalBytes ??
      (downloadBytes != null && uploadBytes != null
          ? downloadBytes! + uploadBytes!
          : null);

  static UsagePeriod? parse(Object? raw) {
    final p = _map(raw);
    if (p == null) return null;
    final share = _double(p['vpnShare']);
    return UsagePeriod(
      downloadBytes: _int(p['downloadBytes']),
      uploadBytes: _int(p['uploadBytes']),
      totalBytes: _int(p['totalBytes']),
      vpnBytes: _int(p['vpnBytes']),
      vpnShare: share == null || share < 0 || share > 1 ? null : share,
      coverage: _double(p['coverage']),
      days: _int(p['days']),
      measured: _bool(p['measured']),
    );
  }
}

class UsageDay {
  const UsageDay({
    required this.day,
    this.downloadBytes,
    this.uploadBytes,
    this.vpnBytes,
    this.coverage,
    this.measured = false,
  });
  final String day;
  final int? downloadBytes;
  final int? uploadBytes;
  final int? vpnBytes;
  final double? coverage;
  final bool measured;

  int? get total => downloadBytes != null && uploadBytes != null
      ? downloadBytes! + uploadBytes!
      : null;

  static UsageDay? parse(Object? raw) {
    final d = _map(raw);
    final day = _str(d?['day']);
    if (d == null || day == null) return null;
    return UsageDay(
      day: day,
      downloadBytes: _int(d['downloadBytes']),
      uploadBytes: _int(d['uploadBytes']),
      vpnBytes: _int(d['vpnBytes']),
      coverage: _double(d['coverage']),
      measured: d['measured'] == true,
    );
  }
}

class ArgonUsage {
  const ArgonUsage({
    this.timeZone,
    this.periods = const {},
    this.days = const [],
  });
  final String? timeZone;
  final Map<String, UsagePeriod> periods;
  final List<UsageDay> days;

  UsagePeriod? get today => periods['today'];
  UsagePeriod? get yesterday => periods['yesterday'];
  UsagePeriod? get last7 => periods['last7'];
  UsagePeriod? get last30 => periods['last30'];
  UsagePeriod? get previous7 => periods['previous7'];
  UsagePeriod? get thisMonth => periods['thisMonth'];
  UsagePeriod? get lastMonth => periods['lastMonth'];

  static ArgonUsage? parse(Object? raw, {Object? legacyHistory}) {
    final u = _map(raw);
    final periods = <String, UsagePeriod>{};
    final p = _map(u?['periods']);
    if (p != null) {
      for (final key in const [
        'today',
        'yesterday',
        'last7',
        'last30',
        'previous7',
        'thisMonth',
        'lastMonth',
      ]) {
        final parsed = UsagePeriod.parse(p[key]);
        if (parsed != null) periods[key] = parsed;
      }
    }
    // Older Argons only have gateway.history.days.
    final rows = u?['days'] is List
        ? u!['days'] as List
        : _map(legacyHistory)?['days'] is List
        ? _map(legacyHistory)!['days'] as List
        : const [];
    final days = [for (final r in rows) ?UsageDay.parse(r)];
    if (u == null && days.isEmpty) return null;
    return ArgonUsage(
      timeZone: _str(u?['timeZone']),
      periods: periods,
      days: days.length > 14 ? days.sublist(days.length - 14) : days,
    );
  }
}

class UplinkProfile {
  const UplinkProfile({this.name, this.ssid, this.priority});
  final String? name;
  final String? ssid;
  final int? priority;
}

/// Argon's own internet uplink (Ethernet or Wi-Fi) and its fallback plan.
class ArgonUplink {
  const ArgonUplink({
    this.active,
    this.type,
    this.online,
    this.gatewayIp,
    this.since,
    this.profiles,
    this.radios,
    this.fallbackReady,
  });

  final String? active;
  final String? type;
  final bool? online;
  final String? gatewayIp;
  final DateTime? since;
  final List<UplinkProfile>? profiles;
  final List<String>? radios;
  final bool? fallbackReady;

  static ArgonUplink? parse(Object? raw) {
    final u = _map(raw);
    if (u == null) return null;
    final fb = _map(u['fallback']);
    final profiles = fb?['profiles'];
    final radios = fb?['radios'];
    return ArgonUplink(
      active: _str(u['active']),
      type: _str(u['type']),
      online: _bool(u['online']),
      gatewayIp: _str(u['gatewayIp']),
      since: _unix(u['since']),
      profiles: profiles is List
          ? [
              for (final p in profiles.whereType<Map>())
                UplinkProfile(
                  name: _str(p['name']),
                  ssid: _str(p['ssid']),
                  priority: _int(p['priority']),
                ),
            ]
          : null,
      radios: radios is List
          ? [
              for (final r in radios)
                if (r is String)
                  r
                else if (r is Map && _str(r['interface'] ?? r['name']) != null)
                  _str(r['interface'] ?? r['name'])!,
            ]
          : null,
      fallbackReady: _bool(fb?['ready']),
    );
  }
}

/// Per-device usage Argon estimates from sampled router rates. Never a meter:
/// [coverage] says how much of the day was observed.
class ClientUsageDay {
  const ClientUsageDay({
    required this.day,
    this.downloadBytes,
    this.uploadBytes,
    this.totalBytes,
    this.coverage,
    this.observedSeconds,
  });
  final String day;
  final int? downloadBytes;
  final int? uploadBytes;
  final int? totalBytes;
  final double? coverage;
  final int? observedSeconds;

  static ClientUsageDay? parse(Object? raw) {
    final d = _map(raw);
    final day = _str(d?['day']);
    if (d == null || day == null) return null;
    final c = _double(d['coverage']);
    return ClientUsageDay(
      day: day,
      downloadBytes: _int(d['downloadBytes']),
      uploadBytes: _int(d['uploadBytes']),
      totalBytes: _int(d['totalBytes']),
      coverage: c?.clamp(0.0, 1.0),
      observedSeconds: _int(d['observedSeconds']),
    );
  }
}

/// One household device from Argon's normalized router-client inventory.
/// Rates are bits per second (Argon converts the router's bytes/s x8).
class ArgonClient {
  const ArgonClient({
    required this.mac,
    this.ip,
    this.name,
    this.hostname,
    this.connectionType,
    this.online,
    this.downBitsPerSec,
    this.upBitsPerSec,
    this.lastSeen,
    this.source,
    this.labelled = false,
    this.today,
    this.days = const [],
  });

  final String mac;
  final String? ip;
  final String? name;
  final String? hostname;

  /// 'wifi', 'wired' or 'unknown'.
  final String? connectionType;

  /// Null when Argon has no live observation.
  final bool? online;
  final num? downBitsPerSec;
  final num? upBitsPerSec;
  final DateTime? lastSeen;
  final String? source;
  final bool labelled;
  final ClientUsageDay? today;
  final List<ClientUsageDay> days;

  static final _macLike = RegExp(
    r'^[0-9a-f]{2}([:-][0-9a-f]{2}){5}$',
    caseSensitive: false,
  );

  /// A human name, or null when the router only knows the MAC/IP.
  String? get friendlyName {
    for (final v in [name, hostname]) {
      if (v != null && !_macLike.hasMatch(v) && v != ip) return v;
    }
    return null;
  }

  String get displayName => friendlyName ?? 'Unnamed device';
  bool get isOnline => online == true;
  bool get isWired => connectionType == 'wired';
  num get totalBitsPerSec => (downBitsPerSec ?? 0) + (upBitsPerSec ?? 0);

  static ArgonClient? parse(Object? raw) {
    final c = _map(raw);
    final mac = _str(c?['mac']);
    if (c == null || mac == null) return null;
    final usage = _map(c['usage']);
    final days = usage?['days'];
    return ArgonClient(
      mac: mac.toLowerCase(),
      ip: _str(c['ip']),
      name: _str(c['name']),
      hostname: _str(c['hostname']),
      connectionType: _str(c['connectionType']),
      online: _bool(c['online']),
      downBitsPerSec: _double(c['rateRxBps']),
      upBitsPerSec: _double(c['rateTxBps']),
      lastSeen: _unix(c['lastSeen']),
      source: _str(c['source']),
      labelled: c['labelled'] == true,
      today: ClientUsageDay.parse(usage?['today']),
      days: days is List
          ? [for (final d in days) ?ClientUsageDay.parse(d)]
          : const [],
    );
  }
}

/// Argon's router control lease (`/api/v1/router/lease`, `router.control.lease`).
class RouterLease {
  const RouterLease({
    this.active = false,
    this.holderId,
    this.holderName,
    this.expiresAt,
    this.handover,
  });
  final bool active;
  final String? holderId;
  final String? holderName;
  final DateTime? expiresAt;

  /// 'none', 'waiting-for-observer', 'observer-yielded' or 'observer-offline'.
  final String? handover;

  /// The router's management session is free for the lease holder.
  bool get handedOver =>
      active &&
      (handover == 'observer-yielded' || handover == 'observer-offline');

  static RouterLease? parse(Object? raw) {
    final l = _map(raw);
    if (l == null) return null;
    final holder = _map(l['holder']);
    return RouterLease(
      active: l['active'] == true,
      holderId: _str(holder?['id']),
      holderName: _str(holder?['name']),
      expiresAt: _unix(l['expiresAt']),
      handover: _str(l['handover']),
    );
  }
}

/// Argon's view of the TaoTronics router: observed by its LAN observer relay
/// (or, as a fallback, by a phone's shared snapshot).
class ArgonRouterView {
  const ArgonRouterView({
    this.name,
    this.model,
    this.internet,
    this.devicesOnline,
    this.nodesOnline,
    this.nodesTotal,
    this.observedAt,
    this.monitoring,
    this.monitoringLabel,
    this.monitoringDetail,
    this.source,
    this.clients = const [],
    this.knownCount,
    this.onlineCount,
    this.wifiCount,
    this.wiredCount,
    this.wanDownBitsPerSec,
    this.wanUpBitsPerSec,
    this.ssids = const [],
    this.nodes = const [],
    this.controlHolder,
    this.lease,
    this.usageMethod,
    this.usageStale,
    this.usageObservedAt,
  });

  /// Argon's own description of its router monitoring: 'connected', 'stale',
  /// 'unreachable', 'not-connected' or 'direct-control'.
  final String? monitoring;
  final String? monitoringLabel;
  final String? monitoringDetail;

  /// e.g. 'lan-observer:dell' or 'flutter-phone'.
  final String? source;
  final String? name;
  final String? model;
  final bool? internet;
  final int? devicesOnline;
  final int? nodesOnline;
  final int? nodesTotal;
  final DateTime? observedAt;
  final List<ArgonClient> clients;
  final int? knownCount;

  /// Null unless Argon has live data: never inferred.
  final int? onlineCount;
  final int? wifiCount;
  final int? wiredCount;
  final num? wanDownBitsPerSec;
  final num? wanUpBitsPerSec;
  final List<String> ssids;
  final List<Map<String, dynamic>> nodes;

  /// 'observer', 'phone' (lease) or 'phone-snapshot'.
  final String? controlHolder;
  final RouterLease? lease;

  /// 'estimated' for per-device usage derived from sampled rates.
  final String? usageMethod;
  final bool? usageStale;
  final DateTime? usageObservedAt;

  bool get live => monitoring == 'connected';
  bool get observedByArgon => source?.startsWith('lan-observer') == true;

  /// 'Dell LAN observer' for 'lan-observer:dell'.
  String get sourceLabel {
    final s = source;
    if (s == null) return 'Not reported';
    if (s.startsWith('lan-observer:')) {
      final host = s.substring('lan-observer:'.length);
      return '${host.isEmpty ? '' : '${host[0].toUpperCase()}${host.substring(1)} '}LAN observer';
    }
    if (s == 'flutter-phone') return 'Phone snapshot';
    return s;
  }

  static ArgonRouterView? parse(Object? raw) {
    final r = _map(raw);
    if (r == null) return null;
    final inner = _map(r['router']) ?? r;
    final mon = _map(r['monitoring']);
    final counts = _map(r['counts']);
    final wan = _map(inner['wanRate']);
    final control = _map(r['control']);
    final usage = _map(r['clientUsage']);
    final rawClients = r['clients'];
    final wifi = inner['wifi'];
    final nodes = inner['nodes'];
    return ArgonRouterView(
      monitoring: _str(mon?['state']),
      monitoringLabel: _str(mon?['label']),
      monitoringDetail: _str(mon?['detail']),
      source: _str(mon?['source']),
      name: _str(inner['name']),
      model: _str(inner['model']),
      internet: _bool(inner['internet']),
      devicesOnline: _int(inner['devicesOnline']),
      nodesOnline: _int(inner['nodesOnline']),
      nodesTotal: _int(inner['nodesTotal']),
      observedAt: _unix(
        mon?['snapshotAt'] ?? r['observedAt'] ?? inner['observedAt'],
      ),
      clients: rawClients is List
          ? [for (final c in rawClients) ?ArgonClient.parse(c)]
          : const [],
      knownCount: _int(counts?['known']),
      onlineCount: _int(counts?['online']),
      wifiCount: _int(counts?['wifi']),
      wiredCount: _int(counts?['wired']),
      wanDownBitsPerSec: _double(wan?['downloadBps']),
      wanUpBitsPerSec: _double(wan?['uploadBps']),
      ssids: wifi is List
          ? [
              for (final w in wifi.whereType<Map>())
                if (_str(w['ssid']) != null) _str(w['ssid'])!,
            ]
          : const [],
      nodes: nodes is List
          ? [for (final n in nodes.whereType<Map>()) n.cast<String, dynamic>()]
          : const [],
      controlHolder: _str(control?['holder']),
      lease: RouterLease.parse(control?['lease']),
      usageMethod: _str(usage?['method']),
      usageStale: _bool(usage?['stale']),
      usageObservedAt: _unix(usage?['lastObservationAt']),
    );
  }
}
