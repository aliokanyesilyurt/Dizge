/// Izgaranın üstündeki gün başlıkları: gün adı, tarih ve günün özeti.
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/task.dart';
import '../../theme.dart';

class DayHeaderRow extends StatelessWidget {
  const DayHeaderRow({
    super.key,
    required this.monday,
    required this.today,
    required this.labels,
    required this.tasksByDay,
    required this.onTapDay,
  });

  final DateTime monday;
  final DateTime today;
  final List<String> labels;

  /// Gün başına iş sayısı rozetini beslemek için. Izgaranın kendisi zaten bu
  /// listeyi alıyor; başlık ikinci bir sorgu açmıyor.
  final List<List<Task>> tasksByDay;

  final ValueChanged<DateTime> onTapDay;

  /// Bu genişliğin altında sayaç rozeti düşer. 390px'te bir gün sütunu ~47px;
  /// rozet oraya sığmıyor ve sığdırmaya çalışmak gün sayısını kırpardı.
  static const double _badgeMinWidth = 700;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showBadges = MediaQuery.sizeOf(context).width >= _badgeMinWidth;

    return Padding(
      padding: const EdgeInsets.only(top: S.xs, bottom: S.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Saat sütununun hizasında duran zaman dilimi rozeti.
          SizedBox(
            width: kTimeGutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: S.sm, bottom: S.xs),
              child: Text(
                _utcOffsetLabel(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.dense,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayHeaderCell(
                day: monday.add(Duration(days: i)),
                label: labels[i],
                isToday: monday.add(Duration(days: i)) == today,
                isWeekend: i >= 5,
                taskCount: showBadges ? tasksByDay[i].length : 0,
                onTap: () => onTapDay(monday.add(Duration(days: i))),
              ),
            ),
        ],
      ),
    );
  }

  /// "GMT+3" — Google Takvim'in sol üst köşesindeki küçük bilgi.
  static String _utcOffsetLabel() {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs();
    final minutes = offset.inMinutes.abs() % 60;
    return minutes == 0
        ? 'GMT$sign$hours'
        : 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.label,
    required this.isToday,
    required this.isWeekend,
    required this.taskCount,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isToday;
  final bool isWeekend;

  /// 0 ise rozet çizilmez — hem boş gün sessiz kalır hem dar ekranda
  /// [DayHeaderRow] sayacı bu değeri sıfırlayarak rozeti düşürür.
  final int taskCount;

  final VoidCallback onTap;

  /// Bugünün sayı dairesi. 34px, 20px yazıyı 1.3 ölçeğe kadar taşır.
  static const double _circle = 34;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      button: true,
      // Ekran okuyucu "3" değil, ne olduğunu duysun.
      label: _semanticLabel(),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: R.radiusSm,
        hoverColor: c.hover,
        child: DecoratedBox(
          // Hafta sonu ayrımı yalnız zeminde ve çok hafif. Yazıyı soluklaştırıp
          // renkle bağırmak, cumartesiyi okunmaz yapıp hiçbir şey kazandırmaz.
          decoration: BoxDecoration(
            color: isWeekend ? c.gridWeekend : Colors.transparent,
            borderRadius: R.radiusSm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    // `inkFaint` 11px'te zemine karşı 3.2:1 kalıyordu. Gün adı
                    // hangi sütunun hangi güne ait olduğunu söyleyen tek yazı;
                    // sessiz kalmalı ama okunmalı — `inkDim` ikisini de verir.
                    color: isToday ? c.accent : c.inkDim,
                    fontSize: T.micro,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: S.xs),
                // Rozet sayının *yanında* duruyor, üstünde değil: üstte olsaydı
                // ya satır yüksekliğini büyütürdü ya gün adını iterdi.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: Motion.fast,
                      curve: Motion.curve,
                      width: _circle,
                      height: _circle,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? c.accent : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        maxLines: 1,
                        style: TextStyle(
                          color: isToday ? c.onAccent : c.ink,
                          fontSize: T.headline,
                          fontWeight: isToday
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    if (taskCount > 0) ...[
                      const SizedBox(width: S.xs),
                      ShadBadge.secondary(
                        padding: const EdgeInsets.symmetric(
                          horizontal: S.xs,
                          vertical: S.hair,
                        ),
                        child: Text(
                          '$taskCount',
                          style: const TextStyle(
                            fontSize: T.dense,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel() {
    final buffer = StringBuffer('$label ${day.day}');
    if (isToday) buffer.write(', bugün');
    if (taskCount > 0) buffer.write(', $taskCount iş');
    return buffer.toString();
  }
}
