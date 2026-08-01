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
    this.size = 120,
    this.centerLabel,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0.0, 1.0)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel ?? '%${(value * 100).round()}',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: const TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 11,
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
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 7;
    const stroke = 10.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.hover
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    // Değere göre mavi→pembe geçişli yay.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * pi * value;
    final paint = Paint()
      ..shader = const SweepGradient(
        colors: [AppColors.blue, AppColors.pink],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
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
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyText,
          style: const TextStyle(color: AppColors.inkFaint, fontSize: 12.5),
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
                    style: const TextStyle(
                      color: AppColors.inkDim,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      children: [
                        Container(height: 18, color: AppColors.hover),
                        FractionallySizedBox(
                          widthFactor: maxV == 0 ? 0 : (r.value / maxV),
                          child: Container(
                            height: 18,
                            decoration: BoxDecoration(
                              color: r.color.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    r.valueLabel,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.inkDim,
                      fontSize: 12,
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
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      values[i] < 0 ? '–' : '%${(values[i] * 100).round()}',
                      style: const TextStyle(
                        color: AppColors.inkFaint,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: values[i] < 0
                              ? 0.02
                              : max(values[i], 0.02),
                          child: Container(
                            decoration: BoxDecoration(
                              color: i == highlightIndex
                                  ? AppColors.pink
                                  : color.withValues(
                                      alpha: values[i] < 0 ? 0.15 : 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      labels[i],
                      style: TextStyle(
                        color: i == highlightIndex
                            ? AppColors.pink
                            : AppColors.inkFaint,
                        fontSize: 10,
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
