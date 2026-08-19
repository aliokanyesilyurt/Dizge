/// Uygulamanın tasarım sistemi: renk, derinlik, yuvarlaklık, tipografi.
///
/// Mimari karar: renkler artık `static const` **değil**. Açık ve koyu tema aynı
/// anda var olabilmeli, tema değişince ağaç kendiliğinden yeniden çizilmeli.
/// Bu yüzden palet bir [ThemeExtension] olarak taşınır ve widget'lar onu
/// `context.colors` üzerinden okur:
///
/// ```dart
/// final c = context.colors;
/// Container(color: c.surface, ...)
/// ```
///
/// ## Tasarım yönü
///
/// Sakin, derinlikli ve minimal. Üç ilke:
///
/// 1. **Zemin geri çekilir, içerik öne çıkar.** Kartlar zeminden bir tık
///    *ileri* durur. Açık temada bunu yükseklik (gölge) söyler; koyu temada
///    zemin neredeyse saf siyah olduğu için gölge işe yaramaz ve görevi ince
///    bir kenar çizgisi devralır (bkz. [AppPalette.shadowSm]).
/// 2. **İki neon vurgu.** Camgöbeği birincil (bugün, seçim, bağlantı),
///    magenta ikincil (kaçan iş, "şu an"). Geri kalan her şey nötr gri
///    skalasında; renk yalnızca kullanıcının kendi kategorilerine ait.
/// 3. **Derinlik ışıktır.** Açıkta iki katmanlı gölge: dar/koyu (temas) +
///    geniş/soluk (ortam). Koyuda ise öne çıkan öğe kendi rengiyle çıkar —
///    [glow]. Parıltı üç yerle sınırlı; her yere serpilirse neon olmaz.
///
/// ## Dosya düzeni
///
/// Bu dosya artık yalnızca bir kapı: içerik üç parçaya ayrıldı ve buradan
/// dışa açılıyor. `import '../theme.dart';` yazan hiçbir dosya değişmedi.
library;

export 'theme/app_theme.dart';
export 'theme/palette.dart';
export 'theme/tokens.dart';
