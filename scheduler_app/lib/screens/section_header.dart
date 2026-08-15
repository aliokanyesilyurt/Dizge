import 'package:flutter/material.dart';
import '../theme.dart';

/// Ekranların üstündeki tutarlı başlık bloğu (başlık + alt açıklama + isteğe
/// bağlı sağ aksiyon).
///
/// Tipografi hiyerarşisi burada kurulur: başlık `headlineSmall` (sıkı harf
/// aralığı, ağır), alt satır soluk ve küçük. Aradaki büyük fark, gözün önce
/// nerede duracağını söyler.
///
/// Yatay boşluk [S.gutter]'dan okunur ve altındaki gövde de aynı sabiti
/// kullanır. Daha önce başlık soldan 24, listeler 20 kullanıyordu; dört
/// piksellik bu fark tek başına görünmüyordu ama sekme değiştirince başlığın
/// yatayda zıplaması olarak okunuyordu.
class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.xl, S.gutter, S.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: S.xs),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
