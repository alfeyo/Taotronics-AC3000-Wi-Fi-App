import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';

class WanSettingsScreen extends StatefulWidget {
  const WanSettingsScreen({super.key});

  @override
  State<WanSettingsScreen> createState() => _WanSettingsScreenState();
}

class _WanSettingsScreenState extends State<WanSettingsScreen> {
  final _ip = TextEditingController();
  final _mask = TextEditingController();
  final _gateway = TextEditingController();
  final _dns = TextEditingController();
  final _dnsBackup = TextEditingController();
  final _pppoeUser = TextEditingController();
  final _pppoePassword = TextEditingController();
  final _pppoeService = TextEditingController();
  final _pppoeAc = TextEditingController();
  final _vlanId = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _manualDns = false;
  bool _vlanEnabled = false;
  int _wanProto = 0;
  Map<String, dynamic> _primary = {};
  Map<String, dynamic> _secondary = {'WanDisabled': 1};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ip.dispose();
    _mask.dispose();
    _gateway.dispose();
    _dns.dispose();
    _dnsBackup.dispose();
    _pppoeUser.dispose();
    _pppoePassword.dispose();
    _pppoeService.dispose();
    _pppoeAc.dispose();
    _vlanId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response = await context.read<RouterProvider>().loadWanSettings();
    final items = _mapList(response?['Data']);
    if (items.isNotEmpty) {
      final primary = items[0];
      final secondary = items.length > 1 ? items[1] : {'WanDisabled': 1};
      _primary = primary;
      _secondary = secondary;
      _wanProto = _asInt(primary['WanProto']);
      _manualDns = _asInt(primary['ManualDns']) == 1;
      _vlanEnabled = _asInt(primary['VlanDisabled'], fallback: 1) == 0;
      _ip.text = _asText(primary['WanIp']);
      _mask.text = _asText(primary['WanMask']);
      _gateway.text = _asText(primary['WanGateway']);
      _dns.text = _asText(primary['WanDns']);
      _dnsBackup.text = _asText(primary['WanDnsbak']);
      _pppoeUser.text = _asText(primary['PppoeUser']);
      _pppoePassword.text = _asText(primary['PppoePass']);
      _pppoeService.text = _asText(primary['PppoeServiceName']);
      _pppoeAc.text = _asText(primary['PppoeACName']);
      _vlanId.text = _asText(primary['VlanId'], fallback: '0');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final primary = Map<String, dynamic>.from(_primary)
      ..['WanProto'] = _wanProto
      ..['ManualDns'] = _manualDns ? 1 : 0
      ..['VlanDisabled'] = _vlanEnabled ? 0 : 1
      ..['VlanId'] = _number(_vlanId.text);

    if (_wanProto == 1) {
      primary
        ..['WanIp'] = _ip.text.trim()
        ..['WanMask'] = _mask.text.trim()
        ..['WanGateway'] = _gateway.text.trim();
    }
    if (_manualDns || _wanProto == 1) {
      primary
        ..['WanDns'] = _dns.text.trim()
        ..['WanDnsbak'] = _dnsBackup.text.trim();
    }
    if (_wanProto == 2) {
      primary
        ..['PppoeUser'] = _pppoeUser.text.trim()
        ..['PppoePass'] = _pppoePassword.text
        ..['PppoeServiceName'] = _pppoeService.text.trim()
        ..['PppoeACName'] = _pppoeAc.text.trim();
    }

    final success = await context.read<RouterProvider>().updateWanSettings([
      primary,
      Map<String, dynamic>.from(_secondary)
        ..putIfAbsent('WanDisabled', () => 1),
    ]);
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(
      context,
      success,
      'WAN settings saved. The router may reconnect.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'WAN & DNS',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        children: [
          _FormCard(
            title: 'Internet Link',
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _wanProto,
                  decoration: const InputDecoration(
                    labelText: 'Connection type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('DHCP')),
                    DropdownMenuItem(value: 1, child: Text('Static IP')),
                    DropdownMenuItem(value: 2, child: Text('PPPoE')),
                    DropdownMenuItem(value: 3, child: Text('Bridge')),
                  ],
                  onChanged: (value) => setState(() => _wanProto = value ?? 0),
                ),
                if (_wanProto == 1) ...[
                  _gap,
                  _field(_ip, 'WAN IP address', icon: Icons.language),
                  _gap,
                  _field(_mask, 'Subnet mask', icon: Icons.grid_4x4),
                  _gap,
                  _field(_gateway, 'Gateway', icon: Icons.route),
                ],
                if (_wanProto == 2) ...[
                  _gap,
                  _field(_pppoeUser, 'PPPoE username', icon: Icons.person),
                  _gap,
                  _field(
                    _pppoePassword,
                    'PPPoE password',
                    icon: Icons.password,
                    obscure: true,
                  ),
                  _gap,
                  _field(_pppoeService, 'Service name', icon: Icons.badge),
                  _gap,
                  _field(_pppoeAc, 'Access concentrator', icon: Icons.hub),
                ],
              ],
            ),
          ),
          _FormCard(
            title: 'DNS',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _manualDns || _wanProto == 1,
                  onChanged: _wanProto == 1
                      ? null
                      : (value) => setState(() => _manualDns = value),
                  title: const Text('Use custom DNS'),
                  subtitle: const Text('Static IP always uses manual DNS.'),
                ),
                if (_manualDns || _wanProto == 1) ...[
                  _field(_dns, 'Primary DNS', icon: Icons.dns),
                  _gap,
                  _field(_dnsBackup, 'Secondary DNS', icon: Icons.dns_outlined),
                ],
              ],
            ),
          ),
          _FormCard(
            title: 'WAN VLAN',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _vlanEnabled,
                  onChanged: (value) => setState(() => _vlanEnabled = value),
                  title: const Text('Enable VLAN tagging'),
                ),
                if (_vlanEnabled)
                  _field(
                    _vlanId,
                    'VLAN ID',
                    icon: Icons.tag,
                    keyboardType: TextInputType.number,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LanSettingsScreen extends StatefulWidget {
  const LanSettingsScreen({super.key});

  @override
  State<LanSettingsScreen> createState() => _LanSettingsScreenState();
}

class _LanSettingsScreenState extends State<LanSettingsScreen> {
  final _lanIp = TextEditingController();
  final _lanMask = TextEditingController();
  final _dhcpStart = TextEditingController();
  final _dhcpEnd = TextEditingController();
  final _vlanId = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _vlanEnabled = false;
  Map<String, dynamic> _lan = {};
  Map<String, dynamic> _dhcp = {};
  Map<String, dynamic> _vlan = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lanIp.dispose();
    _lanMask.dispose();
    _dhcpStart.dispose();
    _dhcpEnd.dispose();
    _vlanId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response = await context.read<RouterProvider>().loadLanSettings();
    final items = _mapList(response?['Data']);
    if (items.isNotEmpty) {
      _lan = items[0];
      if (items.length > 1) _dhcp = items[1];
      if (items.length > 2) _vlan = items[2];
      _lanIp.text = _asText(_lan['LanIp']);
      _lanMask.text = _asText(_lan['LanMask']);
      _dhcpStart.text = _asText(_dhcp['DhcpStartAddr']);
      _dhcpEnd.text = _asText(_dhcp['DhcpEndAddr']);
      _vlanEnabled = _asInt(_vlan['VlanEnable']) == 1;
      _vlanId.text = _asText(_vlan['Vlanid'], fallback: '0');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final success = await context.read<RouterProvider>().updateLanSettings([
      Map<String, dynamic>.from(_lan)
        ..['LanIp'] = _lanIp.text.trim()
        ..['LanMask'] = _lanMask.text.trim(),
      Map<String, dynamic>.from(_dhcp)
        ..['DhcpStartAddr'] = _dhcpStart.text.trim()
        ..['DhcpEndAddr'] = _dhcpEnd.text.trim(),
      Map<String, dynamic>.from(_vlan)
        ..['VlanEnable'] = _vlanEnabled ? 1 : 0
        ..['Vlanid'] = _number(_vlanId.text),
    ]);
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(
      context,
      success,
      'LAN settings saved. The local IP may change.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'LAN Settings',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        children: [
          _FormCard(
            title: 'Router Address',
            child: Column(
              children: [
                _field(_lanIp, 'LAN IP address', icon: Icons.lan),
                _gap,
                _field(_lanMask, 'Subnet mask', icon: Icons.grid_4x4),
              ],
            ),
          ),
          _FormCard(
            title: 'DHCP Range',
            child: Column(
              children: [
                _field(_dhcpStart, 'Start address', icon: Icons.play_arrow),
                _gap,
                _field(_dhcpEnd, 'End address', icon: Icons.stop),
              ],
            ),
          ),
          _FormCard(
            title: 'LAN VLAN',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _vlanEnabled,
                  onChanged: (value) => setState(() => _vlanEnabled = value),
                  title: const Text('Enable VLAN'),
                ),
                if (_vlanEnabled)
                  _field(
                    _vlanId,
                    'VLAN ID',
                    icon: Icons.tag,
                    keyboardType: TextInputType.number,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GuestWifiSettingsScreen extends StatefulWidget {
  const GuestWifiSettingsScreen({super.key});

  @override
  State<GuestWifiSettingsScreen> createState() =>
      _GuestWifiSettingsScreenState();
}

class _GuestWifiSettingsScreenState extends State<GuestWifiSettingsScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  int _encryption = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response = await context
        .read<RouterProvider>()
        .loadGuestWifiSettings();
    final guest = _firstMap(response?['Data']);
    if (guest != null) {
      _enabled = _asInt(guest['Enable']) == 1;
      _ssid.text = _asText(guest['Ssid']);
      _password.text = _asText(guest['Password']);
      _encryption = _asInt(guest['EncryptionWay'], fallback: 3);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <String, dynamic>{'Enable': _enabled ? 1 : 0};
    if (_enabled) {
      payload
        ..['Ssid'] = _ssid.text.trim()
        ..['EncryptionWay'] = _encryption;
      if (_encryption > 0) payload['Password'] = _password.text;
    }
    final success = await context
        .read<RouterProvider>()
        .updateGuestWifiSettings(payload);
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(context, success, 'Guest Wi-Fi settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Guest Wi-Fi',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: _FormCard(
        title: 'Visitor Network',
        child: Column(
          children: [
            SwitchListTile.adaptive(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Enable guest Wi-Fi'),
            ),
            if (_enabled) ...[
              _field(_ssid, 'Guest network name', icon: Icons.wifi),
              _gap,
              DropdownButtonFormField<int>(
                initialValue: _encryption,
                decoration: const InputDecoration(labelText: 'Security'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Open')),
                  DropdownMenuItem(value: 2, child: Text('WPA-PSK')),
                  DropdownMenuItem(value: 3, child: Text('WPA2-PSK')),
                  DropdownMenuItem(value: 4, child: Text('WPA/WPA2')),
                ],
                onChanged: (value) => setState(() => _encryption = value ?? 3),
              ),
              if (_encryption > 0) ...[
                _gap,
                _field(
                  _password,
                  'Guest password',
                  icon: Icons.password,
                  obscure: true,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _dmzHost = TextEditingController();
  final _fastNatPorts = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _firewall = false;
  bool _upnp = false;
  bool _dmz = false;
  bool _fastNat = false;
  bool _autoFilter = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dmzHost.dispose();
    _fastNatPorts.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<RouterProvider>();
    final responses = await Future.wait([
      provider.loadFirewallSettings(),
      provider.loadUpnpDmzSettings(),
      provider.loadFastNatSettings(),
    ]);
    final firewall = _dataMap(responses[0]?['Data']);
    final upnp = _mapList(responses[1]?['Data']);
    final fastNat = _dataMap(responses[2]?['Data']);
    _firewall = _asInt(firewall?['Enable']) == 1;
    if (upnp.isNotEmpty) _upnp = _asInt(upnp[0]['UpnpEnabled']) == 1;
    if (upnp.length > 1) {
      _dmz = _asInt(upnp[1]['DmzEnabled']) == 1;
      _dmzHost.text = _asText(upnp[1]['HostIpaddr']);
    }
    _fastNat = _asInt(fastNat?['FastnatEnable']) == 1;
    _autoFilter = _asInt(fastNat?['AutoFilter']) == 1;
    _fastNatPorts.text = _asText(fastNat?['PortList']);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final provider = context.read<RouterProvider>();
    final results = await Future.wait([
      provider.updateFirewallSettings(_firewall),
      provider.updateUpnpDmzSettings(
        upnpEnabled: _upnp,
        dmzEnabled: _dmz,
        dmzHost: _dmzHost.text.trim(),
      ),
      provider.updateFastNatSettings(
        enabled: _fastNat,
        autoFilter: _autoFilter,
        portList: _fastNatPorts.text.trim(),
      ),
    ]);
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(
      context,
      results.every((result) => result),
      'Security settings saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Security & NAT',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        children: [
          _FormCard(
            title: 'Firewall',
            child: SwitchListTile.adaptive(
              value: _firewall,
              onChanged: (value) => setState(() => _firewall = value),
              title: const Text('Enable router firewall'),
            ),
          ),
          _FormCard(
            title: 'UPnP & DMZ',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _upnp,
                  onChanged: (value) => setState(() => _upnp = value),
                  title: const Text('Enable UPnP'),
                ),
                SwitchListTile.adaptive(
                  value: _dmz,
                  onChanged: (value) => setState(() => _dmz = value),
                  title: const Text('Enable DMZ host'),
                ),
                if (_dmz)
                  _field(_dmzHost, 'DMZ host IP', icon: Icons.desktop_windows),
              ],
            ),
          ),
          _FormCard(
            title: 'Fast NAT',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _fastNat,
                  onChanged: (value) => setState(() => _fastNat = value),
                  title: const Text('Enable Fast NAT'),
                ),
                SwitchListTile.adaptive(
                  value: _autoFilter,
                  onChanged: (value) => setState(() => _autoFilter = value),
                  title: const Text('Automatic port filter'),
                ),
                _field(
                  _fastNatPorts,
                  'Port list',
                  icon: Icons.filter_alt,
                  helper: 'Use the same port list format as the router app.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QosSettingsScreen extends StatefulWidget {
  const QosSettingsScreen({super.key});

  @override
  State<QosSettingsScreen> createState() => _QosSettingsScreenState();
}

class _QosSettingsScreenState extends State<QosSettingsScreen> {
  final _up = TextEditingController();
  final _down = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _up.dispose();
    _down.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response = await context.read<RouterProvider>().loadQosSettings();
    final data = _dataMap(response?['Data']);
    _enabled = _asInt(data?['Enable']) == 1;
    _up.text = _asText(data?['UpBandwidth'], fallback: '0');
    _down.text = _asText(data?['DownBandwidth'], fallback: '0');
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final success = await context.read<RouterProvider>().updateQosSettings(
      enabled: _enabled,
      upBandwidth: _number(_up.text),
      downBandwidth: _number(_down.text),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(context, success, 'QoS settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'QoS',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: _FormCard(
        title: 'Bandwidth Control',
        child: Column(
          children: [
            SwitchListTile.adaptive(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Enable QoS'),
            ),
            if (_enabled) ...[
              _field(
                _up,
                'Upload bandwidth',
                icon: Icons.upload,
                keyboardType: TextInputType.number,
              ),
              _gap,
              _field(
                _down,
                'Download bandwidth',
                icon: Icons.download,
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class VpnSettingsScreen extends StatefulWidget {
  const VpnSettingsScreen({super.key});

  @override
  State<VpnSettingsScreen> createState() => _VpnSettingsScreenState();
}

class _VpnSettingsScreenState extends State<VpnSettingsScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _psk = TextEditingController();
  final _innerNet = TextEditingController();
  final _innerMask = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _mppe = false;
  int _mode = 0;
  String _status = 'Not checked';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    _psk.dispose();
    _innerNet.dispose();
    _innerMask.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<RouterProvider>();
    final responses = await Future.wait([
      provider.loadVpnSettings(),
      provider.loadVpnStatus(),
    ]);
    final data = _firstMap(responses[0]?['Data']);
    final status = _dataMap(responses[1]?['Data']);
    if (data != null) {
      _mode = _asInt(data['VpnEnable']);
      _server.text = _asText(data['VpnServer']);
      _user.text = _asText(data['VpnUser']);
      _password.text = _asText(data['VpnPass']);
      _psk.text = _asText(data['IpsecPsk']);
      _mppe = _asInt(data['VpnPPTPMppe']) == 1;
      _innerNet.text = _asText(data['VpnInnerNet']);
      _innerMask.text = _asText(data['VpnInnerMask']);
    }
    _status = switch (_asInt(status?['Status'], fallback: -1)) {
      1 => 'Connected',
      2 => 'Connecting',
      0 => 'Disconnected',
      _ => 'Unavailable',
    };
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <String, dynamic>{'VpnEnable': _mode};
    if (_mode > 0) {
      payload
        ..['VpnServer'] = _server.text.trim()
        ..['VpnUser'] = _user.text.trim()
        ..['VpnPass'] = _password.text
        ..['VpnInnerNet'] = _innerNet.text.trim()
        ..['VpnInnerMask'] = _innerMask.text.trim();
      if (_mode == 1) payload['VpnPPTPMppe'] = _mppe ? 1 : 0;
      if (_mode == 2) payload['IpsecPsk'] = _psk.text;
    }
    final success = await context.read<RouterProvider>().updateVpnSettings(
      payload,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(context, success, 'VPN settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'VPN Client',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        children: [
          _FormCard(
            title: 'VPN Mode',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Router status'),
                  trailing: Text(_status),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _mode,
                  decoration: const InputDecoration(
                    labelText: 'Connection type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Disabled')),
                    DropdownMenuItem(value: 1, child: Text('PPTP')),
                    DropdownMenuItem(value: 2, child: Text('L2TP / IPsec')),
                  ],
                  onChanged: (value) => setState(() => _mode = value ?? 0),
                ),
              ],
            ),
          ),
          if (_mode > 0)
            _FormCard(
              title: 'Credentials',
              child: Column(
                children: [
                  _field(_server, 'VPN server', icon: Icons.cloud),
                  _gap,
                  _field(_user, 'Username', icon: Icons.person),
                  _gap,
                  _field(
                    _password,
                    'Password',
                    icon: Icons.password,
                    obscure: true,
                  ),
                  if (_mode == 2) ...[
                    _gap,
                    _field(
                      _psk,
                      'IPsec pre-shared key',
                      icon: Icons.key,
                      obscure: true,
                    ),
                  ],
                  if (_mode == 1)
                    SwitchListTile.adaptive(
                      value: _mppe,
                      onChanged: (value) => setState(() => _mppe = value),
                      title: const Text('Enable PPTP MPPE'),
                    ),
                ],
              ),
            ),
          if (_mode > 0)
            _FormCard(
              title: 'VPN Inner Network',
              child: Column(
                children: [
                  _field(_innerNet, 'Inner network', icon: Icons.lan),
                  _gap,
                  _field(_innerMask, 'Inner mask', icon: Icons.grid_4x4),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PortForwardingScreen extends StatefulWidget {
  const PortForwardingScreen({super.key});

  @override
  State<PortForwardingScreen> createState() => _PortForwardingScreenState();
}

class _PortForwardingScreenState extends State<PortForwardingScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response = await context.read<RouterProvider>().loadVirtualServers();
    _rules = _mapList(response?['Data']);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Map<String, dynamic>? rule]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _VirtualServerEditor(rule: rule),
    );
    if (result == null || !mounted) return;
    final provider = context.read<RouterProvider>();
    final success = rule == null
        ? await provider.addVirtualServer(result)
        : await provider.updateVirtualServer(result);
    if (!mounted) return;
    _showResult(
      context,
      success,
      rule == null ? 'Rule added.' : 'Rule updated.',
    );
    if (success) {
      setState(() => _loading = true);
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> rule) async {
    final index = _asText(rule['Index']);
    if (index.isEmpty) return;
    final success = await context.read<RouterProvider>().deleteVirtualServer(
      index,
    );
    if (!mounted) return;
    _showResult(context, success, 'Rule deleted.');
    if (success) {
      setState(() => _loading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Port Forwarding',
      loading: _loading,
      onRefresh: _load,
      actions: [
        IconButton(
          onPressed: () => _edit(),
          tooltip: 'Add rule',
          icon: const Icon(Icons.add),
        ),
      ],
      child: _rules.isEmpty
          ? const _EmptySettings(
              icon: Icons.router,
              title: 'No virtual servers',
              subtitle: 'Add a port forwarding rule for a local device.',
            )
          : Column(
              children: _rules.map((rule) {
                final internal =
                    '${_asText(rule['InternalStartPort'])}-${_asText(rule['InternalEndPort'])}';
                final external =
                    '${_asText(rule['ExternalStartPort'])}-${_asText(rule['ExternalEndPort'])}';
                return Card(
                  child: ListTile(
                    title: Text(
                      _asText(
                        rule['DeviceNickName'],
                        fallback: _asText(
                          rule['DeviceHostName'],
                          fallback: 'Forwarding rule',
                        ),
                      ),
                    ),
                    subtitle: Text(
                      '${_asText(rule['DeviceIpaddr'], fallback: 'No IP')} | '
                      'External $external to internal $internal | '
                      '${_protocolLabel(_asInt(rule['Protocol']))}',
                    ),
                    onTap: () => _edit(rule),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _delete(rule),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class DdnsSettingsScreen extends StatefulWidget {
  const DdnsSettingsScreen({super.key});

  @override
  State<DdnsSettingsScreen> createState() => _DdnsSettingsScreenState();
}

class _DdnsSettingsScreenState extends State<DdnsSettingsScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _host = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  int _service = 0;
  String _status = 'Not checked';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _host.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<RouterProvider>();
    final responses = await Future.wait([
      provider.loadDdnsSettings(),
      provider.loadDdnsStatus(),
    ]);
    final data = _firstMap(responses[0]?['Data']);
    final status = _dataMap(responses[1]?['Data']);
    if (data != null) {
      _enabled = _asInt(data['Enable']) == 1;
      _service = _asInt(data['Service']);
      _user.text = _asText(data['UserName']);
      _password.text = _asText(data['PassWord']);
      _host.text = _asText(data['HostName']);
    }
    _status = switch (_asInt(status?['Status'], fallback: -1)) {
      0 => 'Updated',
      1 => 'Updating',
      2 => 'Failed',
      _ => 'Unavailable',
    };
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <String, dynamic>{'Enable': _enabled ? 1 : 0};
    if (_enabled) {
      payload
        ..['Service'] = _service
        ..['UserName'] = _user.text.trim()
        ..['PassWord'] = _password.text
        ..['HostName'] = _host.text.trim();
    }
    final success = await context.read<RouterProvider>().updateDdnsSettings(
      payload,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(context, success, 'DDNS settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'DDNS',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: _FormCard(
        title: 'Dynamic DNS',
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Provider status'),
              trailing: Text(_status),
            ),
            SwitchListTile.adaptive(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Enable DDNS'),
            ),
            if (_enabled) ...[
              DropdownButtonFormField<int>(
                initialValue: _service,
                decoration: const InputDecoration(labelText: 'Service'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Service 1')),
                  DropdownMenuItem(value: 1, child: Text('Service 2')),
                  DropdownMenuItem(value: 2, child: Text('Service 3')),
                ],
                onChanged: (value) => setState(() => _service = value ?? 0),
              ),
              _gap,
              _field(_user, 'Username', icon: Icons.person),
              _gap,
              _field(
                _password,
                'Password',
                icon: Icons.password,
                obscure: true,
              ),
              _gap,
              _field(_host, 'Host name', icon: Icons.public),
            ],
          ],
        ),
      ),
    );
  }
}

class NodeLedSettingsScreen extends StatefulWidget {
  const NodeLedSettingsScreen({super.key});

  @override
  State<NodeLedSettingsScreen> createState() => _NodeLedSettingsScreenState();
}

class _NodeLedSettingsScreenState extends State<NodeLedSettingsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _nodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response = await context.read<RouterProvider>().loadLedSettings();
    _nodes = _mapList(response?['Data']);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setLed(Map<String, dynamic> node, bool enabled) async {
    final success = await context.read<RouterProvider>().updateNodeLed(
      nodeSn: _asText(node['NodeSn']),
      led: enabled ? 1 : 0,
    );
    if (!mounted) return;
    _showResult(context, success, 'LED updated.');
    if (success) {
      node['Led'] = enabled ? 1 : 0;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Router LEDs',
      loading: _loading,
      onRefresh: _load,
      child: _nodes.isEmpty
          ? const _EmptySettings(
              icon: Icons.lightbulb_outline,
              title: 'No LED-capable node reported',
              subtitle: 'Refresh after the mesh nodes finish connecting.',
            )
          : Column(
              children: _nodes.map((node) {
                return Card(
                  child: SwitchListTile.adaptive(
                    value: _asInt(node['Led']) == 1,
                    onChanged: (value) => _setLed(node, value),
                    title: Text(
                      _asText(node['NickName'], fallback: 'Mesh node'),
                    ),
                    subtitle: Text(_asText(node['NodeSn'])),
                    secondary: const Icon(Icons.lightbulb_outline),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class RestartScheduleScreen extends StatefulWidget {
  const RestartScheduleScreen({super.key});

  @override
  State<RestartScheduleScreen> createState() => _RestartScheduleScreenState();
}

class _RestartScheduleScreenState extends State<RestartScheduleScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: 3, minute: 0);
  final Set<int> _days = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response = await context.read<RouterProvider>().loadRestartSchedule();
    final data = _firstMap(response?['Data']);
    if (data != null) {
      _enabled = _asInt(data['RestartSwitch']) == 1;
      _time = TimeOfDay(
        hour: _asInt(data['RestartHour']),
        minute: _asInt(data['RestartMinute']),
      );
      _days
        ..clear()
        ..addAll(_decodeRestartDays(_asText(data['RestartDay'])));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chooseTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null) setState(() => _time = time);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = <String, dynamic>{'RestartSwitch': _enabled ? 1 : 0};
    if (_enabled) {
      payload
        ..['RestartDay'] = _encodeRestartDays(_days)
        ..['RestartHour'] = _time.hour
        ..['RestartMinute'] = _time.minute;
    }
    final success = await context.read<RouterProvider>().updateRestartSchedule(
      payload,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showResult(context, success, 'Restart schedule saved.');
  }

  Future<void> _rebootNow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart router now?'),
        content: const Text('Devices will disconnect while the mesh restarts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final success = await context.read<RouterProvider>().rebootRouter();
    if (mounted) _showResult(context, success, 'Router restart requested.');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Restart Controls',
      loading: _loading,
      onRefresh: _load,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        children: [
          _FormCard(
            title: 'Schedule',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  title: const Text('Enable scheduled restart'),
                ),
                if (_enabled) ...[
                  OutlinedButton.icon(
                    onPressed: _chooseTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(_time.format(context)),
                  ),
                  _gap,
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (day) {
                      return FilterChip(
                        label: Text(_restartDayLabel(day)),
                        selected: _days.contains(day),
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _days.add(day);
                            } else {
                              _days.remove(day);
                            }
                          });
                        },
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
          _FormCard(
            title: 'Immediate Restart',
            child: FilledButton.icon(
              onPressed: _rebootNow,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart now'),
            ),
          ),
        ],
      ),
    );
  }
}

class FirmwareStatusScreen extends StatelessWidget {
  const FirmwareStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RouterProvider>(
      builder: (context, provider, child) {
        final nodes = provider.nodes;
        return Scaffold(
          appBar: AppBar(title: const Text('Firmware')),
          body: RefreshIndicator(
            onRefresh: provider.refreshNodes,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _FormCard(
                  title: 'Update Path',
                  child: Text(
                    'The router exposes node version and upgrade commands, '
                    'but the original app also checks update metadata before '
                    'starting an upgrade. This screen keeps firmware status '
                    'visible without sending an unsafe upgrade request.',
                  ),
                ),
                _FormCard(
                  title: 'Mesh Nodes',
                  child: nodes.isEmpty
                      ? const Text('No nodes reported yet.')
                      : Column(
                          children: nodes.map((node) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.router),
                              title: Text(node.displayName),
                              subtitle: Text(
                                '${node.model ?? 'Unknown model'} | ${node.sn}'
                                '${node.firmwareVersion == null ? '' : ' | ${node.firmwareVersion}'}',
                              ),
                            );
                          }).toList(),
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

class _VirtualServerEditor extends StatefulWidget {
  const _VirtualServerEditor({this.rule});

  final Map<String, dynamic>? rule;

  @override
  State<_VirtualServerEditor> createState() => _VirtualServerEditorState();
}

class _VirtualServerEditorState extends State<_VirtualServerEditor> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _mac;
  late final TextEditingController _ip;
  late final TextEditingController _externalStart;
  late final TextEditingController _externalEnd;
  late final TextEditingController _internalStart;
  late final TextEditingController _internalEnd;
  late int _protocol;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule ?? {};
    _name = TextEditingController(text: _asText(rule['DeviceNickName']));
    _host = TextEditingController(text: _asText(rule['DeviceHostName']));
    _mac = TextEditingController(text: _asText(rule['DeviceMacaddr']));
    _ip = TextEditingController(text: _asText(rule['DeviceIpaddr']));
    _externalStart = TextEditingController(
      text: _asText(rule['ExternalStartPort']),
    );
    _externalEnd = TextEditingController(
      text: _asText(rule['ExternalEndPort']),
    );
    _internalStart = TextEditingController(
      text: _asText(rule['InternalStartPort']),
    );
    _internalEnd = TextEditingController(
      text: _asText(rule['InternalEndPort']),
    );
    _protocol = _asInt(rule['Protocol']);
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _mac.dispose();
    _ip.dispose();
    _externalStart.dispose();
    _externalEnd.dispose();
    _internalStart.dispose();
    _internalEnd.dispose();
    super.dispose();
  }

  void _finish() {
    final old = widget.rule ?? {};
    Navigator.pop(context, <String, dynamic>{
      'Index': _asText(
        old['Index'],
        fallback: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      ),
      'DeviceSystemType': _asInt(old['DeviceSystemType']),
      'DeviceNickName': _name.text.trim(),
      'DeviceHostName': _host.text.trim(),
      'DeviceMacaddr': _mac.text.trim(),
      'DeviceIpaddr': _ip.text.trim(),
      'Protocol': _protocol,
      'ExternalStartPort': _number(_externalStart.text),
      'ExternalEndPort': _number(_externalEnd.text),
      'InternalStartPort': _number(_internalStart.text),
      'InternalEndPort': _number(_internalEnd.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        top: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.rule == null ? 'Add rule' : 'Edit rule'),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            _field(_name, 'Device nickname', icon: Icons.label),
            _gap,
            _field(_host, 'Device host name', icon: Icons.computer),
            _gap,
            _field(_ip, 'Device IP', icon: Icons.lan),
            _gap,
            _field(_mac, 'Device MAC', icon: Icons.fingerprint),
            _gap,
            DropdownButtonFormField<int>(
              initialValue: _protocol,
              decoration: const InputDecoration(labelText: 'Protocol'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('TCP')),
                DropdownMenuItem(value: 1, child: Text('UDP')),
                DropdownMenuItem(value: 2, child: Text('TCP + UDP')),
              ],
              onChanged: (value) => setState(() => _protocol = value ?? 0),
            ),
            _gap,
            Row(
              children: [
                Expanded(
                  child: _field(
                    _externalStart,
                    'External start',
                    icon: Icons.login,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _externalEnd,
                    'External end',
                    icon: Icons.logout,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            _gap,
            Row(
              children: [
                Expanded(
                  child: _field(
                    _internalStart,
                    'Internal start',
                    icon: Icons.login,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _internalEnd,
                    'Internal end',
                    icon: Icons.logout,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            _gap,
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _finish,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.title,
    required this.loading,
    required this.onRefresh,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final bool loading;
  final Future<void> Function() onRefresh;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [child, const SizedBox(height: 24)],
              ),
            ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptySettings extends StatelessWidget {
  const _EmptySettings({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

const _gap = SizedBox(height: 12);

TextField _field(
  TextEditingController controller,
  String label, {
  required IconData icon,
  bool obscure = false,
  TextInputType? keyboardType,
  String? helper,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    ),
  );
}

Map<String, dynamic>? _dataMap(dynamic data) {
  if (data is Map) return Map<String, dynamic>.from(data);
  return null;
}

Map<String, dynamic>? _firstMap(dynamic data) {
  if (data is List && data.isNotEmpty && data.first is Map) {
    return Map<String, dynamic>.from(data.first as Map);
  }
  return _dataMap(data);
}

List<Map<String, dynamic>> _mapList(dynamic data) {
  if (data is! List) return [];
  return data
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}') ?? fallback;
}

int _number(String value) => int.tryParse(value.trim()) ?? 0;

String _asText(dynamic value, {String fallback = ''}) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

String _protocolLabel(int protocol) {
  return switch (protocol) {
    1 => 'UDP',
    2 => 'TCP + UDP',
    _ => 'TCP',
  };
}

Set<int> _decodeRestartDays(String value) {
  if (value.length < 7) return {};
  return {
    for (var index = 0; index < 7; index++)
      if (value[index] == '1') index,
  };
}

String _encodeRestartDays(Set<int> days) {
  return List.generate(7, (day) => days.contains(day) ? '1' : '0').join();
}

String _restartDayLabel(int day) {
  return const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][day];
}

void _showResult(BuildContext context, bool success, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        success ? message : 'Update failed. Check diagnostics logs.',
      ),
    ),
  );
}
