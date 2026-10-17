import 'package:flutter/material.dart';

import '../models/save_result.dart';

/// Shows the outcome of a router write. Pending results are not presented as
/// success: they explain that the app will confirm after reconnecting.
void showSaveResult(BuildContext context, SaveResult result) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  final (icon, background, foreground) = switch (result.status) {
    SaveStatus.confirmed => (
      Icons.check_circle_rounded,
      const Color(0xff0f7b5f),
      Colors.white,
    ),
    SaveStatus.pendingVerification => (
      Icons.hourglass_top_rounded,
      scheme.inverseSurface,
      scheme.onInverseSurface,
    ),
    SaveStatus.failed => (Icons.error_rounded, scheme.error, scheme.onError),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: background,
        duration: Duration(
          seconds: result.status == SaveStatus.confirmed ? 3 : 6,
        ),
        content: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(result.message, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
}

/// Asks for confirmation before a disruptive action. Returns true only when
/// the user explicitly confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: icon == null
          ? null
          : Icon(icon, color: destructive ? scheme.error : scheme.primary),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}
