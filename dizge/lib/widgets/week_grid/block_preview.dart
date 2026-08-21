/// Bloğun iki hafif kopyası: tıklayınca açılan önizleme ve sürüklenen hayalet.
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/task.dart';
import '../../theme.dart';
import '../cancel_action.dart';
import '../owner_avatar.dart';
import '../task_check.dart';

/// Bloğa tıklayınca açılan hafif önizleme.
///
/// Neden doğrudan düzenleyici değil: bir işin ne olduğuna bakmak, onu
/// değiştirmekten çok daha sık yapılan bir şey. Tam sheet ekranı kaplayıp
/// takvimi gizliyordu; burada hafta arkada durmaya devam ediyor. Düzenlemek
/// isteyen tek tıkla oraya geçiyor.
class Preview extends StatelessWidget {
  const Preview({
    super.key,
    required this.task,
    required this.day,
    required this.done,
    required this.onEdit,
    required this.onToggleDone,
    this.cancelled = false,
    this.onCancel,
  });

  final Task task;
  final DateTime day;
  final bool done;
  final VoidCallback onEdit;

  /// İşin **bu gününü** tamamlar / geri alır.
  ///
  /// Kart açıldığında görünen ilk şey bu kutu. Eskiden burada yalnız
  /// tamamlanmışlığı *bildiren* soluk bir ✓ ikonu vardı: takvimden bir işi
  /// yaptım demenin hiçbir yolu yoktu, tek yer gün görünümüydü.
  final VoidCallback onToggleDone;

  /// İş bu gün için iptal edilmiş mi? Başlığın üstü çizili görünmesini de bu
  /// belirliyor: iptal edilen iş, tamamlanan iş gibi "bugünkü listeden düştü".
  final bool cancelled;

  /// İşin bu gününü iptal eder / iptali geri alır. Tek düğme, tek etiket:
  /// rutinde günü atlamak, tek günlük işte havuza almak demek ama kart bunu
  /// bilmiyor (plan K3). Havuz bağlanmamışken null.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.event(task.color, done: done);

    // Bloğun kendisinde yer yok diye kırpılan alanlar burada tam görünür.
    final details = <(IconData, String)>[
      (Icons.schedule, task.timeString),
      if (task.repeat.type != RepeatType.once)
        (Icons.repeat, task.repeat.describe(task.date)),
      if (task.categoryName.isNotEmpty)
        (Icons.label_outline, task.categoryName),
      if (task.place.isNotEmpty) (Icons.place_outlined, task.place),
      if (task.note.isNotEmpty) (Icons.notes, task.note),
    ];

    return ConstrainedBox(
      // 260px'ti; "Kenara al" eklenince iki düğme 43 piksel taştı. Düğmelerden
      // birini ikona indirmek yerine kart genişledi: ikisi de tek kelimeyle
      // anlaşılmayan eylemler.
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bloktaki şeridin küçük yankısı: hangi bloğu açtığın belli olsun.
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(top: S.hair, right: S.sm),
                decoration: BoxDecoration(
                  color: style.stripe,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(
                  task.title.isEmpty ? 'Başlıksız' : task.title,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: T.strong,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    decoration: (done || cancelled)
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              // Durum bildiren ikonun yerinde artık dokunulabilir bir kutu
              // var. Aynı köşe, aynı boy — fark, işe yarıyor olması.
              TaskCheck(
                done: done,
                onToggle: onToggleDone,
                label: task.title.isEmpty ? 'Başlıksız' : task.title,
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          // "Kimin işi" satırı (Y4.4f). Detay listesinin **üstünde**: saatten
          // önce gelen soru, paylaşılan bir takvimde "bu benim mi" sorusu.
          // Kişisel bağlamda kendini gizliyor.
          if (task.ownerId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: S.xs),
              child: OwnerLine(
                ownerId: task.ownerId,
                style: TextStyle(
                  color: c.inkDim,
                  fontSize: T.caption,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          for (final (icon, text) in details)
            Padding(
              padding: const EdgeInsets.only(bottom: S.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: I.xs, color: c.inkFaint),
                  const SizedBox(width: S.xs),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.inkDim,
                        fontSize: T.caption,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: S.sm),
          // `Row` değil `Wrap`: etiket "Bugün iptal" iken sığan sıra, "İptali
          // geri al" olunca 320 pikseli taşıyordu. Kartı üçüncü kez
          // genişletmek yerine sıranın kendisi kırılabilir oldu — yazı tipi
          // büyütülmüş bir ekranda da (metin ölçeği) aynı sorun çıkardı.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: S.xs,
            runSpacing: S.xs,
            children: [
              // "Bugün iptal" burada, sağ tık menüsünde olduğu gibi: sağ tık
              // dokunmatik ekranda hiç yok, menüye orada ulaşılamıyor.
              // Önizleme her iki girdi türünde de tek dokunuşla açılıyor.
              //
              // Tek düğme: eskiden rutin "Bugün atla", tek günlük iş "Kenara
              // al" diyordu ve kart hangisini çizeceğine kendisi karar
              // veriyordu. İki etiket aynı niyetin iki adıydı.
              //
              // İkonsuz: iki kelimelik etiketin yanında ikon, sıranın
              // kırılma eşiğini boş yere aşağı çekiyordu.
              if (onCancel != null)
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: onCancel,
                  child: Text(cancelLabel(cancelled)),
                ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onEdit,
                child: const Text('Düzenle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sürüklenirken parmağı takip eden yükseltilmiş kopya + canlı saat rozeti.
class DragPreview extends StatelessWidget {
  const DragPreview({super.key, required this.task, required this.label});

  final Task task;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.event(task.color);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: R.radiusXs,
        border: Border.all(color: c.surface, width: 1.5),
        // Kendi kategori rengiyle parlıyor: parmağın altındaki şeyin ne olduğu
        // siyah zeminde gölgeyle anlaşılmıyordu.
        boxShadow: [...c.shadowLg, ...c.glowOf(task.color)],
      ),
      // Sürüklenen kopya da yerdeki blokla aynı dili konuşur: solda şerit,
      // gövdede aynı soluk zemin. Farklı görünseydi parmağın altındaki şeyin
      // bırakılınca neye dönüşeceği belirsiz kalırdı.
      child: ClipRRect(
        borderRadius: R.radiusXs,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 3, child: ColoredBox(color: style.stripe)),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.xs, S.xs, S.xs, S.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: style.ink,
                          fontSize: T.micro,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: S.hair),
                      Flexible(
                        child: Text(
                          task.title.isEmpty ? 'Başlıksız' : task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.ink.withValues(alpha: 0.9),
                            fontSize: T.micro,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
