import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';

/// Çizim verisini tutar (editör kaydederken okunur).
class SketchController {
  final List<List<Offset>> strokes;
  Size size = Size.zero;

  SketchController([List<List<Offset>>? initial])
      : strokes = initial == null
            ? <List<Offset>>[]
            : initial.map(List<Offset>.of).toList();

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  Sketch toSketch(Color color) => Sketch(
        strokes.map(List<Offset>.of).toList(),
        size == Size.zero ? const Size(300, 180) : size,
        color,
      );
}

/// Parmak/kalem ile elle yazma alanı.
class DrawingCanvas extends StatefulWidget {
  final SketchController controller;
  final Color color;

  const DrawingCanvas(
      {super.key, required this.controller, required this.color});

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  void _start(Offset p) {
    setState(() => widget.controller.strokes.add(<Offset>[p]));
  }

  void _extend(Offset p) {
    setState(() {
      if (widget.controller.strokes.isEmpty) {
        widget.controller.strokes.add(<Offset>[]);
      }
      widget.controller.strokes.last.add(p);
    });
  }

  void _undo() {
    if (widget.controller.strokes.isEmpty) return;
    setState(() => widget.controller.strokes.removeLast());
  }

  void _clear() {
    setState(() => widget.controller.strokes.clear());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 5 / 3,
          child: LayoutBuilder(
            builder: (context, box) {
              widget.controller.size = Size(box.maxWidth, box.maxHeight);
              return Container(
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: R.radiusMd,
                  border: Border.all(color: c.line),
                  boxShadow: c.shadowSm,
                ),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  onPanStart: (d) => _start(d.localPosition),
                  onPanUpdate: (d) => _extend(d.localPosition),
                  child: CustomPaint(
                    painter: SketchPainter(
                      strokes: widget.controller.strokes,
                      color: widget.color,
                      guideColor: c.lineSoft,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Kalemle yaz',
                style: TextStyle(color: c.inkDim, fontSize: 13)),
            const Spacer(),
            IconButton(
              tooltip: 'Geri al',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.undo_rounded, size: 20, color: c.inkDim),
              onPressed: _undo,
            ),
            IconButton(
              tooltip: 'Temizle',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: c.inkDim),
              onPressed: _clear,
            ),
          ],
        ),
      ],
    );
  }
}

class SketchPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;

  /// Kılavuz çizgilerinin rengi. null ise kılavuz çizilmez (küçük önizleme).
  final Color? guideColor;

  SketchPainter({
    required this.strokes,
    required this.color,
    this.guideColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guide = guideColor;
    if (guide != null) {
      final paint = Paint()
        ..color = guide
        ..strokeWidth = 1;
      for (double y = size.height / 3; y < size.height; y += size.height / 3) {
        canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), paint);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawPoints(PointMode.points, stroke, paint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter old) =>
      old.strokes != strokes ||
      old.color != color ||
      old.guideColor != guideColor;
}

/// Kartlarda küçük çizim önizlemesi.
class SketchThumbnail extends StatelessWidget {
  final Sketch sketch;
  final double width;
  final double height;

  const SketchThumbnail(
      {super.key, required this.sketch, this.width = 56, this.height = 34});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: sketch.size.width,
          height: sketch.size.height,
          child: CustomPaint(
            painter:
                SketchPainter(strokes: sketch.strokes, color: sketch.color),
          ),
        ),
      ),
    );
  }
}
