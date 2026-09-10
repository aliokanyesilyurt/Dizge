import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Google'ın dört renkli "G" işareti — "Google ile devam et" düğmesinde.
///
/// Varlık Google'ın oturum açma düğmesi kılavuzundaki resmî SVG
/// (`assets/brand/google_g.svg`); elle çizilmiş bir yaklaşık değil. Kılavuz
/// işaretin renklerinin değiştirilmemesini istiyor, bu yüzden temaya göre
/// boyanmıyor: koyu temada da dört renk kalıyor.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/google_g.svg',
    width: size,
    height: size,
    semanticsLabel: 'Google',
  );
}
