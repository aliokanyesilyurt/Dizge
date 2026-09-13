import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/undo_toast.dart';
import '../core/time_grid.dart';
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

  late DateTime _day = Task.dayKey(widget.date);

  void _go(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
  }

  Future<void> _openEditor({Task? existing, TimeOfDay? presetStart}) async {
    final changed = await showTaskEditor(
      context,
      date: _day,
      existing: existing,
      presetStart: presetStart,
    );
    // Silinen/rutini biten iş seçili kalmasın (saat diski onu vurgulamaya
    // devam ederdi). Liste zaten store'dan tazeleniyor.
    if (changed == true && mounted) {
      if (existing != null && !existing.occursOn(_day)) {
        setState(() => _selected = null);
      }
    }
  }

  /// Saat diskinin bir dilimine dokunmak: o saate hızlı ekleme.
  void _onClockTap(double hour) =>
      showQuickAdd(context, date: _day, startHour: hour.floorToDouble());

  void _offerUndo(
    String label,
    VoidCallback undo, {
    Duration duration = const Duration(seconds: 5),
  }) => offerUndo(context, label, undo, duration: duration);

  void _pullFromPool(Task task, DateTime day, double hour) {
    final store = ref.read(appStoreProvider);
    if (task.inPool) {
      store.pullFromPool(task, toDay: day, startHour: hour);
      _offerUndo('Takvime kondu', () => store.moveToPool(task));
    } else {
      final oldDate = task.date;
      final oldStart = task.startHour;
      final copy = task.copy();
      copy.date = Task.dayKey(day);
      if (copy.durationHours == 0) copy.durationHours = 1.0;
      copy.startHour = clampStartWithin(hour, copy.durationHours);
      store.updateTask(copy);
      _offerUndo('Saat eklendi', () {
        final restore = copy.copy();
        restore.date = oldDate;
        restore.startHour = oldStart;
        store.updateTask(restore);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tasks = ref.watch(tasksForDateProvider(_day));
    final routines = tasks.where((t) => t.isRoutine).toList();
    final singles = tasks.where((t) => !t.isRoutine).toList();
    final d = _day;
    final done = tasks.where((t) => t.isDoneOn(d)).length;
    final today = Task.dayKey(DateTime.now());
    final isToday = d == today;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: S.gutter,
                vertical: S.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d.day} ${_monthNames[d.month - 1]} ${d.year}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: S.hair),
                        Text(
                          tasks.isEmpty
                              ? _weekdays[d.weekday - 1]
                              : '${_weekdays[d.weekday - 1]}  ·  $done/${tasks.length} tamam',
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: T.caption,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _go(-1),
                        tooltip: 'Önceki gün',
                        icon: Icon(
                          Icons.chevron_left_rounded,
                          size: I.lg,
                          color: c.inkDim,
                        ),
                      ),
                      TextButton(
                        onPressed: isToday
                            ? null
                            : () => setState(() => _day = today),
                        child: Text(
                          'Bugün',
                          style: TextStyle(
                            color: isToday ? c.inkFaint : c.accent,
                            fontSize: T.caption,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _go(1),
                        tooltip: 'Sonraki gün',
                        icon: Icon(
                          Icons.chevron_right_rounded,
                          size: I.lg,
                          color: c.inkDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
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
                            onDropTask: (task, hour) => _pullFromPool(task, d, hour),
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
                            text:
                                'Saatin bir dilimine dokun ya da yeni bir iş ekle.',
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
                                ...singles.expand(_cards),
                              ],
                              if (routines.isNotEmpty) ...[
                                if (singles.isNotEmpty)
                                  const SizedBox(height: S.lg),
                                _sectionHeader(
                                  c,
                                  Icons.repeat_rounded,
                                  'RUTİNLER',
                                  routines.length,
                                ),
                                ...routines.expand(_cards),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add_rounded, size: I.md),
        label: const Text('Yeni iş'),
      ),
    );
  }

  /// [title] büyük harfli verilir: Dart'ın toUpperCase'i Türkçe 'i' harfini
  /// noktalı 'İ' yapmaz.
  Widget _sectionHeader(AppPalette c, IconData icon, String title, int count) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(S.xs, S.xs, S.xs, S.sm),
        child: Row(
          children: [
            Icon(icon, size: I.xs, color: c.inkFaint),
            const SizedBox(width: S.sm),
            Text(title, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: S.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.xs,
                vertical: S.hair,
              ),
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: R.radiusPill,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.micro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  /// Bir işin o günkü kart(lar)ı.
  ///
  /// Gün içinde tekrarlayan iş (Z6) **tekrar başına** bir kart veriyor:
  /// üç dozluk ilaç üç satır, her biri kendi tikiyle. Tek kart olsaydı
  /// "sabahkini içtim" diyecek bir yer kalmazdı.
  List<Widget> _cards(Task task) {
    if (!task.hasManyTimes) return [_card(task)];
    return [for (final hour in task.occurrenceHours) _card(task, hour: hour)];
  }

  Widget _card(Task task, {double? hour}) {
    final card = _TaskCard(
      key: hour == null ? null : ValueKey('${task.id}@$hour'),
      task: task,
      date: widget.date,
      hour: hour,
      selected: identical(task, _selected),
      onTap: () =>
          setState(() => _selected = identical(_selected, task) ? null : task),
      onEdit: () => _openEditor(existing: task),
      onToggleDone: () {
        final store = ref.read(appStoreProvider);
        if (hour == null) {
          store.setTaskDone(task, widget.date, !task.isDoneOn(widget.date));
        } else {
          store.setTaskSlotDone(
            task,
            widget.date,
            hour,
            !task.isSlotDone(widget.date, hour),
          );
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: Draggable<Task>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.8,
            child: SizedBox(width: 250, child: card),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: card,
        ),
        child: card,
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final DateTime date;

  /// Gün içinde tekrarlayan işin **hangi** tekrarı; null => işin kendisi.
  final double? hour;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleDone;

  const _TaskCard({
    super.key,
    required this.task,
    required this.date,
    this.hour,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Tekrar kartında tik o tekrarın kendisi; günün tamamı değil.
    final done = hour == null
        ? task.isDoneOn(date)
        : task.isSlotDone(date, hour!);

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
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.xs, S.md),
          child: Row(
            children: [
              _Check(
                key: ValueKey(
                  hour == null ? 'done-${task.id}' : 'done-${task.id}@$hour',
                ),
                color: task.color,
                done: done,
                onTap: onToggleDone,
              ),
              const SizedBox(width: S.md),
              SizedBox(
                width: 48,
                child: task.scheduled
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hour == null
                                ? task.startString
                                : Task.formatTime(hour!),
                            style: TextStyle(
                              color: done ? c.inkFaint : c.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: T.strong,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            task.durationString,
                            style: TextStyle(
                              color: c.inkFaint,
                              fontSize: T.micro,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Saatsiz',
                        style: TextStyle(color: c.inkFaint, fontSize: T.micro),
                      ),
              ),
              const SizedBox(width: S.sm),
              Container(width: 1, height: 32, color: c.lineSoft),
              const SizedBox(width: S.md),
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
                              fontSize: T.strong,
                              letterSpacing: -0.1,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: c.inkFaint,
                            ),
                          ),
                        ),
                        if (task.isRoutine) ...[
                          const SizedBox(width: S.xs),
                          Icon(
                            Icons.repeat_rounded,
                            size: I.xs,
                            color: c.inkFaint,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: S.xs),
                    Row(
                      children: [
                        _MiniTag(
                          text: categoryLabel(task.categoryName),
                          color: task.color,
                        ),
                        if (task.place.isNotEmpty) ...[
                          const SizedBox(width: S.sm),
                          Icon(
                            Icons.place_rounded,
                            size: I.xs,
                            color: c.inkFaint,
                          ),
                          const SizedBox(width: S.hair),
                          Flexible(
                            child: Text(
                              task.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.inkDim,
                                fontSize: T.micro,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (task.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: S.xs),
                        child: Text(
                          task.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.inkDim,
                            fontSize: T.caption,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (task.sketch != null && !task.sketch!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: S.xs),
                        child: SketchThumbnail(sketch: task.sketch!),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: I.md,
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
          padding: const EdgeInsets.all(S.hair),
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
                ? Icon(Icons.check_rounded, size: I.xs, color: inkOn(color))
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
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
      decoration: BoxDecoration(color: style.fill, borderRadius: R.radiusPill),
      child: Text(
        text,
        style: TextStyle(
          color: style.text,
          fontSize: T.micro,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
