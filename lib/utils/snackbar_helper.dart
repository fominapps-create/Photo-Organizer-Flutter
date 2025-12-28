import 'package:flutter/material.dart';

/// Helper to create styled floating snackbars that appear above the navigation bar
/// with rounded corners and compact sizing
SnackBar createStyledSnackBar(
  String message, {
  Duration duration = const Duration(seconds: 2),
  SnackBarAction? action,
  Color? backgroundColor,
}) {
  return SnackBar(
    content: Text(message),
    duration: duration,
    action: action,
    backgroundColor: backgroundColor,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.only(
      bottom: 80, // Above Samsung navigation bar
      left: 16,
      right: 16,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}
