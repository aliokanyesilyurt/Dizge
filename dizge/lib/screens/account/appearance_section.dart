/// Görünüm bölümü: tema tercihi ve kullanım kipi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme_mode_controller.dart';
import '../../core/usage_mode_controller.dart';
import '../../theme.dart';
import '../../models/task.dart';
import '../../data/app_store.dart';
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
          const SizedBox(height: S.xl),
          ActionTile(
            icon: Icons.label_outline_rounded,
            title: 'Kategoriler',
            subtitle: 'Kategori adlarını ve renklerini düzenle',
            onTap: () => _showCategories(context),
          ),
        ],
      ),
    );
  }

  void _showCategories(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _CategoriesSheet(),
    );
  }
}

class _CategoriesSheet extends ConsumerWidget {
  const _CategoriesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // AppStore güncellendiğinde bu sheet de yenilenecek.
    ref.watch(appStoreProvider);
    final cats = AppData.categories;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: S.xl,
        right: S.xl,
        top: S.md,
        bottom: S.xxl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: S.xl),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Kategoriler',
            style: TextStyle(
              color: c.ink,
              fontSize: T.headline,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: S.md),
          Text(
            'Kategori adlarını ve renklerini buradan değiştirebilirsin. '
            'Değişiklikler tüm işlerine yansır.',
            style: TextStyle(color: c.inkFaint, fontSize: T.body, height: 1.4),
          ),
          const SizedBox(height: S.xl),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: cats.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: S.sm),
              itemBuilder: (ctx, i) {
                final cat = cats[i];
                return _CategoryRow(
                  category: cat,
                  onUpdate: (updated) {
                    ref.read(appStoreProvider).updateCategory(updated);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onUpdate});

  final TaskCategory category;
  final ValueChanged<TaskCategory> onUpdate;

  Future<void> _edit(BuildContext context) async {
    final updated = await showDialog<TaskCategory>(
      context: context,
      builder: (ctx) => _CategoryEditDialog(category: category),
    );
    if (updated != null) onUpdate(updated);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: R.radiusMd,
        onTap: () => _edit(context),
        child: Container(
          padding: const EdgeInsets.all(S.md),
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: R.radiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.edit_rounded, size: I.sm, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  const _CategoryEditDialog({required this.category});
  final TaskCategory category;

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late TextEditingController _ctrl;
  late Color _picked;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.category.label);
    _picked = widget.category.color;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Kategori düzenle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: TextStyle(color: c.ink),
            decoration: const InputDecoration(hintText: 'Görünen ad'),
          ),
          const SizedBox(height: S.lg),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kTaskColors.map((color) {
              final sel = color == _picked;
              return GestureDetector(
                onTap: () => setState(() => _picked = color),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? c.ink : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: sel
                      ? Icon(
                          Icons.check_rounded,
                          size: I.sm,
                          color: inkOn(color),
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            final t = _ctrl.text.trim();
            if (t.isEmpty) return;
            final customLabel = t == categoryLabel(widget.category.name) ? null : t;
            Navigator.pop(context, widget.category.copyWith(color: _picked, customLabel: customLabel));
          },
          child: const Text('Kaydet'),
        ),
      ],
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
