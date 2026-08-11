import 'package:flutter/material.dart';

import '../theme.dart';

/// Uygulamanın işareti — kenar çubuğunun tepesinde ve karşılama ekranında
/// aynı şey.
///
/// Ayrı bir dosyaya çıkarıldı çünkü artık iki yerde görünüyor ve ikisinin
/// birbirinden ayrılması sessiz bir tutarsızlık olurdu: marka, kullanıcının
/// uygulamayı tanıdığı ilk karedir.
///
/// Oranlar [size] üzerinden türetiliyor; 30 piksellik kenar çubuğu hâli
/// (yarıçap 9, ikon 16) birebir korunur.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.accent, Color.lerp(c.accent, c.secondary, 0.55)!],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: c.shadowSm,
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * 8 / 15,
        color: c.onAccent,
      ),
    );
  }
}
