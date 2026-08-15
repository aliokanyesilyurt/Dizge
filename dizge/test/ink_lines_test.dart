import 'package:dizge/core/ink_lines.dart';
import 'package:flutter_test/flutter_test.dart';

/// A1 — satır ayırma. Motorsuz, saf geometri.
///
/// Bu testlerin gerçek kalem gerektirmemesi, satır ayırmanın tanımadan ayrı
/// tutulmasının başlıca sebebi: ajandanın en kırılgan adımı burada, gerçek
/// donanım olmadan sınanabiliyor.
void main() {
  /// Soldan sağa giden yatay bir vuruş — bir harf yerine geçer.
  List<Offset> letter(double x, double y, {double w = 10, double h = 12}) => [
    Offset(x, y),
    Offset(x + w / 2, y - h),
    Offset(x + w, y),
  ];

  /// "i" harfinin noktası: satırın üstünde duran minik vuruş.
  List<Offset> dot(double x, double y) => [Offset(x, y), Offset(x + 1, y + 1)];

  /// Bir satır dolusu yazı: [count] harf, [y] taban çizgisinde.
  List<List<Offset>> writtenLine(
    double y, {
    int count = 5,
    double x0 = 20,
    double h = 12,
  }) => [for (var i = 0; i < count; i++) letter(x0 + i * 14, y, h: h)];

  test('boş sayfa boş liste verir', () {
    expect(splitIntoLines(const []), isEmpty);
    // Dokunulup çekilmiş ama iz bırakmamış vuruşlar da sayılmaz.
    expect(splitIntoLines(const [[], []]), isEmpty);
  });

  test('üst üste üç satır yazı üç satıra ayrılır', () {
    final strokes = [
      ...writtenLine(40),
      ...writtenLine(80),
      ...writtenLine(120),
    ];

    final lines = splitIntoLines(strokes);

    expect(lines, hasLength(3));
    for (final line in lines) {
      expect(line.strokes, hasLength(5));
    }
  });

  test('satırlar yukarıdan aşağıya sıralı gelir', () {
    // Girdi karışık sırada: kullanıcı ikinci satırı yazıp sonra birinciye
    // dönmüş olabilir. Çıktı sayfadaki sıraya göre olmalı.
    final strokes = [...writtenLine(120), ...writtenLine(40)];

    final lines = splitIntoLines(strokes);

    expect(lines, hasLength(2));
    expect(lines[0].bounds.top, lessThan(lines[1].bounds.top));
  });

  test('noktalı harflerin noktası kendi satırında kalır', () {
    // "i" ve "ı" ayrımının tamamı bu noktada; nokta bir üst satıra kaçarsa
    // hem üst satır bozulur hem harf kimliğini kaybeder.
    final strokes = [
      ...writtenLine(40),
      ...writtenLine(80),
      // İkinci satırdaki bir harfin noktası: taban çizgisinin 18 piksel
      // üstünde, yani birinci satıra ikinci satırdan daha yakın değil.
      dot(48, 62),
    ];

    final lines = splitIntoLines(strokes);

    expect(lines, hasLength(2));
    expect(lines[1].strokes, hasLength(6), reason: 'nokta ikinci satırda');
    expect(lines[0].strokes, hasLength(5));
  });

  test('satır içi vuruşlar soldan sağa sıralanır', () {
    // Kullanıcı önce sondaki harfi, sonra baştakini yazmış olsun — motora
    // giden sıra yine okuma sırası olmalı.
    final lines = splitIntoLines([letter(100, 40), letter(20, 40)]);

    expect(lines, hasLength(1));
    expect(lines.single.strokes.first.first.dx, 20);
    expect(lines.single.strokes.last.first.dx, 100);
  });

  test('tek satır, ne kadar uzun olursa olsun bölünmez', () {
    final lines = splitIntoLines(writtenLine(40, count: 20));

    expect(lines, hasLength(1));
    expect(lines.single.strokes, hasLength(20));
  });

  test('sıkışık yazıda satırlar ayrı kalır', () {
    // Tolerans sabit bir piksel değeri olsaydı, küçük yazıda iki satır
    // birleşirdi. Ortancadan türetilmesinin sınandığı yer burası.
    final strokes = [...writtenLine(30, h: 6), ...writtenLine(42, h: 6)];

    expect(splitIntoLines(strokes), hasLength(2));
  });
}
