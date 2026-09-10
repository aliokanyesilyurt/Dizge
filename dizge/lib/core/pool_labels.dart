/// Havuzun adı ve havuza giriş cümleleri — tek yer.
///
/// Eskiden "Kenarda Bekleyenler" diyordu ve aynı ad dört yüzeyde (menü,
/// panel, şerit, ekran) ayrı ayrı yazılmıştı. Ad değişince hepsi birlikte
/// değişsin diye burada; `cancelLabel` ile aynı ders.
library;

/// Havuzun kendisi: menü satırı, panel ve ekran başlığı.
const String kPoolName = 'Havuz';

/// Şeridin ipucu: sayı varsa parantez içinde.
String poolCountLabel(int count) =>
    count == 0 ? kPoolName : '$kPoolName ($count)';

/// Bir iş havuza girdiğinde çıkan bildirim.
const String kMovedToPool = 'Havuza alındı';
