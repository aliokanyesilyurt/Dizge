import 'package:flutter/material.dart';

import '../models/agenda_page.dart';
import '../theme.dart';

/// Ajanda yaprağının yazma yüzeyi.
///
/// ## `DrawingCanvas`'tan farkı
///
/// `DrawingCanvas` bir görevin ekini çizer: tek renk, tek kalınlık, küçük bir
/// kutu. Burası bir defter yaprağı — kalem rengi değişir, silinir, geri alınır
/// ve yazılan şey [InkStroke] olarak kalıcıdır. İkisini tek widget'a
/// sıkıştırmak, küçük ekin ihtiyacı olmayan bir sürü durumu ona da taşırdı.
///
/// ## Neden `Listener`, `GestureDetector` değil
///
/// Kalem (stylus) olayları `GestureDetector`'ın tanıma katmanından geçerken
/// gecikiyor ve ilk birkaç nokta yutulabiliyor — yazının başı kırpılmış
/// görünüyor. `Listener` ham işaretçi olaylarını verir; çizim tam olarak bunu
/// ister.
class InkCanvas extends StatefulWidget {
  /// Sayfadaki vuruşlar. Değişiklikler [onChanged] ile dışarı bildirilir;
  /// widget kendi durumunu **sahiplenmez** — tek gerçek kaynak depodur.
  final List<InkStroke> strokes;

  final ValueChanged<List<InkStroke>> onChanged;

  /// Kalemin rengi ve kalınlığı.
  final Color color;
  final double width;

  /// Silgi açıkken dokunulan vuruş listeden çıkar.
  final bool erasing;

  /// Çizgili kâğıt aralığı. Sıfır verilirse çizgi çizilmez.
  final double ruleSpacing;

  const InkCanvas({
    super.key,
    required this.strokes,
    required this.onChanged,
    required this.color,
    this.width = 2.0,
    this.erasing = false,
    this.ruleSpacing = 34,
  });

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  /// Çizilmekte olan vuruş. Bitene kadar listeye girmez: her nokta için
  /// dışarıya yeni bir liste yollamak, sayfa uzadıkça her karede kopyalama
  /// demekti.
  List<Offset>? _active;

  void _down(Offset p) {
    if (widget.erasing) {
      _eraseAt(p);
      return;
    }
    setState(() => _active = [p]);
  }

  void _move(Offset p) {
    if (widget.erasing) {
      _eraseAt(p);
      return;
    }
    if (_active == null) return;
    setState(() => _active!.add(p));
  }

  void _up() {
    final active = _active;
    if (active == null) return;

    setState(() => _active = null);
    // Tek noktalık dokunuşlar da kalır: "i" harfinin noktası bir vuruştur.
    if (active.isEmpty) return;

    widget.onChanged([
      ...widget.strokes,
      InkStroke(points: active, color: widget.color, width: widget.width),
    ]);
  }

  /// [p] noktasına yeterince yakın vuruşları siler.
  ///
  /// Silgi ayrı bir "silme vuruşu" bırakmıyor, vuruşu listeden çıkarıyor.
  /// Böylece geri alma tek kurala iniyor ve silinmiş-ama-duran yarı canlı bir
  /// durum oluşmuyor.
  void _eraseAt(Offset p) {
    const reach = 12.0;

    final kept = [
      for (final s in widget.strokes)
        if (!_touches(s, p, reach)) s,
    ];

    if (kept.length != widget.strokes.length) widget.onChanged(kept);
  }

  static bool _touches(InkStroke stroke, Offset p, double reach) {
    for (final q in stroke.points) {
      if ((q - p).distanceSquared <= reach * reach) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _down(e.localPosition),
      onPointerMove: (e) => _move(e.localPosition),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: MouseRegion(
        cursor: widget.erasing
            ? SystemMouseCursors.cell
            : SystemMouseCursors.precise,
        child: CustomPaint(
          painter: _InkPainter(
            strokes: widget.strokes,
            active: _active,
            activeColor: widget.color,
            activeWidth: widget.width,
            rule: c.lineSoft,
            ruleSpacing: widget.ruleSpacing,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.strokes,
    required this.active,
    required this.activeColor,
    required this.activeWidth,
    required this.rule,
    required this.ruleSpacing,
  });

  final List<InkStroke> strokes;
  final List<Offset>? active;
  final Color activeColor;
  final double activeWidth;
  final Color rule;
  final double ruleSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    if (ruleSpacing > 0) {
      final linePaint = Paint()
        ..color = rule
        ..strokeWidth = 1;
      for (var y = ruleSpacing; y < size.height; y += ruleSpacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }

    for (final s in strokes) {
      _drawStroke(canvas, s.points, s.color, s.width);
    }

    final live = active;
    if (live != null) _drawStroke(canvas, live, activeColor, activeWidth);
  }

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width,
  ) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Tek nokta bir çizgi değil; nokta olarak konur, yoksa hiç görünmez.
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      // Çizilmekte olan vuruş her karede uzuyor; kimlik karşılaştırması onu
      // kaçırırdı, uzunluğu da bakıyoruz.
      old.strokes.length != strokes.length ||
      old.active?.length != active?.length ||
      !identical(old.strokes, strokes) ||
      old.activeColor != activeColor ||
      old.rule != rule;
}
