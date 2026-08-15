import 'package:flutter/material.dart';

import 'node.dart' show colorFromHex, colorToHex;
import 'task.dart' show Task;

/// Ajanda sayfasındaki tek bir kalem vuruşu.
///
/// ## Neden `Sketch` yeniden kullanılmadı
///
/// `Sketch` (bkz. `models/task.dart`) bir **görevin eki**: tek renkli, tek
/// boyutlu, küçük bir çizim. Ajanda sayfası ise bir defter yaprağı — üstünde
/// kalem rengi değişir, bir şey çizilir, altı çizilir. Rengi sayfaya değil
/// **vuruşa** bağlamak bunun tek doğru yeri; `Sketch`'i zorlamak, sayfayı tek
/// renge mahkûm ederdi.
///
/// `Sketch` olduğu gibi duruyor ve görev ekleri hâlâ onu kullanıyor.
@immutable
class InkStroke {
  /// Vuruşun noktaları, çizildiği sırada.
  final List<Offset> points;

  final Color color;

  /// Kalem kalınlığı. Silgi ayrı bir tür değil — silme, vuruşu **listeden
  /// çıkarır**. Böylece "silinmiş bir vuruş" diye yarı-canlı bir durum
  /// oluşmuyor ve geri alma tek kurala iniyor: son işlemi ters çevir.
  final double width;

  const InkStroke({
    required this.points,
    required this.color,
    this.width = 2.0,
  });

  bool get isEmpty => points.isEmpty;

  Map<String, dynamic> toJson() => {
    // Noktalar düz bir sayı dizisi olarak yazılıyor: [x1,y1,x2,y2,…].
    // Nokta başına bir liste açmak, uzun bir sayfada JSON'u iki katına
    // çıkarıyordu.
    'p': [
      for (final o in points) ...[o.dx, o.dy],
    ],
    'c': colorToHex(color),
    'w': width,
  };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List).cast<num>();
    return InkStroke(
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
      color: colorFromHex(j['c'] as String?),
      width: (j['w'] as num?)?.toDouble() ?? 2.0,
    );
  }
}

/// Bir güne ait ajanda yaprağı.
///
/// Bir gün = bir sayfa. Sayfa, üstüne yazılan her şeyi olduğu gibi tutar;
/// görev oluşup oluşmaması sayfayı değiştirmez. Ajanda önce bir defterdir,
/// sonra bir girdi yöntemi — tanıma yanılsa bile yazdığın kaybolmaz (§Ab).
///
/// **Senkron kapsam dışı** (plan §9): sayfalar şimdilik yalnız bu cihazda
/// yaşıyor. Bu yüzden diğer varlıkların aksine `groupId`/`ownerId` taşımıyor
/// ve mutasyon kuyruğuna girmiyor. Alanları şimdiden eklemek, kullanılmayan
/// bir sözleşme yazmak olurdu.
@immutable
class AgendaPage {
  /// Sayfanın kimliği **günün kendisi**: bir güne bir yaprak düşer.
  ///
  /// Ayrı bir uuid taşımıyor — taşısaydı aynı güne iki sayfa açılabilirdi ve
  /// "hangisi bugünün sayfası" sorusunun yanıtı belirsizleşirdi.
  final DateTime day;

  final List<InkStroke> strokes;

  /// Yazının çizildiği tuval boyutu — sayfa başka bir pencere boyutunda
  /// açıldığında ölçeklemek için.
  final Size canvasSize;

  final DateTime updatedAt;

  AgendaPage({
    required DateTime day,
    this.strokes = const [],
    this.canvasSize = Size.zero,
    DateTime? updatedAt,
  }) : day = Task.dayKey(day),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  /// Sayfanın anahtarı: `2026-08-15`. Depoda ve haritalarda bununla aranır.
  String get key => keyOf(day);

  static String keyOf(DateTime day) {
    final d = Task.dayKey(day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  AgendaPage copyWith({
    List<InkStroke>? strokes,
    Size? canvasSize,
    DateTime? updatedAt,
  }) => AgendaPage(
    day: day,
    strokes: strokes ?? this.strokes,
    canvasSize: canvasSize ?? this.canvasSize,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'day': day.toIso8601String(),
    'strokes': [for (final s in strokes) s.toJson()],
    'w': canvasSize.width,
    'h': canvasSize.height,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory AgendaPage.fromJson(Map<String, dynamic> j) => AgendaPage(
    day: DateTime.parse(j['day'] as String),
    strokes: [
      for (final raw in (j['strokes'] as List? ?? const []))
        InkStroke.fromJson((raw as Map).cast<String, dynamic>()),
    ],
    canvasSize: Size(
      (j['w'] as num?)?.toDouble() ?? 0,
      (j['h'] as num?)?.toDouble() ?? 0,
    ),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
