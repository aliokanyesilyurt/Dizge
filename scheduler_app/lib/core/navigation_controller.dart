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
  const NavState(this.section, {this.month, this.day});

  final AppSection section;

  /// [AppSection.month] için açılacak ay (0 = Ocak). Boşsa içinde bulunulan ay.
  final int? month;

  /// [AppSection.hour] için açılacak gün. Boşsa bugün.
  final DateTime? day;

  @override
  bool operator ==(Object other) =>
      other is NavState &&
      other.section == section &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(section, month, day);
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

  /// Yıl görünümünden bir aya girer. [month] 0 tabanlı (0 = Ocak).
  void openMonth(int month) => state = NavState(AppSection.month, month: month);

  /// Ay görünümünden bir güne girer.
  void openDay(DateTime day) => state = NavState(AppSection.hour, day: day);
}

final navigationProvider =
    StateNotifierProvider<NavigationController, NavState>(
      (ref) => NavigationController(),
    );
