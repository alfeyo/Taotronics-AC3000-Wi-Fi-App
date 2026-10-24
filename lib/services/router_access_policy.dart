/// Who may hold the TaoTronics router's management session.
///
/// The router serves **one management client at a time**. Every command from
/// another client is answered with `ErrorCode 5`, and access moves to a
/// waiting client about 60-80 s after the holder stops sending requests.
/// See `docs/MULTI_DEVICE_CONNECTION_REVIEW.md` §3.
///
/// This policy is the single decision point the app consults before it
/// discovers, connects to, authenticates with, reads from or writes to the
/// router. Phase 1 of `docs/ROUTER_CONTROL_MIGRATION_PLAN.md` keeps direct
/// control available by default and yields only when Argon (the Raspberry Pi)
/// reports that it owns the router.
class RouterAccessPolicy {
  RouterAccessPolicy({
    this.directControlEnabled = true,
    this.preferPiController = false,
    this.blockDirectOwnership = false,
    this.diagnosticsOnly = false,
  });

  /// Master switch for the direct MQTT path. False means the app may not touch
  /// the router at all, whatever the other flags say.
  bool directControlEnabled;

  /// Argon is the preferred controller. Set with [blockDirectOwnership] when
  /// the Pi reports ownership; kept separate so a future phase can prefer the
  /// Pi without forbidding direct control outright.
  bool preferPiController;

  /// Hard stop. Argon reported that it holds the router session, so this app
  /// must not connect, probe, refresh, reconnect or write.
  bool blockDirectOwnership;

  /// Read-only mode: reads and probes stay available, writes are refused.
  bool diagnosticsOnly;

  /// Direct control is possible at all.
  bool get _direct => directControlEnabled && !blockDirectOwnership;

  bool get mayDiscover => _direct;
  bool get mayConnect => _direct;
  bool get mayAuthenticate => _direct;
  bool get mayProbe => _direct;
  bool get mayRefresh => _direct;

  /// Read-level permission for the transport backstop.
  bool get maySendCommands => _direct;

  /// Writes additionally require that the app is not in diagnostics-only mode.
  bool get mayWrite => _direct && !diagnosticsOnly;

  bool get mayAutoReconnect => _direct;

  /// True when screens should render cached values without offering writes.
  bool get isReadOnly => !_direct || diagnosticsOnly;

  /// Shown wherever router access is refused in the default Argon mode.
  static const directControlOffMessage =
      'Argon monitors the router. Take Direct Router Control to change '
      'router settings from this phone.';

  /// Shown wherever a write is refused because Argon controls the router.
  static const piOwnershipMessage =
      'Router control is provided by Network Hub.';

  static const piOwnershipDetail =
      'The Raspberry Pi holds the router connection. Values here are the last '
      'ones it reported, and settings cannot be changed from this phone.';

  /// The user-facing reason direct control is unavailable, or null when it is.
  String? get blockMessage {
    if (!directControlEnabled) {
      return directControlOffMessage;
    }
    if (blockDirectOwnership) return piOwnershipMessage;
    return null;
  }

  /// Records Argon's ownership claim. Returns true when it changed anything, so
  /// the caller can cancel or restart timers exactly once.
  bool setPiOwnership({required bool ownedByArgon}) {
    if (blockDirectOwnership == ownedByArgon &&
        preferPiController == ownedByArgon) {
      return false;
    }
    blockDirectOwnership = ownedByArgon;
    preferPiController = ownedByArgon;
    return true;
  }

  RouterAccessPolicy copyWith({
    bool? directControlEnabled,
    bool? preferPiController,
    bool? blockDirectOwnership,
    bool? diagnosticsOnly,
  }) => RouterAccessPolicy(
    directControlEnabled: directControlEnabled ?? this.directControlEnabled,
    preferPiController: preferPiController ?? this.preferPiController,
    blockDirectOwnership: blockDirectOwnership ?? this.blockDirectOwnership,
    diagnosticsOnly: diagnosticsOnly ?? this.diagnosticsOnly,
  );

  @override
  String toString() =>
      'RouterAccessPolicy(direct: $directControlEnabled, '
      'preferPi: $preferPiController, blocked: $blockDirectOwnership, '
      'diagnosticsOnly: $diagnosticsOnly)';
}
