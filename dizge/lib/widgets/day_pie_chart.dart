import 'dart:math';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';

/// Günü 24 saatlik bir disk olarak gösteren "saat pastası".
class DayPieChart extends StatelessWidget {
  final List<Task> tasks;

  /// Grafiğin çizildiği gün (tamamlanma durumu buna göre okunur).
  final DateTime date;

  /// Seçili/vurgulanan görev (saat o görevin rengiyle öne çıkar).
  final Task? selected;

  /// Saatin bir dilimine dokununca o saat (0-23) ile çağrılır.
  final void Function(double hour)? onHourTap;
  final void Function(Task task, double hour)? onDropTask;

  const DayPieChart({
    super.key,
    required this.tasks,
    required this.date,
    this.selected,
    this.onHourTap,
    this.onDropTask,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final chart = GestureDetector(
          onTapUp: (details) {
            if (onHourTap == null) return;
            final center = Offset(size.width / 2, size.height / 2);
            final dx = details.localPosition.dx - center.dx;
            final dy = details.localPosition.dy - center.dy;
            final radius = min(size.width, size.height) / 2;
            if (sqrt(dx * dx + dy * dy) > radius) return;
            double angle = atan2(dy, dx) + pi / 2; // 0 = üst
            if (angle < 0) angle += 2 * pi;
            onHourTap!((angle / (2 * pi)) * 24);
          },
          child: CustomPaint(
            painter: ClockPiePainter(
              tasks: tasks,
              date: date,
              selected: selected,
              palette: palette,
            ),
            size: size,
          ),
        );

        if (onDropTask == null) return chart;

        return DragTarget<Task>(
          onWillAcceptWithDetails: (details) => true,
          onAcceptWithDetails: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            
            // `details.offset` is the global top-left of the drag feedback. 
            // We approximate the cursor by adding half the feedback size if we knew it,
            // but just using the local offset works well enough for a large pie chart.
            final local = box.globalToLocal(details.offset);
            // Center feedback adjustment (approximate 50x20 offset)
            final adjustedLocal = local + const Offset(50, 20);
            
            final center = Offset(size.width / 2, size.height / 2);
            final dx = adjustedLocal.dx - center.dx;
            final dy = adjustedLocal.dy - center.dy;
            
            double angle = atan2(dy, dx) + pi / 2;
            if (angle < 0) angle += 2 * pi;
            final hour = (angle / (2 * pi)) * 24;
            
            onDropTask!(details.data, hour);
          },
          builder: (context, candidateData, rejectedData) => chart,
        );
      },
    );
  }
}

class ClockPiePainter extends CustomPainter {
  final List<Task> tasks;
  final DateTime date;
  final Task? selected;
  final AppPalette palette;

  ClockPiePainter({
    required this.tasks,
    required this.date,
    required this.palette,
    this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 22;
    if (radius <= 0) return;

    final scheduled = tasks.where((t) => t.scheduled).toList();
    final hasSelection = selected != null;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Zemin: yumuşak gölge + zeminden ayrışan disk. Saat öne çıksın.
    canvas.drawShadow(
      Path()..addOval(rect),
      Colors.black,
      palette.isDark ? 10 : 6,
      false,
    );
    canvas.drawCircle(center, radius, Paint()..color = palette.clockFace);

    for (final task in scheduled) {
      final isSel = identical(task, selected);
      final fade = hasSelection && !isSel;
      final done = task.isDoneOn(date);
      final alpha = fade ? 0.16 : (done ? 0.40 : 0.88);

      final startAngle = (task.startHour! / 24) * 2 * pi - (pi / 2);
      final duration = task.endHour! - task.startHour!;
      final sweepAngle = (duration / 24) * 2 * pi;

      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()..color = task.color.withValues(alpha: alpha),
      );

      // Dilim kenarı — seçili olan vurgu rengiyle öne çıkar.
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = isSel
              ? palette.accent
              : palette.clockFace.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 2.5 : 1,
      );

      // Rutinleri dilim üstünde ince tarama ile ayırt et.
      if (task.isRoutine && !fade) {
        canvas.save();
        canvas.clipPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..arcTo(rect, startAngle, sweepAngle, false)
            ..close(),
        );
        final hatch = Paint()
          ..color = (palette.isDark ? Colors.white : Colors.black).withValues(
            alpha: 0.14,
          )
          ..strokeWidth = 1;
        for (double x = -radius * 2; x < radius * 2; x += 7) {
          canvas.drawLine(
            Offset(center.dx + x, center.dy - radius),
            Offset(center.dx + x + radius * 2, center.dy + radius),
            hatch,
          );
        }
        canvas.restore();
      }

      // Etiket (yeterince büyük dilimlerde).
      if (duration >= 1) {
        final sliceFill = Color.alphaBlend(
          task.color.withValues(alpha: alpha),
          palette.clockFace,
        );
        final labelColor = fade
            ? palette.inkFaint.withValues(alpha: 0.5)
            : inkOn(sliceFill);

        final mid = startAngle + sweepAngle / 2;
        final lr = radius * 0.62;
        final lp = Offset(center.dx + cos(mid) * lr, center.dy + sin(mid) * lr);
        final tp = TextPainter(
          text: TextSpan(
            text: task.title,
            style: TextStyle(
              color: labelColor,
              fontSize: T.dense,
              fontWeight: FontWeight.w700,
              decoration: done ? TextDecoration.lineThrough : null,
            ),
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: radius * 0.7);
        tp.paint(canvas, Offset(lp.dx - tp.width / 2, lp.dy - tp.height / 2));
      }
    }

    // 24 saatlik ince ayraçlar.
    final spokeBase = palette.isDark ? Colors.white : Colors.black;
    for (int i = 0; i < 24; i++) {
      final angle = (i / 24) * 2 * pi - (pi / 2);
      canvas.drawLine(
        center,
        Offset(
          center.dx + cos(angle) * radius,
          center.dy + sin(angle) * radius,
        ),
        Paint()
          ..color = spokeBase.withValues(alpha: i % 6 == 0 ? 0.10 : 0.04)
          ..strokeWidth = 0.8,
      );
    }

    // Dış halka.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = palette.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Şimdiki zaman ibresi (sadece bugün).
    final now = DateTime.now();
    if (Task.dayKey(now) == Task.dayKey(date)) {
      final h = now.hour + now.minute / 60.0;
      final angle = (h / 24) * 2 * pi - (pi / 2);
      canvas.drawLine(
        center,
        Offset(
          center.dx + cos(angle) * radius,
          center.dy + sin(angle) * radius,
        ),
        Paint()
          ..color = palette.nowLine
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(center, 4, Paint()..color = palette.nowLine);
    } else {
      canvas.drawCircle(center, 3, Paint()..color = palette.inkFaint);
    }

    // Saat çentikleri + rakamlar (her 2 saatte bir).
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < 24; i += 2) {
      final angle = (i / 24) * 2 * pi - (pi / 2);
      canvas.drawLine(
        Offset(
          center.dx + cos(angle) * (radius - 6),
          center.dy + sin(angle) * (radius - 6),
        ),
        Offset(
          center.dx + cos(angle) * radius,
          center.dy + sin(angle) * radius,
        ),
        Paint()
          ..color = palette.inkFaint
          ..strokeWidth = 1.2,
      );

      textPainter.text = TextSpan(
        text: i.toString(),
        style: TextStyle(
          color: palette.inkFaint,
          fontSize: T.dense,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          center.dx + cos(angle) * (radius + 13) - textPainter.width / 2,
          center.dy + sin(angle) * (radius + 13) - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ClockPiePainter old) => true;
}
