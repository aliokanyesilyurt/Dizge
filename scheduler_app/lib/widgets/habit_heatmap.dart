import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../models/node.dart';
import '../theme.dart';

const _weekdayLabels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// GitHub commit geçmişi tarzı ısı haritası: satırlar = haftanın günleri,
/// sütunlar = haftalar. Dolu hücre = o gün alışkanlık yapılmış. Geçmiş/bugün
/// hücrelerine dokununca [onToggleDay] ile işaretlenip kaldırılabilir.
class HabitHeatmap extends StatelessWidget {
  final Habit habit;

  /// Kaç haftalık geçmiş gösterilsin.
  final int weeks;

  final void Function(DateTime day)? onToggleDay;

  const HabitHeatmap({
    super.key,
    required this.habit,
    this.weeks = 17,
    this.onToggleDay,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = dayOnly(DateTime.now());
    // Izgaranın sağ-alt köşesi bugün olacak şekilde, en soldaki Pazartesi'yi bul.
    final thisWeekMon = Habit.weekStart(today);
    final firstMon = thisWeekMon.subtract(Duration(days: (weeks - 1) * 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sol: gün etiketleri (Pzt / Çar / Cum hizası)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: List.generate(7, (r) {
                  final show = r == 0 || r == 2 || r == 4;
                  return SizedBox(
                    height: _cell + _gap,
                    child: show
                        ? Text(
                            _weekdayLabels[r],
                            style: TextStyle(
                              color: c.inkFaint,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null,
                  );
                }),
              ),
            ),
            // Izgara
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true, // bugün sağda başlasın
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var w = 0; w < weeks; w++)
                      Column(
                        children: [
                          for (var d = 0; d < 7; d++)
                            _cellFor(
                              c,
                              firstMon.add(Duration(days: w * 7 + d)),
                              today,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Legend(color: habit.color),
      ],
    );
  }

  static const _cell = 13.0;
  static const _gap = 3.0;

  Widget _cellFor(AppPalette c, DateTime day, DateTime today) {
    final future = day.isAfter(today);
    final done = habit.isDoneOn(day);
    Color fill;
    if (future) {
      fill = Colors.transparent;
    } else if (done) {
      fill = habit.color;
    } else {
      fill = c.hover;
    }

    final cell = AnimatedContainer(
      duration: Motion.fast,
      width: _cell,
      height: _cell,
      margin: const EdgeInsets.all(_gap / 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
        border: future ? Border.all(color: c.lineSoft) : null,
      ),
    );

    if (future || onToggleDay == null) return cell;
    return GestureDetector(
      onTap: () => onToggleDay!(day),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: cell),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  const _Legend({required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget box(Color fill) => Container(
      width: 11,
      height: 11,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
      ),
    );

    final label = TextStyle(color: c.inkFaint, fontSize: 10);

    return Row(
      children: [
        Text('Az', style: label),
        const SizedBox(width: 5),
        box(c.hover),
        box(color.withValues(alpha: 0.5)),
        box(color),
        const SizedBox(width: 5),
        Text('Çok', style: label),
      ],
    );
  }
}
