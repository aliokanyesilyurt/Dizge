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
    backgroundColor: AppColors.surfaceAlt,
    // Arkadaki takvim seçilebilir kalsın diye hafif karartma.
    barrierColor: Colors.black.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
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
        ref.read(telemetryProvider).capture(Ev.quickAddOpened, props: {
          'from_grid': widget.startHour != null,
        });
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
    await showTaskEditor(
      context,
      date: _date,
      draft: draft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.inkFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // --- Başlık satırı: renk noktası + tek satırlık alan ---
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 14, 4),
            child: Row(
              children: [
                _ColorDot(
                  color: _category.color,
                  onTap: _pickCategory,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _title,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Ne yapacaksın?',
                      hintStyle: TextStyle(
                        color: AppColors.inkFaint,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- Hızlı özellikler ---
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Pill(
                  icon: Icons.calendar_today_outlined,
                  label: _dateLabel,
                  onTap: _pickDate,
                ),
                const SizedBox(width: 8),
                _Pill(
                  icon: Icons.schedule,
                  label: _start == null ? 'Saatsiz' : Task.formatTime(_start!),
                  highlighted: _start != null,
                  onTap: _pickTime,
                ),
                if (_start != null) ...[
                  const SizedBox(width: 8),
                  _Pill(
                    icon: Icons.timelapse_outlined,
                    label: Task.formatDuration(_duration),
                    onTap: _cycleDuration,
                  ),
                ],
                const SizedBox(width: 8),
                _Pill(
                  icon: Icons.sell_outlined,
                  label: _category.name,
                  color: _category.color,
                  onTap: _pickCategory,
                ),
              ],
            ),
          ),

          const Divider(height: 17, color: AppColors.lineSoft),

          // --- Alt eylem çubuğu ---
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _openFullEditor,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Ayrıntılar'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    disabledBackgroundColor: AppColors.hover,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: AppColors.inkFaint,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
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
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
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
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text('Kategori',
                style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final cat in AppData.categories)
              ListTile(
                dense: true,
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration:
                      BoxDecoration(color: cat.color, shape: BoxShape.circle),
                ),
                title: Text(cat.name,
                    style: const TextStyle(
                        color: AppColors.ink, fontSize: 14)),
                trailing: cat.name == _category.name
                    ? const Icon(Icons.check, size: 17, color: AppColors.blue)
                    : null,
                onTap: () => Navigator.pop(ctx, cat),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _category = picked);
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
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
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
    final tint = color ?? (highlighted ? AppColors.blue : AppColors.inkDim);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlighted || color != null
                ? tint.withValues(alpha: 0.55)
                : AppColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: tint,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
