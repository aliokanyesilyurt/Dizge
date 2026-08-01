import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/day_pie_chart.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';

class DayViewScreen extends ConsumerStatefulWidget {
  final DateTime date;
  const DayViewScreen({super.key, required this.date});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  Task? _selected; // saatte vurgulanan görev

  static const List<String> _weekdays = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];
  static const List<String> _monthNames = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  Future<void> _openEditor({Task? existing, TimeOfDay? presetStart}) async {
    final changed = await showTaskEditor(
      context,
      date: widget.date,
      existing: existing,
      presetStart: presetStart,
    );
    // Silinen/rutini biten iş seçili kalmasın (saat diski onu vurgulamaya
    // devam ederdi). Liste zaten store'dan tazeleniyor.
    if (changed == true && mounted) {
      if (existing != null && !existing.occursOn(widget.date)) {
        setState(() => _selected = null);
      }
    }
  }

  /// Saat diskinin bir dilimine dokunmak: o saate hızlı ekleme.
  void _onClockTap(double hour) => showQuickAdd(
        context,
        date: widget.date,
        startHour: hour.floorToDouble(),
      );

  @override
  Widget build(BuildContext context) {
    // Store'u izle: bu ekran açıkken başka bir yerden yapılan değişiklik
    // (ör. senkron ya da haftalık ızgaradaki sürükleme) anında yansır.
    final tasks = ref.watch(appStoreProvider).tasksForDate(widget.date);
    final routines = tasks.where((t) => t.isRoutine).toList();
    final singles = tasks.where((t) => !t.isRoutine).toList();
    final d = widget.date;
    final done = tasks.where((t) => t.isDoneOn(d)).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${d.day} ${_monthNames[d.month - 1]} ${d.year}',
                style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text(
              tasks.isEmpty
                  ? _weekdays[d.weekday - 1]
                  : '${_weekdays[d.weekday - 1]}  ·  $done/${tasks.length} tamam',
              style: const TextStyle(color: AppColors.inkDim, fontSize: 12),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DayPieChart(
                    tasks: tasks,
                    date: d,
                    selected: _selected,
                    onHourTap: _onClockTap,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.lineSoft),
          Expanded(
            flex: 4,
            child: tasks.isEmpty
                ? _empty()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    children: [
                      if (singles.isNotEmpty) ...[
                        _sectionHeader(Icons.today_outlined, 'BUGÜNE ÖZEL',
                            singles.length),
                        ...singles.map(_card),
                      ],
                      if (routines.isNotEmpty) ...[
                        if (singles.isNotEmpty) const SizedBox(height: 14),
                        _sectionHeader(
                            Icons.repeat, 'RUTİNLER', routines.length),
                        ...routines.map(_card),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Yeni iş'),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 30, color: AppColors.inkFaint),
            SizedBox(height: 10),
            Text('Bu gün boş.',
                style: TextStyle(color: AppColors.inkDim, fontSize: 14)),
            SizedBox(height: 4),
            Text(
              'Saatin bir dilimine dokun ya da yeni bir iş ekle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkFaint, fontSize: 12),
            ),
          ],
        ),
      );

  /// [title] büyük harfli verilir: Dart'ın toUpperCase'i Türkçe 'i' harfini
  /// noktalı 'İ' yapmaz.
  Widget _sectionHeader(IconData icon, String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.inkFaint),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                )),
            const SizedBox(width: 6),
            Text('$count',
                style: const TextStyle(
                    color: AppColors.inkFaint, fontSize: 11)),
          ],
        ),
      );

  Widget _card(Task task) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _TaskCard(
          task: task,
          date: widget.date,
          selected: identical(task, _selected),
          onTap: () => setState(
              () => _selected = identical(_selected, task) ? null : task),
          onEdit: () => _openEditor(existing: task),
          onToggleDone: () => ref.read(appStoreProvider).setTaskDone(
                task,
                widget.date,
                !task.isDoneOn(widget.date),
              ),
        ),
      );
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleDone;

  const _TaskCard({
    required this.task,
    required this.date,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    final done = task.isDoneOn(date);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onEdit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? AppColors.hover : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? task.color : AppColors.lineSoft,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        child: Row(
          children: [
            _Check(
              key: ValueKey('done-${task.id}'),
              color: task.color,
              done: done,
              onTap: onToggleDone,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 46,
              child: task.scheduled
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(task.startString,
                            style: TextStyle(
                                color: done ? AppColors.inkFaint : AppColors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        Text(task.durationString,
                            style: const TextStyle(
                                color: AppColors.inkFaint, fontSize: 11)),
                      ],
                    )
                  : const Text('Saatsiz',
                      style:
                          TextStyle(color: AppColors.inkFaint, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 30, color: AppColors.lineSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: done ? AppColors.inkDim : AppColors.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.inkFaint,
                          ),
                        ),
                      ),
                      if (task.isRoutine) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.repeat,
                            size: 13, color: AppColors.inkFaint),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _MiniTag(text: task.categoryName, color: task.color),
                      if (task.place.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.place_outlined,
                            size: 11, color: AppColors.inkFaint),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(task.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.inkDim, fontSize: 11)),
                        ),
                      ],
                    ],
                  ),
                  if (task.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(task.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.inkDim,
                              fontSize: 12,
                              height: 1.25)),
                    ),
                  if (task.sketch != null && !task.sketch!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SketchThumbnail(sketch: task.sketch!),
                    ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_horiz,
                  size: 18, color: AppColors.inkFaint),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final Color color;
  final bool done;
  final VoidCallback onTap;

  const _Check({
    super.key,
    required this.color,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: done ? color : AppColors.inkFaint, width: 1.5),
          ),
          child: done
              ? const Icon(Icons.check, size: 13, color: Color(0xFF191919))
              : null,
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final style = tagStyleFor(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              color: style.text, fontSize: 10.5, fontWeight: FontWeight.w500)),
    );
  }
}
