/// Outcome of a configuration write to the router.
enum SaveStatus {
  /// The router acknowledged the change with ErrorCode 0.
  confirmed,

  /// The request was sent but the connection dropped before the router
  /// answered (expected for Wi-Fi, WAN and LAN changes). The app re-reads the
  /// setting after reconnecting; see [PendingChange].
  pendingVerification,

  /// The router rejected the change, or did not answer a change that should
  /// not interrupt the connection.
  failed,
}

class SaveResult {
  const SaveResult(this.status, this.message);

  const SaveResult.confirmed(String message)
    : this(SaveStatus.confirmed, message);

  const SaveResult.pending(String message)
    : this(SaveStatus.pendingVerification, message);

  const SaveResult.failed(String message) : this(SaveStatus.failed, message);

  final SaveStatus status;
  final String message;

  bool get isConfirmed => status == SaveStatus.confirmed;
  bool get isFailed => status == SaveStatus.failed;

  /// True unless the router explicitly rejected or ignored the change.
  bool get accepted => status != SaveStatus.failed;
}

enum ChangeStatus {
  /// Waiting to reconnect and re-read the setting.
  verifying,

  /// The router reports the new values.
  confirmed,

  /// The router reports different values from the ones that were sent.
  mismatch,

  /// The setting could not be read back (still offline or unsupported).
  unverified,
}

/// A configuration change whose result is confirmed after reconnecting.
class PendingChange {
  PendingChange({required this.id, required this.label})
    : startedAt = DateTime.now();

  final int id;
  final String label;
  final DateTime startedAt;
  ChangeStatus status = ChangeStatus.verifying;

  String get message => switch (status) {
    ChangeStatus.verifying =>
      '$label sent. Checking the router after it reconnects...',
    ChangeStatus.confirmed =>
      '$label applied. The router reports the new settings.',
    ChangeStatus.mismatch =>
      '$label was not applied. The router still reports different values.',
    ChangeStatus.unverified =>
      '$label could not be confirmed. Reconnect to the router and check the setting.',
  };
}
