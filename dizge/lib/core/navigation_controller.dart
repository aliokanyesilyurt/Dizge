import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kenar çubuğunun açtığı bölümler.
enum AppSection {
  /// Elle yazılan gün yaprağı (A4). Yalnız kullanım modu izin verdiğinde
  /// kenar çubuğunda görünür; bölümün kendisi her zaman var, çünkü mod
  /// değiştiğinde kabuk yeniden kurulmuyor.
  agenda,
  year,
  month,
  week,
  hour,
  routines,
  todos,

  /// Kenarda bekleyenler (havuz). Haftalık ızgaranın şeridiyle aynı listeye
  /// bakar; ayrı bir bölüm olmasının sebebi şeridin **boşken görünmemesi**
  /// (plan K4).
  pool,
  notes,
  habits,
  reports,
  account,
}

/// Kabuğun o an gösterdiği bölüm ve — varsa — hangi ay/güne açılacağı.
///
/// Hedef bilgisi burada duruyor çünkü bölüm geçişini *başlatan* ekran (yıl
/// görünümü) ile onu *çizen* yer (kabuk) farklı: yıl görünümü "aylığa geç"
/// derken hangi ayı kastettiğini başka türlü söyleyemezdi.
@immutable
class NavState {
  const NavState(this.section, {this.anchor, this.day});

  final AppSection section;

  /// [AppSection.month] ve [AppSection.year] için açılacak ay/yıl — **ayın
  /// ilk günü**. Boşsa içinde bulunulan ay.
  ///
  /// Eskiden burası `int? month` idi (0 = Ocak) ve **yıl taşımıyordu**. Aylık
  /// ekran da bu yüzden yılı `DateTime.now().year` diye sabitlemek zorunda
  /// kalıyor, takvim Aralık'ta duvara tosluyordu. Ay damgasının yılıyla
  /// birlikte tek parça gezmesi o sınırı kaldırıyor.
  ///
  /// Gün değil ay tutuyor: "hangi aya bakıyoruz" sorusunun cevabında günün
  /// bir karşılığı yok, olsaydı iki farklı gün aynı ayı iki ayrı durum
  /// yapardı ve kabuk ekranı boşuna yeniden kurardı.
  final DateTime? anchor;

  /// [AppSection.hour] ve [AppSection.agenda] için açılacak gün. Boşsa bugün.
  ///
  /// [anchor] ile ayrı duruyor: biri "hangi ay", öteki "hangi gün". Tek alana
  /// bindirilseydi aylık ekran gün bilgisini yok saymak, gün ekranı da ayın
  /// birinci gününü gerçek bir seçimden ayırmak zorunda kalırdı.
  final DateTime? day;

  @override
  bool operator ==(Object other) =>
      other is NavState &&
      other.section == section &&
      other.anchor == anchor &&
      other.day == day;

  @override
  int get hashCode => Object.hash(section, anchor, day);
}

/// Takvim bölümleri arasındaki geçişin tek yeri.
///
/// ## Neden var
///
/// Önceden yıl → ay, ay → yıl ve ay → gün geçişleri `Navigator.push` ile tam
/// ekran rota açıyordu. O rota **kabuğun üstüne** biniyordu: kenar çubuğu
/// kayboluyor, kullanıcı "yan bar kapandı, bozuldu" ile karşılaşıyordu. Üstelik
/// geçişler üst üste yığılabildiği için (yıl → ay → yıl → ay …) geri tuşu
/// kimsenin beklemediği bir geçmişte geziniyordu.
///
/// Bu bölümler birbirinin *üstü* değil, **eşiti** — aynı takvimin farklı
/// yakınlaştırma kademeleri. Bu yüzden rota itilmiyor, kabuğun bölümü
/// değiştiriliyor: kenar çubuğu yerinde kalıyor ve nerede olduğun orada yazıyor.
class NavigationController extends StateNotifier<NavState> {
  /// Açılış bölümü: haftalık görünüm. Kullanıcı uygulamayı açtığında "bu hafta
  /// ne var" sorusunun cevabıyla karşılaşır.
  NavigationController() : super(const NavState(AppSection.week));

  void go(AppSection section) => state = NavState(section);

  /// Yıl görünümünden bir aya girer. [anchor] o ayın herhangi bir günü
  /// olabilir; durumda ayın ilk gününe yuvarlanır.
  void openMonth(DateTime anchor) => state = NavState(
    AppSection.month,
    anchor: DateTime(anchor.year, anchor.month),
  );

  /// Aylık görünümden 12 aylık ızgaraya çıkar.
  ///
  /// Yılı taşıyor: bakılan yıl unutulsaydı 2028'in Haziran'ından "12 ay"a
  /// basan kişi içinde bulunduğumuz yıla düşer, geri geldiği yere iki tıkla
  /// dönerdi.
  void openYear(int year) =>
      state = NavState(AppSection.year, anchor: DateTime(year));

  /// Ay görünümünden bir güne girer.
  void openDay(DateTime day) => state = NavState(AppSection.hour, day: day);

  /// Bir günün ajanda yaprağını açar (A2 — ajanda modunda görev yazma kapısı
  /// buraya iniyor).
  void openAgenda(DateTime day) =>
      state = NavState(AppSection.agenda, day: day);
}

final navigationProvider =
    StateNotifierProvider<NavigationController, NavState>(
      (ref) => NavigationController(),
    );
