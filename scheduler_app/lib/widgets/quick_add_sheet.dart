import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../core/time_grid.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import 'task_editor_sheet.dart';

/// Hızlı ekleme sayfasını açar. İş eklendiyse `true` döner.
///
/// Tasarım niyeti: **tek nefeslik akış.** Kullanıcı ızgarada bir saate
/// dokunduğunda gün ve saat zaten belli; geriye tek bir şey kalıyor — ne
/// yapacağı. Bu yüzden klavye anında açılır, Enter kaydeder, sayfa ekranın
/// yalnızca alt kısmını kaplar ve arkadaki takvim görünür kalır.
/// Ayrıntı gerekiyorsa "Ayrıntılar" tam editöre devreder — girilenler kaybolmaz.
Future<bool?> showQuickAdd(
  BuildContext context, {
  required DateTime date,
  double? startHour,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Arkadaki takvim seçilebilir kalsın diye hafif karartma.
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => QuickAddSheet(date: date, startHour: startHour),
  );
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, required this.date, this.startHour});

  final DateTime date;
  final double? startHour;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _title = TextEditingController();
  final _focus = FocusNode();

  late DateTime _date = Task.dayKey(widget.date);
  late double? _start = widget.startHour;
  double _duration = 1.0;
  late TaskCategory _category = AppData.categories.first;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        ref
            .read(telemetryProvider)
            .capture(
              Ev.quickAddOpened,
              props: {'from_grid': widget.startHour != null},
            );
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSave => _title.text.trim().isNotEmpty;

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    _saving = true;

    final task = Task(
      title: title,
      color: _category.color,
      categoryName: _category.name,
      date: _date,
      startHour: _start,
      durationHours: _duration,
    );
    ref.read(appStoreProvider).addTask(task);
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  /// Girilenleri kaybetmeden tam editöre geç.
  Future<void> _openFullEditor() async {
    final draft = Task(
      title: _title.text.trim(),
      color: _category.color,
      categoryName: _category.name,
      date: _date,
      startHour: _start,
      durationHours: _duration,
    );

    // Taslak henüz depoya girmedi; editöre "yeni kayıt" olarak veriyoruz ki
    // kullanıcı vazgeçerse ortada yarım iş kalmasın.
    Navigator.pop(context, false);
    await showTaskEditor(context, date: _date, draft: draft);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Grabber(),

          // --- Başlık satırı: renk noktası + tek satırlık alan ---
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.xs, S.lg, S.xs),
            child: Row(
              children: [
                _ColorDot(color: _category.color, onTap: _pickCategory),
                const SizedBox(width: S.md),
                Expanded(
                  child: TextField(
                    controller: _title,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                    style: TextStyle(
                      color: c.ink,
                      fontSize: T.headline,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Ne yapacaksın?',
                      hintStyle: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.headline,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- Hızlı özellikler ---
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: S.lg),
              children: [
                _Pill(
                  icon: Icons.calendar_today_rounded,
                  label: _dateLabel,
                  onTap: _pickDate,
                ),
                const SizedBox(width: S.sm),
                _Pill(
                  icon: Icons.schedule_rounded,
                  label: _start == null ? 'Saatsiz' : Task.formatTime(_start!),
                  highlighted: _start != null,
                  onTap: _pickTime,
                ),
                if (_start != null) ...[
                  const SizedBox(width: S.sm),
                  _Pill(
                    icon: Icons.timelapse_rounded,
                    label: Task.formatDuration(_duration),
                    onTap: _cycleDuration,
                  ),
                ],
                const SizedBox(width: S.sm),
                _Pill(
                  icon: Icons.sell_rounded,
                  label: _category.name,
                  color: _category.color,
                  onTap: _pickCategory,
                ),
              ],
            ),
          ),

          const SizedBox(height: S.xs),
          Divider(height: 1, color: c.lineSoft),

          // --- Alt eylem çubuğu ---
          Padding(
            padding: const EdgeInsets.fromLTRB(S.md, S.md, S.lg, S.lg),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _openFullEditor,
                  icon: const Icon(Icons.tune_rounded, size: I.sm),
                  label: const Text('Ayrıntılar'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: c.hover,
                    disabledForegroundColor: c.inkFaint,
                  ),
                  child: const Text('Ekle'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Özellik seçiciler -----------------------------------------------------

  static const _months = [
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

  String get _dateLabel {
    final today = Task.dayKey(DateTime.now());
    if (_date == today) return 'Bugün';
    if (_date == today.add(const Duration(days: 1))) return 'Yarın';
    return '${_date.day} ${_months[_date.month - 1]}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 2),
      lastDate: DateTime(_date.year + 5),
    );
    if (picked != null && mounted) setState(() => _date = Task.dayKey(picked));
  }

  Future<void> _pickTime() async {
    if (_start != null) {
      // İkinci dokunuş saati kaldırır: "saatsiz"e dönüş tek dokunuş uzakta.
      setState(() => _start = null);
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _start = snapHour(picked.hour + picked.minute / 60));
    }
  }

  static const _durations = [0.5, 1.0, 1.5, 2.0, 3.0];

  void _cycleDuration() {
    final i = _durations.indexOf(_duration);
    setState(() => _duration = _durations[(i + 1) % _durations.length]);
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<TaskCategory>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Grabber(),
              Text('Kategori', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: S.sm),
              for (final cat in AppData.categories)
                ListTile(
                  dense: true,
                  leading: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: cat.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(
                    cat.name,
                    style: TextStyle(color: c.ink, fontSize: T.strong),
                  ),
                  trailing: cat.name == _category.name
                      ? Icon(Icons.check_rounded, size: I.md, color: c.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, cat),
                ),
              const SizedBox(height: S.sm),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }
}

/// Sheet'lerin tepesindeki tutamak.
class _Grabber extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: S.md, bottom: S.md),
      decoration: BoxDecoration(
        color: c.line,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = highlighted || color != null;
    final tint = color ?? (highlighted ? c.accent : c.inkDim);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: S.md),
          decoration: BoxDecoration(
            color: active
                ? tint.withValues(alpha: c.isDark ? 0.14 : 0.10)
                : c.surface,
            borderRadius: R.radiusPill,
            border: Border.all(
              color: active ? tint.withValues(alpha: 0.45) : c.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: I.xs, color: tint),
              const SizedBox(width: S.sm),
              Text(
                label,
                style: TextStyle(
                  color: active ? tint : c.inkDim,
                  fontSize: T.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
