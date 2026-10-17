import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pi_provider.dart';
import '../providers/router_provider.dart';
import '../theme/app_theme.dart';

String piBytes(num? v) {
  if (v == null) return '—';
  if (v >= 1073741824) return '${(v / 1073741824).toStringAsFixed(2)} GiB';
  if (v >= 1048576) return '${(v / 1048576).toStringAsFixed(1)} MiB';
  return '${(v / 1024).toStringAsFixed(1)} KiB';
}

String piRate(num? v) => v == null
    ? '—'
    : v >= 1000000
    ? '${(v / 1000000).toStringAsFixed(1)} Mbps'
    : '${(v / 1000).toStringAsFixed(0)} kbps';
String piTime(dynamic v) {
  if (v is! num) return 'Not reported';
  final d = DateTime.fromMillisecondsSinceEpoch((v * 1000).round()).toLocal();
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic> ? v : {};
num? _number(dynamic v) => v is num ? v : null;

class PiGatewayScreen extends StatefulWidget {
  const PiGatewayScreen({super.key});
  @override
  State<PiGatewayScreen> createState() => _PiGatewayScreenState();
}

class _PiGatewayScreenState extends State<PiGatewayScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  late PiProvider _pi;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _pi = context.read<PiProvider>();
    _pi.setForeground(true);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_foreground) _refresh();
      });
    });
  }

  Future<void> _refresh() async {
    if (mounted && _foreground) {
      await context.read<PiProvider>().refresh(context.read<RouterProvider>());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pi.setForeground(_foreground);
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _pi.setForeground(false);
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setup() async {
    final p = context.read<PiProvider>();
    final address = TextEditingController(text: p.endpoint);
    final token = TextEditingController();
    bool share = p.sharing;
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Connect Argon'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Use your Pi’s Tailscale address with the phone VPN connected, or a verified HTTPS address. Your router pairing stays separate.',
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(
                    labelText: 'Pi address',
                    hintText: 'http://100.x.x.x',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: token,
                  decoration: InputDecoration(
                    labelText: 'Companion token',
                    hintText: p.configured
                        ? 'Leave blank to keep saved token'
                        : null,
                  ),
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share router telemetry'),
                  subtitle: const Text(
                    'Sanitized inventory only while Gateway is open. No passwords or router commands.',
                  ),
                  value: share,
                  onChanged: (v) => setState(() => share = v),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await p.configure(address.text, token.text, share);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setState(() {
                            error = e.toString();
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save connection'),
            ),
          ],
        ),
      ),
    );
    address.dispose();
    token.dispose();
    await _refresh();
  }

  Widget _panel(Widget child, {Color? color}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color ?? Palette.panel,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Palette.line),
    ),
    child: child,
  );
  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PiProvider>();
    final data = p.data ?? {};
    final g = _map(data['gateway']),
        traffic = _map(data['traffic']),
        a = _map(traffic['aggregate']),
        today = _map(traffic['today']),
        up = _map(g['upstream']),
        vpn = _map(g['vpn']);
    final events = (data['events'] as List? ?? []).whereType<Map>().toList();
    final days = (_map(data['history'])['days'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final recent = days.length > 14 ? days.sublist(days.length - 14) : days;
    final fresh = !p.stale && traffic['stale'] == false;
    final total =
        _number(today['downloadBytes']) != null &&
            _number(today['uploadBytes']) != null
        ? (_number(today['downloadBytes'])! + _number(today['uploadBytes'])!)
        : null;
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: Palette.background,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ARGON · RASPBERRY PI',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              color: Palette.muted,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your gateway',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh gateway',
                      onPressed: p.busy ? null : _refresh,
                      icon: p.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Gateway connection',
                      onPressed: _setup,
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (!p.configured)
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.hub_outlined,
                          size: 36,
                          color: Palette.amber,
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'Bring Argon into TT Router',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'See household usage, VPN health and Pi events alongside your router. Connect securely over Tailscale; direct router controls continue to work independently.',
                          style: TextStyle(color: Palette.muted, height: 1.6),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _setup,
                          icon: const Icon(Icons.add_link),
                          label: const Text('Connect Raspberry Pi'),
                        ),
                      ],
                    ),
                  ),
                if (p.configured) ...[
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              p.stale
                                  ? Icons.cloud_off
                                  : Icons.check_circle_outline,
                              color: p.stale ? Palette.amber : Palette.green,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                p.stale
                                    ? 'Awaiting gateway'
                                    : 'Argon is available',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(
                          p.error ??
                              (p.stale
                                  ? 'No fresh response. Retained measurements are stale.'
                                  : 'Private connection · refreshed ${piTime(data['generatedAt'])}'),
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        _line(
                          'Upstream',
                          '${up['ssid'] ?? up['interface'] ?? 'Unknown'} · ${up['online'] == null
                              ? 'unknown'
                              : up['online'] == true
                              ? 'online'
                              : 'offline'}',
                        ),
                        _line(
                          'Surfshark VPN',
                          vpn['state']?.toString() ?? 'Unknown',
                        ),
                        _line(
                          'Uptime',
                          g['uptimeSeconds'] is num
                              ? '${((g['uptimeSeconds'] as num) / 3600).floor()}h ${(((g['uptimeSeconds'] as num) % 3600) / 60).floor()}m'
                              : '—',
                        ),
                      ],
                    ),
                    color: const Color(0xff29282b),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, c) {
                      final items = [
                        (
                          'Download',
                          piRate(fresh ? _number(a['downloadBps']) : null),
                          Icons.south,
                        ),
                        (
                          'Upload',
                          piRate(fresh ? _number(a['uploadBps']) : null),
                          Icons.north,
                        ),
                        ('Usage today', piBytes(total), Icons.data_usage),
                        (
                          'Pi temperature',
                          g['temperatureC'] is num
                              ? '${(g['temperatureC'] as num).toStringAsFixed(1)}°C'
                              : '—',
                          Icons.thermostat,
                        ),
                      ];
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: items
                            .map(
                              (v) => SizedBox(
                                width: (c.maxWidth - 12) / 2,
                                child: _panel(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(v.$3, size: 19, color: Palette.icy),
                                      const SizedBox(height: 16),
                                      FittedBox(
                                        child: Text(
                                          v.$2,
                                          style: const TextStyle(
                                            fontSize: 23,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        v.$1,
                                        style: const TextStyle(
                                          color: Palette.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${p.stale ? 'Stale · ' : ''}eth1 accounting · sampled ${piTime(traffic['sampleAt'])}',
                    style: const TextStyle(color: Palette.muted, fontSize: 10),
                  ),
                  const SizedBox(height: 16),
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Household history',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Measured daily usage · last 14 days',
                          style: TextStyle(color: Palette.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 20),
                        if (recent.isEmpty)
                          const Text('No saved daily measurements.')
                        else
                          SizedBox(
                            height: 130,
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _UsagePainter(recent),
                            ),
                          ),
                        const SizedBox(height: 12),
                        _line(
                          'VPN today (included)',
                          piBytes(
                            _number(today['vpnDownloadBytes']) != null &&
                                    _number(today['vpnUploadBytes']) != null
                                ? _number(today['vpnDownloadBytes'])! +
                                      _number(today['vpnUploadBytes'])!
                                : null,
                          ),
                        ),
                        _line(
                          'CPU across all cores',
                          g['cpuPercent'] is num
                              ? '${(g['cpuPercent'] as num).toStringAsFixed(1)}%'
                              : 'Awaiting two samples',
                        ),
                        _line(
                          'Active throttling',
                          g['activeThrottling'] == null
                              ? 'Unknown'
                              : g['activeThrottling'] == true
                              ? 'Detected'
                              : 'None',
                        ),
                        const Text(
                          'SQLite local-day totals. Gaps are unmeasured. VPN is a subset; interface totals are not added.',
                          style: TextStyle(
                            color: Palette.muted,
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sync_alt, color: Palette.amber),
                            const SizedBox(width: 9),
                            const Expanded(
                              child: Text(
                                'Router telemetry bridge',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          !p.sharing
                              ? 'Sharing is off. Enable it in Gateway connection.'
                              : p.bridgeError ??
                                    (p.sharedAt == null
                                        ? 'Waiting for a fresh router observation.'
                                        : 'Last shared ${piTime(p.sharedAt!.millisecondsSinceEpoch / 1000)}'),
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 9),
                        const Text(
                          'Foreground only · inventory expires after 60s · no passwords',
                          style: TextStyle(color: Palette.amber, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gateway events',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (events.isEmpty)
                          Text(
                            data['eventsAvailable'] == false
                                ? 'Event history is unavailable.'
                                : 'No observed gateway alerts yet.',
                            style: const TextStyle(color: Palette.muted),
                          ),
                        ...events
                            .take(20)
                            .map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      e['severity'] == 'warning'
                                          ? Icons.warning_amber_rounded
                                          : Icons.info_outline,
                                      size: 19,
                                      color: e['severity'] == 'warning'
                                          ? Palette.amber
                                          : Palette.icy,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${e['message']}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${piTime(e['at'])} · Argon observation',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Palette.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        const Text(
                          'Server-observed history during foreground polling. Connection failures above are local to this phone.',
                          style: TextStyle(
                            color: Palette.muted,
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UsagePainter extends CustomPainter {
  _UsagePainter(this.days);
  final List<Map> days;
  @override
  void paint(Canvas canvas, Size size) {
    double value(Map d) =>
        ((_number(d['downloadBytes']) ?? 0) + (_number(d['uploadBytes']) ?? 0))
            .toDouble();
    final max = days.fold<double>(1, (m, d) => value(d) > m ? value(d) : m);
    final step = size.width / days.length;
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final measured = d['measured'] == true;
      final h = measured
          ? (value(d) / max * (size.height - 25)).clamp(2.0, size.height - 25)
          : 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step + 2, size.height - 20 - h, step - 5, h),
          const Radius.circular(3),
        ),
        Paint()..color = measured ? Palette.icy : Palette.slate,
      );
      final day = '${d['day']}';
      final text = TextPainter(
        text: TextSpan(
          text: day.length >= 10 ? day.substring(8) : '',
          style: const TextStyle(color: Palette.muted, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(i * step + (step - text.width) / 2, size.height - 13),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UsagePainter oldDelegate) =>
      oldDelegate.days != days;
}
