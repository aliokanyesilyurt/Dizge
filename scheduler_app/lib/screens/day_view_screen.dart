import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/day_pie_chart.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import 'task_list_scaffold.dart' show EmptyState;

class DayViewScreen extends ConsumerStatefulWidget {
  final DateTime date;
  const DayViewScreen({super.key, required this.date});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  Task? _selected; // saatte vurgulanan görev

  static const List<String> _weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  static const List<String> _monthNames = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
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
  void _onClockTap(double hour) =>
      showQuickAdd(context, date: widget.date, startHour: hour.floorToDouble());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Store'u izle: bu ekran açıkken başka bir yerden yapılan değişiklik
    // (ör. senkron ya da haftalık ızgaradaki sürükleme) anında yansır.
    final tasks = ref.watch(appStoreProvider).tasksForDate(widget.date);
    final routines = tasks.where((t) => t.isRoutine).toList();
    final singles = tasks.where((t) => !t.isRoutine).toList();
    final d = widget.date;
    final done = tasks.where((t) => t.isDoneOn(d)).length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        titleSpacing: 8,
        toolbarHeight: 66,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${d.day} ${_monthNames[d.month - 1]} ${d.year}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              tasks.isEmpty
                  ? _weekdays[d.weekday - 1]
                  : '${_weekdays[d.weekday - 1]}  ·  $done/${tasks.length} tamam',
              style: TextStyle(
                color: c.inkFaint,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                S.gutter,
                S.xs,
                S.gutter,
                S.lg,
              ),
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
          Divider(height: 1, color: c.lineSoft),
          Expanded(
            flex: 4,
            child: tasks.isEmpty
                ? const EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Bu gün boş.',
                    text: 'Saatin bir dilimine dokun ya da yeni bir iş ekle.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      S.gutter,
                      S.md,
                      S.gutter,
                      S.fabGap,
                    ),
                    children: [
                      if (singles.isNotEmpty) ...[
                        _sectionHeader(
                          c,
                          Icons.today_rounded,
                          'BUGÜNE ÖZEL',
                          singles.length,
                        ),
                        ...singles.map(_card),
                      ],
                      if (routines.isNotEmpty) ...[
                        if (singles.isNotEmpty) const SizedBox(height: 18),
                        _sectionHeader(
                          c,
                          Icons.repeat_rounded,
                          'RUTİNLER',
                          routines.length,
                        ),
                        ...routines.map(_card),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Yeni iş'),
      ),
    );
  }

  /// [title] büyük harfli verilir: Dart'ın toUpperCase'i Türkçe 'i' harfini
  /// noktalı 'İ' yapmaz.
  Widget _sectionHeader(AppPalette c, IconData icon, String title, int count) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
        child: Row(
          children: [
            Icon(icon, size: 14, color: c.inkFaint),
            const SizedBox(width: 7),
            Text(title, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: R.radiusPill,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _card(Task task) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _TaskCard(
      task: task,
      date: widget.date,
      selected: identical(task, _selected),
      onTap: () =>
          setState(() => _selected = identical(_selected, task) ? null : task),
      onEdit: () => _openEditor(existing: task),
      onToggleDone: () => ref
          .read(appStoreProvider)
          .setTaskDone(task, widget.date, !task.isDoneOn(widget.date)),
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
    final c = context.colors;
    final done = task.isDoneOn(date);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onEdit,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.radiusMd,
            border: Border.all(
              color: selected ? task.color : c.lineSoft,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected ? c.shadowMd : c.shadowSm,
          ),
          padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
          child: Row(
            children: [
              _Check(
                key: ValueKey('done-${task.id}'),
                color: task.color,
                done: done,
                onTap: onToggleDone,
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: task.scheduled
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.startString,
                            style: TextStyle(
                              color: done ? c.inkFaint : c.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            task.durationString,
                            style: TextStyle(color: c.inkFaint, fontSize: 11),
                          ),
                        ],
                      )
                    : Text(
                        'Saatsiz',
                        style: TextStyle(color: c.inkFaint, fontSize: 11),
                      ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 32, color: c.lineSoft),
              const SizedBox(width: 12),
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
                              color: done ? c.inkDim : c.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                              letterSpacing: -0.1,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: c.inkFaint,
                            ),
                          ),
                        ),
                        if (task.isRoutine) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.repeat_rounded,
                            size: 13,
                            color: c.inkFaint,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _MiniTag(text: task.categoryName, color: task.color),
                        if (task.place.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Icon(
                            Icons.place_rounded,
                            size: 11,
                            color: c.inkFaint,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              task.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.inkDim, fontSize: 11),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (task.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          task.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.inkDim,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (task.sketch != null && !task.sketch!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SketchThumbnail(sketch: task.sketch!),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: c.inkFaint,
                ),
                onPressed: onEdit,
              ),
            ],
          ),
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
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: done ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: done ? color : c.inkFaint, width: 1.5),
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 14, color: inkOn(color))
                : null,
          ),
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
    final style = context.colors.tag(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: style.fill, borderRadius: R.radiusPill),
      child: Text(
        text,
        style: TextStyle(
          color: style.text,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
