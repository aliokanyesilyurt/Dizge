/// Saatsiz işler şeridi ve içindeki çipler.
library;

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme.dart';
import 'day_drop_target.dart';

/// Google Takvim'deki "tüm gün" şeridinin karşılığı. Saati olmayan işler
/// ızgarada bir yere konamaz; burada gün sütununun tepesinde durur.
///
/// Yükseklik içeriğe göre büyür ama üst sınırı vardır: kalabalık bir gün
/// ızgarayı yutmasın diye şerit kendi içinde kaydırılır.
class UntimedRow extends StatelessWidget {
  const UntimedRow({
    super.key,
    required this.monday,
    required this.tasksByDay,
    required this.energyLimit,
    required this.onTapTask,
    required this.onToggle,
    this.onDropTask,
  });

  final DateTime monday;
  final List<List<Task>> tasksByDay;

  /// Izgarayla aynı kural: enerjinin üstündeki işler burada da soluklaşır.
  /// Saatsiz olmak işi kolaylaştırmıyor.
  final Energy? energyLimit;
  final void Function(Task, DateTime) onTapTask;
  final void Function(Task, DateTime) onToggle;

  /// Şeridin bir gün sütununa iş bırakıldı: o güne saatsiz iner (plan H5).
  final void Function(Task task, DateTime day)? onDropTask;

  static const double _chipHeight = 24.0;
  static const double _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final untimed = [
      for (final day in tasksByDay) day.where((t) => !t.scheduled).toList(),
    ];
    final maxCount = untimed.fold<int>(
      0,
      (m, list) => list.length > m ? list.length : m,
    );
    if (maxCount == 0) return const SizedBox.shrink();

    final rows = maxCount.clamp(1, _maxRows.toInt());
    final height = rows * (_chipHeight + 4) + 10;

    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: kTimeGutterWidth,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: S.sm, top: S.sm),
                child: Text(
                  'Saatsiz',
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: T.dense,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < tasksByDay.length; i++)
            Expanded(child: _column(i, untimed[i])),
        ],
      ),
    );
  }

  Widget _column(int i, List<Task> tasks) {
    final day = monday.add(Duration(days: i));
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(S.xs, S.xs, S.xs, S.xs),
      children: [
        for (final task in tasks)
          _UntimedChip(
            task: task,
            day: day,
            dimmed: task.exceedsEnergy(energyLimit),
            onTap: onTapTask,
            onToggle: onToggle,
          ),
      ],
    );
    final drop = onDropTask;
    if (drop == null) return list;
    return DayDropTarget(day: day, onDrop: drop, child: list);
  }
}

class _UntimedChip extends StatelessWidget {
  const _UntimedChip({
    required this.task,
    required this.day,
    required this.dimmed,
    required this.onTap,
    required this.onToggle,
  });

  final Task task;
  final DateTime day;
  final bool dimmed;
  final void Function(Task, DateTime) onTap;
  final void Function(Task, DateTime) onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = task.isDoneOn(day);
    // Atlanan rutin şeritte de üstü çizili ve solgun görünmeli: "Günü kurtar"
    // saatsiz rutinlere de dokunuyor, ızgarada değişip burada değişmemesi
    // düğmenin yarım çalıştığı izlenimi verirdi.
    final skipped = task.isSkippedOn(day);
    final style = c.tag(task.color);

    return GestureDetector(
      onTap: () => onTap(task, day),
      onLongPress: () => onToggle(task, day),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Draggable<Task>(
          data: task,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.8,
              child: SizedBox(
                width: 120, // Arbitrary width for drag feedback
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: UntimedRow._chipHeight,
                  padding: const EdgeInsets.symmetric(horizontal: S.sm),
                  decoration: BoxDecoration(
                    color: style.fill.withValues(alpha: done ? 0.45 : 1),
                    borderRadius: R.radiusXs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : (skipped
                                  ? Icons.redo_rounded
                                  : Icons.circle_outlined),
                        size: I.xs,
                        color: style.text.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: S.xs),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.text,
                            fontSize: T.micro,
                            fontWeight: FontWeight.w600,
                            decoration: (done || skipped)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _chip(done, skipped, style, dimmed),
          ),
          child: _chip(done, skipped, style, dimmed),
        ),
      ),
    );
  }

  Widget _chip(bool done, bool skipped, TagStyle style, bool dimmed) {
    return Opacity(
      opacity: (dimmed || skipped) ? 0.4 : 1,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: UntimedRow._chipHeight,
        margin: const EdgeInsets.only(bottom: S.xs),
        padding: const EdgeInsets.symmetric(horizontal: S.sm),
        decoration: BoxDecoration(
          color: style.fill.withValues(alpha: done ? 0.45 : 1),
          borderRadius: R.radiusXs,
        ),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : (skipped ? Icons.redo_rounded : Icons.circle_outlined),
              size: I.xs,
              color: style.text.withValues(alpha: 0.85),
            ),
            const SizedBox(width: S.xs),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.text,
                  fontSize: T.micro,
                  fontWeight: FontWeight.w600,
                  decoration: (done || skipped)
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
