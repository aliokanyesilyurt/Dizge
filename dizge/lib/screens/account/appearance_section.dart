/// Görünüm bölümü: tema tercihi ve kullanım kipi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme_mode_controller.dart';
import '../../core/usage_mode_controller.dart';
import '../../theme.dart';
import 'account_tiles.dart';

/// Tema seçici: üç büyük, dokunulası kart. Anahtar yerine kart tercih edildi
/// çünkü "sistem" üçüncü bir durum ve iki konumlu bir anahtara sığmaz.
class ThemeCard extends ConsumerWidget {
  const ThemeCard({super.key});

  static const _options = <(IconData, String, String, ThemeMode)>[
    (Icons.light_mode_rounded, 'Açık', 'Gündüz', ThemeMode.light),
    (Icons.dark_mode_rounded, 'Koyu', 'Gece', ThemeMode.dark),
    (Icons.brightness_auto_rounded, 'Sistem', 'Otomatik', ThemeMode.system),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);

    return AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, size: I.md, color: c.inkDim),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  'Tema',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          Text(
            'Tercihin bu cihazda saklanır ve uygulama açılır açılmaz uygulanır.',
            style: TextStyle(
              color: c.inkFaint,
              fontSize: T.micro,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              for (final o in _options) ...[
                Expanded(
                  child: _ThemeOptionCard(
                    icon: o.$1,
                    title: o.$2,
                    caption: o.$3,
                    selected: mode == o.$4,
                    onTap: () => ref.read(themeModeProvider.notifier).set(o.$4),
                  ),
                ),
                if (o != _options.last) const SizedBox(width: S.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Görev yazmanın hangi yoldan gideceği (A2).
///
/// Tema kartıyla aynı kalıpta ve onun hemen altında duruyor — ikisi de
/// "uygulama bana nasıl görünsün/davransın" sorusunun yanıtı ve ikisi de bu
/// cihaza özel.
class UsageModeCard extends ConsumerWidget {
  const UsageModeCard({super.key});

  static const _icons = <UsageMode, IconData>{
    UsageMode.klasik: Icons.keyboard_rounded,
    UsageMode.ajanda: Icons.draw_rounded,
    UsageMode.karma: Icons.auto_awesome_motion_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(usageModeProvider);

    return AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: I.md, color: c.inkDim),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  'Yazma biçimi',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          Text(
            'Hiçbir ekran kaybolmaz; değişen tek şey yeni bir iş eklerken '
            'önce neyin açıldığı.',
            style: TextStyle(
              color: c.inkFaint,
              fontSize: T.micro,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              for (final option in UsageMode.values) ...[
                Expanded(
                  child: _ThemeOptionCard(
                    icon: _icons[option]!,
                    title: option.label,
                    caption: option.description,
                    selected: mode == option,
                    onTap: () =>
                        ref.read(usageModeProvider.notifier).set(option),
                  ),
                ),
                if (option != UsageMode.values.last)
                  const SizedBox(width: S.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.symmetric(vertical: S.md),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.bg,
            borderRadius: R.radiusSm,
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
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
                  fontSize: T.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.hair),
              Text(
                caption,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.micro,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
