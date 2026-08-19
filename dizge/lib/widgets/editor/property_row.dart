/// Editörün açılır özellik satırı.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Özellik satırı: ikon + etiket + değer; dokununca altı açılır.
class PropertyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color? valueColor;
  final bool open;
  final VoidCallback onTap;
  final Widget child;

  const PropertyRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
    this.valueColor,
    required this.open,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.hair),
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.curve,
        decoration: BoxDecoration(
          color: open ? c.hover : Colors.transparent,
          borderRadius: R.radiusMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: R.radiusMd,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: S.md,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: I.sm, color: c.inkDim),
                    const SizedBox(width: S.md),
                    SizedBox(
                      width: 76,
                      child: Text(
                        label,
                        style: TextStyle(color: c.inkDim, fontSize: T.body),
                      ),
                    ),
                    Expanded(
                      child: valueWidget != null
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: valueWidget!,
                            )
                          : Text(
                              value ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: (value == 'Boş')
                                    ? c.inkFaint
                                    : (valueColor ?? c.ink),
                                fontSize: T.strong,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: Motion.base,
                      curve: Motion.curve,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: I.md,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.lg),
                      child: child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
