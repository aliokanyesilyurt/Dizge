import 'package:flutter/material.dart';

/// Liste ekranlarının okuma genişliği: geniş pencerede içerik ortada bir
/// sütunda durur, dar pencerede hiçbir şey değişmez.
///
/// **Neden var.** Birincil hedef Windows ve orada pencere 1920 piksel
/// olabiliyor. Bir alışkanlık kartı o genişlikte solda 10 piksellik bir renk
/// noktası, sağda bir seri sayısı ve arada 1700 piksel boşluktan ibaret
/// kalıyordu — kart değil, cetvel. Göz satırın sonundan başına dönerken
/// kayboluyor.
///
/// **Neden 720.** Yeni bir sayı uydurulmadı: Notlar ekranının düzenleyicisi
/// bu sınırı zaten kullanıyordu.
///
/// **Neden başlığı da sarıyor.** Yalnız liste sınırlansaydı başlık tam
/// genişlikte kalır ve C2'de kapatılan hizasızlık geri gelirdi. Sarmalın
/// içine ekranın **tamamı** girer: başlık da gövdeyle aynı sütunda.
///
/// **Kimler kullanmaz.** Takvim ekranları (Hafta, Ay, Yıl, Gün). Orada
/// genişlik boşa gitmiyor — bir güne bir sütun, bir saate bir satır düşüyor.
class ContentColumn extends StatelessWidget {
  /// Okunabilir satır uzunluğunun üst sınırı.
  static const double maxWidth = 720.0;

  final Widget child;

  const ContentColumn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
