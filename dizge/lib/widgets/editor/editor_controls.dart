/// Editörün ortak seçim parçaları: büyük kart, çip, etiket ve ikili anahtar.
///
/// Hiçbiri durum tutmuyor — değer alıp dokunuşu geri bildiriyorlar. Bu yüzden
/// sayfadan en temiz ayrılan parçalar bunlar.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Tür seçimindeki büyük kart (Tek günlük / Rutin).
class BigChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const BigChoice({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface,
            borderRadius: R.radiusSm,
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: I.md,
                color: selected ? c.navActiveInk : c.inkDim,
              ),
              const SizedBox(height: S.sm),
              Text(
                title,
                style: TextStyle(
                  color: selected ? c.navActiveInk : c.ink,
                  fontSize: T.strong,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.hair),
              Text(
                subtitle,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.micro,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChoiceChipTile extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceChipTile({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface,
            borderRadius: R.radiusPill,
            border: Border.all(color: selected ? c.accent : c.line),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? c.navActiveInk : c.inkDim,
              fontSize: T.body,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kategori etiketi.
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool selected;

  const Tag({
    super.key,
    required this.text,
    required this.color,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = context.colors.tag(color, selected: selected);
    return AnimatedContainer(
      duration: Motion.fast,
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: R.radiusPill,
        border: Border.all(
          color: selected ? color : Colors.transparent,
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: style.text,
          fontSize: T.body,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Yaz / Çiz geçiş düğmesi.
class SegToggle extends StatelessWidget {
  final bool drawMode;
  final ValueChanged<bool> onChanged;

  const SegToggle({super.key, required this.drawMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget seg(String label, IconData icon, bool active, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.sm,
            ),
            decoration: BoxDecoration(
              color: active ? c.surfaceAlt : Colors.transparent,
              borderRadius: R.radiusPill,
              boxShadow: active ? c.shadowSm : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: I.xs, color: active ? c.ink : c.inkFaint),
                const SizedBox(width: S.xs),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? c.ink : c.inkFaint,
                    fontSize: T.body,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(S.xs),
      decoration: BoxDecoration(
        color: c.isDark ? c.bg : c.hover,
        borderRadius: R.radiusPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Yaz', Icons.keyboard_rounded, !drawMode, () => onChanged(false)),
          seg('Çiz', Icons.gesture_rounded, drawMode, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Kısa tarih etiketi: "3 Eyl 2026".
///
/// Editörde üç yerde (tarih satırı, tekrar bitişi, özet) aynı biçim
/// isteniyor; ortak parçaların yanında duruyor ki üçü ayrışmasın.
String fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

const List<String> _months = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];
