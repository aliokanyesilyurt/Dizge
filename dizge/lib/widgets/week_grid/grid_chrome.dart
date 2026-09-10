/// Izgaranın sabit çerçevesi: solda saat sütunu, arkada çizgi ve gölgeler.
///
/// İkisi de veriyi dışarıdan alır, olay üretmez — bu yüzden bloklardan ve
/// etkileşim kodundan ayrı duruyorlar.
library;

import 'package:flutter/material.dart';

import '../../core/time_grid.dart';
import '../../theme.dart';

class HourGutter extends StatelessWidget {
  const HourGutter({super.key, required this.metrics});

  final GridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = metrics.dayStart.ceil();
    final last = metrics.dayEnd.floor();

    return Stack(
      children: [
        for (var h = first; h <= last; h++)
          Positioned(
            // Etiket kendi çizgisinin biraz üstünde durur (Google Takvim'de
            // olduğu gibi) — böylece saat, altındaki dilimi adlandırır.
            top: metrics.yFor(h.toDouble()) - 6,
            right: 10,
            child: Text(
              // İlk ve son etiket kenara yapışıp kırpılır; Google da onları
              // gizler.
              (h >= 24 || h == 0) ? '' : '${h.toString().padLeft(2, '0')}:00',
              style: TextStyle(
                // `inkFaint` değil: 10.5px'te zemine karşı 3.2:1 kalıyordu ve
                // saat sütunu dekorasyon değil, saati oradan okuyorsun.
                // `inkDim` hâlâ ikincil ama AA'yı iki temada da geçiyor.
                color: c.inkDim,
                fontSize: T.dense,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }
}

// --- Izgara zemini -----------------------------------------------------------

class GridPainter extends CustomPainter {
  const GridPainter({
    required this.metrics,
    required this.palette,
    required this.todayIndex,
    required this.dropDayIndex,
    required this.columnCount,
  });

  final GridMetrics metrics;
  final AppPalette palette;
  final int? todayIndex;
  final int columnCount;

  /// Sürükleme sırasında hedeflenen gün — sütunu hafifçe aydınlanır.
  final int? dropDayIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final columnWidth = size.width / columnCount;

    // Bugünün ve bırakma hedefinin sütun zemini.
    if (todayIndex != null) {
      canvas.drawRect(
        Rect.fromLTWH(todayIndex! * columnWidth, 0, columnWidth, size.height),
        Paint()..color = palette.gridTodayWash,
      );
    }
    if (dropDayIndex != null) {
      canvas.drawRect(
        Rect.fromLTWH(dropDayIndex! * columnWidth, 0, columnWidth, size.height),
        Paint()..color = palette.dropTarget.withValues(alpha: 0.10),
      );
    }

    final hourPaint = Paint()
      ..color = palette.gridHourLine
      ..strokeWidth = 1;
    final halfPaint = Paint()
      ..color = palette.gridHalfLine
      ..strokeWidth = 1;
    final columnPaint = Paint()
      ..color = palette.gridColumnLine
      ..strokeWidth = 1;

    // Yatay: tam saatler belirgin, yarım saatler soluk. Yarım saat çizgileri
    // yalnızca yeterince yer varken çizilir; sıkışıkken görsel gürültü olur.
    final drawHalf = metrics.hourHeight >= 64;
    for (var h = metrics.dayStart; h <= metrics.dayEnd; h += 1) {
      final y = metrics.yFor(h);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
      if (drawHalf && h + 0.5 < metrics.dayEnd) {
        final yh = metrics.yFor(h + 0.5);
        canvas.drawLine(Offset(0, yh), Offset(size.width, yh), halfPaint);
      }
    }

    // Dikey: gün ayraçları.
    for (var i = 1; i < columnCount; i++) {
      final x = i * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), columnPaint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.metrics.hourHeight != metrics.hourHeight ||
      old.palette != palette ||
      old.todayIndex != todayIndex ||
      old.dropDayIndex != dropDayIndex;
}
