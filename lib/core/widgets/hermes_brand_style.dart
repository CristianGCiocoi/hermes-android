import 'package:flutter/material.dart';

/// Offline-safe Hermes wordmark styling.
///
/// `serif` is resolved by Android's packaged system fonts. Keeping the brand
/// style on the platform font manager makes first paint deterministic and
/// prevents application startup from depending on an external font host.
TextStyle hermesBrandStyle({
  double? fontSize,
  Color? color,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'serif',
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: letterSpacing,
  );
}
