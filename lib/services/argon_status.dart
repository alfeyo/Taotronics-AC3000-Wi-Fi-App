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
  bool get connected => state == 'connected';

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
                else if (r is Map && _str(r['name']) != null)
                  _str(r['name'])!,
            ]
          : null,
      fallbackReady: _bool(fb?['ready']),
    );
  }
}

/// Argon's view of the TaoTronics router (from the phone's shared snapshot).
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
  });

  /// Argon's own description of its router monitoring (e.g. connected).
  final String? monitoring;
  final String? name;
  final String? model;
  final bool? internet;
  final int? devicesOnline;
  final int? nodesOnline;
  final int? nodesTotal;
  final DateTime? observedAt;

  static ArgonRouterView? parse(Object? raw) {
    final r = _map(raw);
    if (r == null) return null;
    final inner = _map(r['router']) ?? r;
    final mon = _map(r['monitoring']);
    return ArgonRouterView(
      monitoring: _str(mon?['state']),
      name: _str(inner['name']),
      model: _str(inner['model']),
      internet: _bool(inner['internet']),
      devicesOnline: _int(inner['devicesOnline']),
      nodesOnline: _int(inner['nodesOnline']),
      nodesTotal: _int(inner['nodesTotal']),
      observedAt: _unix(
        mon?['snapshotAt'] ?? r['observedAt'] ?? inner['observedAt'],
      ),
    );
  }
}
