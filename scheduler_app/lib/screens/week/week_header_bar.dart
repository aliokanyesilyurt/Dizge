import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme.dart';

/// Haftalık görünümün başlık çubuğu.
///
/// Ayrı bir dosyada duruyor çünkü `WeekViewScreen` zaten ızgara durumunu,
/// sayfa denetleyicisini ve düzenleyici akışlarını taşıyor; başlığın kendi
/// düzen kuralları (taşma, duyarlılık, hiyerarşi) oraya karışmasın.
///
/// ## Hiyerarşi
///
/// Bir ekranda tek birincil eylem olur — burada **+ Yeni**. Geri kalan her şey
/// sessiz: gezinme okları `ghost`, "Bugün" `outline`. Bu, shadcn'in düğme
/// varyantlarını kullanmanın asıl sebebi; görsel süs değil, okunur bir sıralama.
///
/// Durum tutmaz: gördüğü her şeyi parametre olarak alır, her eylemi geri
/// bildirir. Böylece testte tek başına kurulabiliyor.
class WeekHeaderBar extends StatelessWidget {
  const WeekHeaderBar({
    super.key,
    required this.rangeLabel,
    required this.offsetLabel,
    required this.isCurrentWeek,
    required this.density,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onDensityChanged,
    required this.onCreate,
  });

  /// "3 – 9 Ağustos 2026" — ekranın tek vurgulu satırı.
  final String rangeLabel;

  /// "Bu hafta" / "Geçen hafta" — bağlam, vurgu değil.
  final String offsetLabel;

  final bool isCurrentWeek;
  final GridDensity density;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<GridDensity> onDensityChanged;
  final VoidCallback onCreate;

  /// Bu genişliğin altında yoğunluk seçici ile "+ Yeni"nin yazısı düşer.
  /// 390px telefonda beş öğe yan yana sığmıyor; sığdırmaya çalışmak yerine
  /// ikincil olanı ikona indiriyoruz.
  static const double _compactWidth = 600;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tight = MediaQuery.sizeOf(context).width < _compactWidth;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          // Gezinme solda ve bitişik: ileri/geri tek bir hareket ekseni.
          _IconButton(
            icon: Icons.chevron_left_rounded,
            label: 'Önceki hafta',
            onPressed: onPrevious,
          ),
          _IconButton(
            icon: Icons.chevron_right_rounded,
            label: 'Sonraki hafta',
            onPressed: onNext,
          ),

          // "Bugün" yalnızca gerektiğinde belirir — bu haftadayken anlamsız bir
          // düğme, sakin kromun ilk kuralına aykırı olurdu.
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.curve,
            child: isCurrentWeek
                ? const SizedBox(width: 0)
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: onToday,
                      child: const Text('Bugün'),
                    ),
                  ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  offsetLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrentWeek ? c.accent : c.inkFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          _DensitySelect(
            value: density,
            onChanged: onDensityChanged,
            iconOnly: tight,
          ),
          const SizedBox(width: 8),

          ShadButton(
            size: ShadButtonSize.sm,
            onPressed: onCreate,
            leading: const Icon(Icons.add_rounded, size: 16),
            child: tight ? null : const Text('Yeni'),
          ),
        ],
      ),
    );
  }
}

/// Etiketi yalnız ipucunda görünen ikon düğmesi.
///
/// `Tooltip` süs değil: ikonun tek başına ne yaptığını söylemediği her yerde
/// hem fare kullanıcısına açıklama hem ekran okuyucuya `Semantics` etiketi
/// veren tek şey o. Çıplak `ShadButton.ghost` ikisini de vermiyor.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: ShadButton.ghost(
        width: 36,
        height: 36,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(icon, size: 20, semanticLabel: label),
      ),
    );
  }
}

/// Üç kademeli yoğunluk seçici.
///
/// Önceki hâli döngüsel bir ikon düğmesiydi: kaç seçenek olduğu, hangisinde
/// olunduğu ve istenene kaç tıkta varılacağı görünmüyordu. Açılır liste üçünü
/// de bir bakışta veriyor.
class _DensitySelect extends StatelessWidget {
  const _DensitySelect({
    required this.value,
    required this.onChanged,
    required this.iconOnly,
  });

  final GridDensity value;
  final ValueChanged<GridDensity> onChanged;

  /// Dar ekranda etiket düşer, yalnız ikon kalır.
  final bool iconOnly;

  static IconData _iconFor(GridDensity density) => switch (density) {
        GridDensity.compact => Icons.density_small_rounded,
        GridDensity.cozy => Icons.density_medium_rounded,
        GridDensity.spacious => Icons.density_large_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Izgara yoğunluğu',
      child: ShadSelect<GridDensity>(
        initialValue: value,
        // Dar ekranda kutu ikon genişliğine iner; etiketli hâlde üç seçeneğin
        // en uzunu ("Sıkışık") kırpılmadan sığsın diye sabit bir taban var.
        minWidth: iconOnly ? 0 : 132,
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
        options: [
          for (final density in GridDensity.values)
            ShadOption(
              value: density,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconFor(density), size: 16),
                  const SizedBox(width: 8),
                  Text(density.label),
                ],
              ),
            ),
        ],
        selectedOptionBuilder: (context, selected) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(selected), size: 16),
            if (!iconOnly) ...[
              const SizedBox(width: 8),
              Text(selected.label),
            ],
          ],
        ),
      ),
    );
  }
}
