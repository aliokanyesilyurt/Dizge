import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/task.dart' show Energy;
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
    required this.energy,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onDensityChanged,
    required this.onEnergyChanged,
    required this.onCreate,
    required this.rescuableCount,
    required this.onRescue,
    this.isEmptyWeek = false,
  });

  /// "3 – 9 Ağustos 2026" — ekranın tek vurgulu satırı.
  final String rangeLabel;

  /// "Bu hafta" / "Geçen hafta" — bağlam, vurgu değil.
  final String offsetLabel;

  /// Haftada hiç iş yok mu?
  ///
  /// Eskiden bunu ızgaranın ortasında yüzen bir kart söylüyordu (T2). Kart iki
  /// sorun üretiyordu: plan yapılmamış bir hafta hata değil ki ekranın
  /// ortasında duyurulsun, ve ızgaranın üstündeki o katman havuzdan gelen
  /// bırakmayı tam ortada kesiyordu.
  ///
  /// Bilgi burada, zaten var olan bağlam satırının devamında: hizalı, sessiz,
  /// ızgaranın üstünde hiçbir şey kaplamıyor.
  final bool isEmptyWeek;

  final bool isCurrentWeek;
  final GridDensity density;

  /// "Bugün enerjim" — null ise filtre kapalı.
  final Energy? energy;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<GridDensity> onDensityChanged;
  final ValueChanged<Energy?> onEnergyChanged;
  final VoidCallback onCreate;

  /// Bugün "Günü kurtar"ın dokunabileceği iş sayısı. 0 ise düğme pasif —
  /// basıldığında hiçbir şey olmayan bir düğme, kullanıcıya özelliğin
  /// bozuk olduğunu düşündürür.
  final int rescuableCount;

  final VoidCallback onRescue;

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

          // Gezinmenin yanındaki tek yuva, haftaya göre yer değiştiriyor:
          // bu haftadayken "Günü kurtar", başka haftadayken "Bugün".
          //
          // İkisi aynı yuvada durabiliyor çünkü hiçbir zaman ikisi birden
          // anlamlı değil: "Bugün" zaten bugündeyken anlamsız, "Günü kurtar"
          // ise tanımı gereği yalnız bugüne dokunuyor — geçen haftayı
          // kurtarmak diye bir şey yok. Bu, başlığın 390px'teki genişliğini
          // **hiç artırmadan** altıncı denetimi eklemenin tek yolu (plan
          // §5.3'te açık bırakılan soru).
          //
          // Dar ekranda ikisinin de yazısı düşer; başlık zaten yoğunluk ve
          // "Yeni" için aynı kuralı uyguluyor.
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.curve,
            child: Padding(
              padding: EdgeInsets.only(left: tight ? 0 : 8),
              child: isCurrentWeek
                  ? _RescueButton(
                      count: rescuableCount,
                      onPressed: onRescue,
                      iconOnly: tight,
                    )
                  : (tight
                        ? _IconButton(
                            icon: Icons.today_rounded,
                            label: 'Bugün',
                            onPressed: onToday,
                          )
                        : ShadButton.outline(
                            size: ShadButtonSize.sm,
                            onPressed: onToday,
                            child: const Text('Bugün'),
                          )),
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
                Semantics(
                  // Ekran okuyucu haftanın boşaldığını/dolduğunu duysun; kart
                  // kalkarken bu bilgiyi de kaybetmiyoruz.
                  liveRegion: true,
                  // İki `Text`'li bir `Row` değil, tek bir zengin metin: bu
                  // başlık 390px'te zaten sınırda (enerji seçici eklenince
                  // 1.7px taşmıştı) ve ikinci bir kutu eklemek onu 100px
                  // taşırdı. Tek metinde elips kendiliğinden çalışıyor —
                  // dar ekranda önce "hiç iş yok" kısalır, düzen bozulmaz.
                  child: Text.rich(
                    TextSpan(
                      text: offsetLabel,
                      style: TextStyle(
                        color: isCurrentWeek ? c.accent : c.inkFaint,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                      children: [
                        if (isEmptyWeek)
                          TextSpan(
                            text: ' · hiç iş yok',
                            style: TextStyle(
                              color: c.inkFaint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Sağdaki denetimler arası nefes payı dar ekranda kısalıyor: 390px'te
          // beş öğe ancak böyle sığıyor (enerji seçici eklenince 1.7px taşmıştı).
          SizedBox(width: tight ? 8 : 12),

          _EnergySelect(
            value: energy,
            onChanged: onEnergyChanged,
            iconOnly: tight,
          ),
          SizedBox(width: tight ? 4 : 8),

          _DensitySelect(
            value: density,
            onChanged: onDensityChanged,
            iconOnly: tight,
          ),
          SizedBox(width: tight ? 4 : 8),

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

/// "Günü kurtar" — günün geri kalanındaki esnek işleri kenara alan düğme.
///
/// Sessiz bir varyant (`outline`, birincil değil) bilinçli: bu düğme tek tıkla
/// sekiz işi kımıldatıyor, ekranın en yüksek sesli öğesi olması onu kazayla
/// basılası yapardı. Aradığında bulunacak kadar görünür, göze batmayacak
/// kadar sakin.
class _RescueButton extends StatelessWidget {
  const _RescueButton({
    required this.count,
    required this.onPressed,
    required this.iconOnly,
  });

  final int count;
  final VoidCallback onPressed;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;

    // Pasif hâlde ipucu sebebini söylüyor: sönük bir düğmeye basıp hiçbir şey
    // olmaması, sebebi yazmaktan çok daha sinir bozucu.
    return Tooltip(
      message: enabled
          ? 'Günü kurtar — bugünün kalan $count esnek işini kenara alır'
          : 'Kurtarılacak iş yok',
      child: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: enabled ? onPressed : null,
        leading: const Icon(Icons.cleaning_services_rounded, size: 15),
        child: iconOnly ? null : const Text('Günü kurtar'),
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

/// "Bugün enerjim" seçici.
///
/// Yoğunluk seçicinin **solunda**: yoğunluk ekranın nasıl göründüğünü, enerji
/// ise neye bakılacağını değiştiriyor. İçeriğe dokunan denetim, krom ayarından
/// önce gelir.
///
/// Seçim ızgarayı süzmez, **soluklaştırır**. Gizlemek "bugün enerjim düşük"
/// diyen birine işleri unutturur; solgun bir blok hâlâ oradadır, yalnız öne
/// çıkmaz.
class _EnergySelect extends StatelessWidget {
  const _EnergySelect({
    required this.value,
    required this.onChanged,
    required this.iconOnly,
  });

  final Energy? value;
  final ValueChanged<Energy?> onChanged;
  final bool iconOnly;

  /// Filtre kapalıyken görünen etiket. "Enerji" değil "Tüm işler": kapalı bir
  /// filtrenin ne yaptığını değil, ekranda ne olduğunu söylemek daha dürüst.
  static const String _allLabel = 'Tüm işler';

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Bugün enerjim',
      child: ShadSelect<Energy?>(
        initialValue: value,
        minWidth: iconOnly ? 0 : 148,
        onChanged: onChanged,
        options: [
          const ShadOption<Energy?>(value: null, child: Text(_allLabel)),
          for (final level in Energy.values)
            ShadOption<Energy?>(value: level, child: Text(level.label)),
        ],
        selectedOptionBuilder: (context, selected) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected == null
                  ? Icons.battery_full_rounded
                  : Icons.bolt_rounded,
              size: 16,
            ),
            if (!iconOnly) ...[
              const SizedBox(width: 8),
              Text(selected?.label ?? _allLabel),
            ],
          ],
        ),
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
            if (!iconOnly) ...[const SizedBox(width: 8), Text(selected.label)],
          ],
        ),
      ),
    );
  }
}
