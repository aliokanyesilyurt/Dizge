/// Bir ajanda sayfasındaki vuruşları **yazı satırlarına** ayırır.
///
/// ## Neden bu iş bizde, tanıma motorunda değil
///
/// Bir sayfaya beş görev yazılmışsa ve motora tek bir yığın vuruş
/// gönderilirse, geriye tek bir uzun cümle döner — beş görev değil. Satıra
/// ayırma, tanımadan **önce** gelmesi gereken bir adım.
///
/// Burada olmasının ikinci sebebi: bu adım motordan bağımsız. Ne WinRT ne ML
/// Kit karışıyor; saf geometri. Yani iki platformda da aynı davranır ve
/// gerçek bir kalem olmadan test edilebilir.
///
/// ## Nasıl çalışır
///
/// Vuruşlar dikey merkezlerine göre sıralanır ve sırayla gruplanır. Bir vuruş,
/// açık satırın dikey aralığıyla **kesişiyorsa** (ya da aralığa [_tolerance]
/// kadar yakınsa) o satıra katılır; katılmıyorsa yeni satır açar.
///
/// Tolerans sabit bir piksel değeri değil, sayfadaki vuruş yüksekliklerinin
/// ortancasından türetilir. Sabit bir sayı, iri yazıda satırları birleştirir,
/// ufak yazıda tek satırı ikiye böler.
library;

import 'dart:ui' show Offset, Rect;

/// Tek bir yazı satırı: kendi vuruşları ve onları saran kutu.
class InkLine {
  /// Satırın vuruşları, **soldan sağa** — yani okuma sırasında.
  final List<List<Offset>> strokes;

  /// Satırı saran kutu.
  final Rect bounds;

  const InkLine(this.strokes, this.bounds);

  @override
  String toString() => 'InkLine(${strokes.length} vuruş, $bounds)';
}

/// Vuruşları satırlara ayırır. Boş sayfa boş liste verir.
///
/// [tolerance] verilmezse ortanca vuruş yüksekliğinin yarısı kullanılır.
/// Bunu dışarıdan vermek yalnız testlerin işine yarar.
List<InkLine> splitIntoLines(List<List<Offset>> strokes, {double? tolerance}) {
  // Boş vuruşlar (parmağın değip çekildiği tek nokta bile değil) elenir.
  final drawn = strokes.where((s) => s.isNotEmpty).toList();
  if (drawn.isEmpty) return const [];

  final boxes = drawn.map(_boundsOf).toList();

  // Sıralama için indeksleri taşıyoruz: vuruşun kendisi ile kutusu birlikte
  // gitmeli, yoksa gruplama yanlış vuruşu toplar.
  final order = List.generate(drawn.length, (i) => i)
    ..sort((a, b) => boxes[a].center.dy.compareTo(boxes[b].center.dy));

  final gap = tolerance ?? _medianHeight(boxes) / 2;

  final lines = <List<int>>[];
  var openTop = 0.0;
  var openBottom = 0.0;

  for (final i in order) {
    final box = boxes[i];

    // Açık satır yoksa ya da vuruş ona uzaksa yeni satır açılır.
    final fits =
        lines.isNotEmpty &&
        box.top <= openBottom + gap &&
        box.bottom >= openTop - gap;

    if (fits) {
      lines.last.add(i);
      // Aralık büyür: noktalı harfler ve alta sarkan kuyruklar satırın
      // yüksekliğini genişletir, sonraki vuruşlar bu genişlemiş aralığa göre
      // ölçülür.
      if (box.top < openTop) openTop = box.top;
      if (box.bottom > openBottom) openBottom = box.bottom;
    } else {
      lines.add([i]);
      openTop = box.top;
      openBottom = box.bottom;
    }
  }

  return [
    for (final line in lines)
      InkLine(
        // Satır içinde okuma sırası: soldan sağa. Kullanıcı "toplantı"nın
        // noktasını en sona koymuş olabilir; motor onu yerinde görmeli.
        (line.toList()..sort((a, b) => boxes[a].left.compareTo(boxes[b].left)))
            .map((i) => drawn[i])
            .toList(),
        line.map((i) => boxes[i]).reduce((a, b) => a.expandToInclude(b)),
      ),
  ];
}

Rect _boundsOf(List<Offset> stroke) {
  var left = stroke.first.dx, right = stroke.first.dx;
  var top = stroke.first.dy, bottom = stroke.first.dy;

  for (final p in stroke) {
    if (p.dx < left) left = p.dx;
    if (p.dx > right) right = p.dx;
    if (p.dy < top) top = p.dy;
    if (p.dy > bottom) bottom = p.dy;
  }

  return Rect.fromLTRB(left, top, right, bottom);
}

/// Ortanca yükseklik — ortalama değil.
///
/// Ortalama, tek bir uzun alt çizgiyle ya da sayfayı bölen bir çizgiyle
/// savrulur. Ortanca, "bu sayfadaki tipik harf ne kadar iri" sorusunun
/// gürültüye dayanıklı yanıtı.
double _medianHeight(List<Rect> boxes) {
  final heights = boxes.map((b) => b.height).toList()..sort();
  final mid = heights.length ~/ 2;

  final median = heights.length.isOdd
      ? heights[mid]
      : (heights[mid - 1] + heights[mid]) / 2;

  // Yalnız nokta koyulmuş bir sayfada ortanca sıfır çıkar; o zaman gruplama
  // toleranssız kalır ve her nokta kendi satırı olur. Küçük bir taban koyuyoruz.
  return median <= 0 ? 8.0 : median;
}
