import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Uygulamadaki her "içerik parçası" bir [Node]'dur: hem görevler (Task) hem de
/// dokümanlar (Note) bu tabandan türer. Böylece etiketleme, [[bağlantı]] çözümü
/// ve arama tek bir soyutlama üzerinden çalışır (Obsidian tarzı graph yapısı).
///
/// Mimari karar — Veri formatı: runtime'da JSON, metin gövdesi ([body]) ise
/// Markdown string olarak saklanır. Yani meta veri (JSON) + içerik (Markdown)
/// aynı objede birleşir.
enum NodeKind { task, note }

const _uuid = Uuid();

/// Yeni node'lar için gerçek UUID üretir. (Eski kayıtlar string id'lerini korur.)
String newNodeId() => _uuid.v4();

/// Hem Task hem Note'un uyduğu ortak sözleşme. UI ve servisler mümkün olduğunca
/// bu arayüz üzerinden çalışmalı; tipe özel alanlar (dueDate, status vb.) ilgili
/// sınıfta yaşar.
abstract class Node {
  String get id;
  NodeKind get kind;

  /// Başlık — aynı zamanda [[Başlık]] bağlantılarının çözümlendiği anahtar.
  String get title;

  /// Markdown gövde. Görevlerde "açıklama", notlarda ana metin.
  String get body;

  /// Serbest etiketler (ör. "yazılım", "spor"). '#' işareti olmadan saklanır.
  Set<String> get tags;

  DateTime get createdAt;
  DateTime get updatedAt;

  /// Hangi gruba ait; **null ise kişisel** (Y4).
  ///
  /// Sunucuda payload'ın içinde değil, satırın `group_id` sütununda duruyor —
  /// `SupabaseGateway` okurken buraya katıyor, gönderirken tel gösteriminin
  /// tepesine çıkarıyor. Bir kaydın grubu, o kaydın niteliğidir; ikinci bir
  /// "satır meta" kanalı açmak `mergeJson`'ın sözleşmesini bozardı (Y4a).
  String? get groupId;

  /// Kaydı **oluşturan** kişi. Sunucu yazar, istemci hiç dokunmaz (Y4).
  ///
  /// Sahiplik değil köken: grup kaydını her üye düzenleyebilir, bu alan yalnız
  /// "kimin işi" işaretini besler. Yetkinin kaynağı RLS, bu alan değil.
  String? get ownerId;

  Map<String, dynamic> toJson();
}

/// Saf doküman (bilgi bankası sayfası). Görev alanları yoktur; sadece metin +
/// bağlantılar. Bir görevden [[Not Adı]] ile buraya köprü kurulur.
class Note implements Node {
  @override
  final String id;
  @override
  String title;
  @override
  String body;
  @override
  final Set<String> tags;
  @override
  final DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  String? groupId;
  @override
  final String? ownerId;

  Note({
    String? id,
    this.title = '',
    this.body = '',
    Set<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.groupId,
    this.ownerId,
  }) : id = id ?? newNodeId(),
       tags = tags ?? <String>{},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  @override
  NodeKind get kind => NodeKind.note;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'note',
    'id': id,
    'title': title,
    'body': body,
    'tags': tags.toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    ...groupFields(groupId, ownerId),
  };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String?,
    title: (j['title'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    tags: readTags(j['tags']),
    createdAt: readDate(j['createdAt']),
    updatedAt: readDate(j['updatedAt']),
    groupId: j['groupId'] as String?,
    ownerId: j['ownerId'] as String?,
  );
}

// --- Serileştirme yardımcıları (tüm modeller ortak kullanır) ---------------

/// Grup alanlarının JSON karşılığı — üç modelde de aynı (Y4a).
///
/// [groupId] **null olsa bile yazılıyor** ve bu bilinçli: sunucu anahtarın
/// yokluğu ile null değerini ayırıyor — yokluk "grubuna dokunma", null
/// "gruptan çıkar" demek. Kaydın grubunu bilen istemcinin susması, "işi
/// gruptan çıkardım"ın sunucuya hiç gitmemesi olurdu.
///
/// [ownerId] ise yalnız doluyken: onu sunucu yazıyor, istemci hiç üretmiyor.
/// Boş bir anahtarı her kayda serpmek, yerel dosyaya anlamsız gürültü eklerdi.
Map<String, dynamic> groupFields(String? groupId, String? ownerId) => {
  'groupId': groupId,
  'ownerId': ?ownerId,
};

/// N5a öncesi pastel palet → bugünkü neon karşılığı.
///
/// Anahtarlar `kTaskColors`'ın eski sekizlisi, artı `kUnknownCategoryColor`'ın
/// eski tonu. Değerler bugünkü `kTaskColors` ile birebir aynı sırada;
/// `category_colors_test.dart` bunu her koşuda doğruluyor — palet değişip
/// eşleme unutulursa test yakalar.
///
/// Tabloyu burada, `Color` değil `int` anahtarlı tutmanın nedeni:
/// [colorFromHex] elinde zaten ayrıştırılmış `int` var, `Color` sarmalayıp
/// `hashCode` üzerinden arama yapmak bedava değil ve bu işlev her blok
/// çiziminde değil ama her yükleme/çekimde binlerce kez çağrılıyor.
const Map<int, int> kLegacyTaskColors = {
  0xFFFF6090: 0xFFFF3D8B, // pembe
  0xFF4FC3F7: 0xFF38BDF8, // mavi
  0xFF81C784: 0xFF34E39B, // yeşil
  0xFFFFB74D: 0xFFFF9E3D, // turuncu
  0xFFBA68C8: 0xFFA78BFA, // mor
  0xFF4DD0E1: 0xFF00E5C7, // turkuaz
  0xFFFFF176: 0xFFF2E14C, // sarı
  0xFFE57373: 0xFFFF5C5C, // kırmızı
  0xFF529CCA: 0xFF5AA9FF, // rengi bilinmeyen kategori
};

/// Renk <-> "AARRGGBB" hex string. JSON'da okunur ve platformdan bağımsız.
String colorToHex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

/// Kayıttaki hex'i renge çevirir; eski paletten gelen değeri **neon
/// karşılığına taşır**.
///
/// Göç neden burada, okuma anında:
///
/// * Yalnız yerel anlık görüntüyü bir kez göçürmek kendi kendini bozardı —
///   sonraki artımlı çekim sunucudaki pastel satırı yerele geri yazar.
/// * Göçü mutasyon kuyruğuna yazıp sunucuya itmek, grup işlerinde
///   **başkasının** verisini yeniden yazmak olurdu; üstelik outbox tavanını
///   tek hamlede doldururdu.
/// * Bu işlev ise uygulamadaki her kalıcı rengin tek geçidi: iş, alışkanlık,
///   kategori — yerelden de gelse sunucudan da gelse buradan geçiyor. Tek
///   nokta, unutulması imkânsız.
///
/// Bedeli: eski renkler için `fromJson(toJson(x)) == x` artık doğru değil,
/// pastel yazılır neon okunur. Kusur değil, işin kendisi. Yeni renkler için
/// eşleme etkisiz eleman, yani çevrim iki kez uygulanınca da aynı sonucu
/// veriyor.
///
/// Eşleme **tam**: uygulamada serbest renk seçici yok (seçiciler yalnız
/// `kTaskColors`'ı geziyor), yani diskteki her değer bu tablonun ya
/// anahtarında ya değerinde. Yine de tabloda olmayan bir hex'e dokunulmuyor —
/// elle düzenlenmiş bir kayıt ya da ileride gelecek bir renk sessizce
/// değişmesin.
Color colorFromHex(String? hex, {Color fallback = const Color(0xFF38BDF8)}) {
  if (hex == null) return fallback;
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return fallback;
  return Color(kLegacyTaskColors[v] ?? v);
}

/// Saat/dakika kırpılmış, yalnızca gün taşıyan tarih. Set anahtarı olarak kullanılır.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Yalnızca gün hassasiyetli tarih (YYYY-MM-DD).
String dateToKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? dateFromKeyOrNull(String? s) =>
    s == null ? null : DateTime.tryParse(s);

/// Tam zaman damgası; eksik/boşsa "şimdi"ye düşer (geriye dönük kayıtlar için).
DateTime readDate(dynamic v) {
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

/// Tam zaman damgası; eksik/bozuksa **null**.
///
/// [readDate]'in "şimdi"ye düşmesi çoğu alan için doğru ama senkron damgası
/// için yıkıcı: eksik bir `updatedAt`, kaydı her okumada en yeni ilan eder ve
/// sunucudaki kopyayı ezer. Çağıran taraf boşluğu kendi doğru varsayılanıyla
/// (genelde `createdAt`) doldursun diye ayrı bir okuyucu.
DateTime? readDateOrNull(dynamic v) =>
    v is String ? DateTime.tryParse(v) : null;

Set<String> readTags(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toSet() : <String>{};
