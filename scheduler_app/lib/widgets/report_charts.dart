import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Tamamlanma oranını gösteren dairesel gösterge (0-1).
class CompletionRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final String? centerLabel;
  final String? caption;

  const CompletionRing({
    super.key,
    required this.value,
    this.size = 124,
    this.centerLabel,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0.0, 1.0), c),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel ?? '%${(value * 100).round()}',
                style: TextStyle(
                  color: c.ink,
                  fontSize: T.display,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: T.micro,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final AppPalette palette;
  _RingPainter(this.value, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;
    const stroke = 9.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = palette.hover
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // Değere göre vurgu→ikincil renk geçişli yay.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * pi * value;
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [palette.accent, palette.secondary, palette.accent],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.palette != palette;
}

/// Etiketli yatay çubuk satırları (kategori/etikete göre süre gibi).
class HBarRow {
  final String label;
  final Color color;
  final double value;
  final String valueLabel;
  const HBarRow(this.label, this.color, this.value, this.valueLabel);
}

class HBarChart extends StatelessWidget {
  final List<HBarRow> rows;
  final String emptyText;

  const HBarChart({super.key, required this.rows, this.emptyText = 'Veri yok'});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyText,
          style: TextStyle(color: c.inkFaint, fontSize: T.caption, height: 1.4),
        ),
      );
    }
    final maxV = rows.map((r) => r.value).fold(0.0, max);

    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.inkDim,
                      fontSize: T.caption,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Stack(
                      children: [
                        Container(height: 16, color: c.hover),
                        FractionallySizedBox(
                          widthFactor: maxV == 0 ? 0 : (r.value / maxV),
                          child: AnimatedContainer(
                            duration: Motion.slow,
                            curve: Motion.curve,
                            height: 16,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  r.color.withValues(alpha: 0.65),
                                  r.color,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  child: Text(
                    r.valueLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: c.inkDim,
                      fontSize: T.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dikey mini çubuklar (haftanın günü tamamlanma oranı gibi). Değer -1 = veri yok.
class VBarChart extends StatelessWidget {
  final List<double> values; // her biri 0..1 ya da -1
  final List<String> labels;
  final Color color;
  final int? highlightIndex; // ör. en kötü gün

  const VBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.highlightIndex,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SizedBox(
      height: 118,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      values[i] < 0 ? '–' : '%${(values[i] * 100).round()}',
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.dense,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: values[i] < 0
                              ? 0.02
                              : max(values[i], 0.02),
                          child: AnimatedContainer(
                            duration: Motion.slow,
                            curve: Motion.curve,
                            decoration: BoxDecoration(
                              color: i == highlightIndex
                                  ? c.secondary
                                  : color.withValues(
                                      alpha: values[i] < 0 ? 0.15 : 0.8,
                                    ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: TextStyle(
                        color: i == highlightIndex ? c.secondary : c.inkFaint,
                        fontSize: T.dense,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
