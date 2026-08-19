/// Hafta ekranının üst yüzeyi.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Gün başlıkları + saatsiz şeridini taşıyan yükseltilmiş yüzey.
class WeekChrome extends StatelessWidget {
  const WeekChrome({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.lineSoft)),
        boxShadow: c.shadowSm,
      ),
      child: child,
    );
  }
}
