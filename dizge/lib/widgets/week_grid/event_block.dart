/// Izgaradaki tek bir işi çizen blok ve süre tutamağının jest tanıyıcısı.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/task.dart';
import '../../theme.dart';
import '../owner_avatar.dart';
import 'block_preview.dart';

class EventBlock extends StatefulWidget {
  const EventBlock({
    super.key,
    required this.task,
    required this.day,
    required this.done,
    required this.skipped,
    required this.compact,
    this.dimmed = false,
    this.onMoveToPool,
    this.onToggleSkip,
    required this.onEdit,
    required this.onToggleDone,
    required this.onDuplicate,
    required this.onDelete,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final Task task;
  final DateTime day;
  final bool done;

  /// Rutin bugünlüğüne atlandı mı? Tamamlanmadan ayrı bir durum: ikisi de üstü
  /// çizili görünür ama atlanan iş **yapılmadı**, yalnız bugünlüğüne geçildi.
  /// Ayrımı yalnız ekran okuyucu cümlesi ve [Task.completedOn] taşıyor.
  final bool skipped;

  /// Blok kısaysa başlık ve saat tek satırda birleşir.
  final bool compact;

  /// Enerji filtresi bu bloğu eledi mi? Solgunluğu üstteki [Opacity] veriyor;
  /// burada yalnızca ekran okuyucuya söylemek için duruyor — solgunluk göze
  /// görünüyorsa kulağa da görünmeli.
  final bool dimmed;

  /// İşi havuza alır. Rutinlerde ve havuz bağlanmamışken null.
  final VoidCallback? onMoveToPool;

  /// Rutinin bu gününü atlar / atlamayı kaldırır. Havuzun rutindeki karşılığı:
  /// tek günlük işin "Kenara al"ı neyse, rutinin "Bugün atla"sı o (plan K2/K4).
  /// Tek günlük işlerde null.
  final VoidCallback? onToggleSkip;

  /// Tam düzenleyiciyi açar. Bloğa tıklamak artık doğrudan buraya gitmiyor —
  /// önce hafif bir önizleme açılıyor, "Düzenle" oradan çağırıyor.
  final VoidCallback onEdit;

  /// İşin bu gününü tamamlar / geri alır. Önizleme kartındaki kutu ve sağ tık
  /// menüsündeki "Yaptım" aynı yere gidiyor.
  final VoidCallback onToggleDone;

  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  final void Function(LongPressStartDetails) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final void Function(LongPressEndDetails) onLongPressEnd;
  final VoidCallback onResizeStart;
  final void Function(DragUpdateDetails) onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  State<EventBlock> createState() => _EventBlockState();
}

class _EventBlockState extends State<EventBlock> {
  /// Bloğa tıklayınca açılan önizleme. Her blok kendi denetleyicisini tutuyor;
  /// ızgara ortak bir tane taşısaydı hangi bloğun açık olduğunu ayrıca
  /// izlemek gerekirdi.
  final _preview = ShadPopoverController();

  /// Klavye odağı. Düğüm açıkça tutuluyor: `Focus`'un kendi ürettiği düğüme
  /// dışarıdan erişilemiyor ve blok, ızgaranın tek klavye hedefi.
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'blok-${widget.task.id}',
  );

  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _preview.dispose();
    super.dispose();
  }

  /// Odaklıyken Enter düzenler, Delete/Backspace siler.
  ///
  /// Fare olmadan bir bloğa erişmenin başka yolu yoktu: ızgara tamamen jest
  /// üzerine kuruluydu ve klavyeyle yalnız başlık çubuğuna ulaşılabiliyordu.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        widget.onEdit();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        widget.onDelete();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _preview.toggle();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Ekran okuyucunun duyduğu cümle: "Toplantı, Salı 14:00 – 15:30, Ali Okan,
  /// tamamlandı".
  ///
  /// Blok içindeki parçalar `excludeSemantics` ile susturuluyor; yoksa okuyucu
  /// başlığı, saati ve ikonları ayrı ayrı, bağlamsız okurdu.
  ///
  /// [ownerName] grup bağlamında dolu, kişiselde null (Y4.4f): rozet göze
  /// görünüyorsa kulağa da görünmeli — tersi, gören kullanıcının bildiği bir
  /// şeyi görmeyenden saklamak olurdu.
  String _semanticLabelWith(String? ownerName) {
    final task = widget.task;
    final parts = <String>[
      task.title.isEmpty ? 'Başlıksız' : task.title,
      '${_weekdayNames[widget.day.weekday - 1]} ${task.timeString}',
      ?ownerName,
      if (task.isRoutine) 'rutin',
      if (widget.done) 'tamamlandı',
      // Üstü çizili iki farklı sebeple olabiliyor; ekranda ikisi de aynı
      // görünüyorsa kulağa ayrı gelmeli.
      if (widget.skipped) 'bugünlük atlandı',
      if (widget.dimmed) 'bugünkü enerjinin üstünde',
    ];
    return parts.join(', ');
  }

  static const _weekdayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final done = widget.done;
    final compact = widget.compact;
    final c = context.colors;
    final style = c.event(task.color, done: done);
    final title = task.title.isEmpty ? 'Başlıksız' : task.title;

    final titleStyle = TextStyle(
      color: style.ink,
      fontSize: T.micro,
      height: 1.2,
      fontWeight: FontWeight.w600,
      decoration: (done || widget.skipped) ? TextDecoration.lineThrough : null,
      decorationColor: style.ink.withValues(alpha: 0.7),
    );
    final timeStyle = TextStyle(
      color: style.ink.withValues(alpha: 0.82),
      fontSize: T.dense,
      height: 1.2,
      fontWeight: FontWeight.w500,
    );

    // Tamamlandı yalnız renge/çizgiye dayanmaz: ✓ ikonu da var (WCAG 1.4.1).
    final marks = <Widget>[
      if (done) Icon(Icons.check, size: compact ? 10 : 11, color: style.ink),
      // Atlanan gün de kendi işaretini taşıyor. ✓ ile aynı ikonu paylaşsaydı
      // "yaptım" ile "geçtim" ekranda ayırt edilemezdi.
      if (widget.skipped && !done)
        Icon(
          Icons.redo_rounded,
          size: compact ? 10 : 11,
          color: style.ink.withValues(alpha: 0.85),
        ),
      if (task.isRoutine)
        Icon(
          Icons.repeat,
          size: compact ? 9.5 : 10,
          color: style.ink.withValues(alpha: 0.85),
        ),
    ];

    // Sahiplik rozeti sağ üstte (Y4.4d). Kişisel bağlamda [OwnerAvatar]
    // kendini gizliyor, yani bu satır orada boş bir `SizedBox`tan ibaret.
    //
    // Başlığın **sonuna** konuyor, başına değil: baştaki her piksel başlığın
    // okunabilir uzunluğundan gidiyor ve 15 dakikalık blokta o pikseller
    // "Kahve"yi "Kah…" yapardı.
    final owner = <Widget>[
      if (task.ownerId != null) ...[
        const SizedBox(width: S.xs),
        OwnerAvatar(ownerId: task.ownerId, size: compact ? 12 : 14),
      ],
    ];

    final body = Container(
      padding: EdgeInsets.fromLTRB(S.xs, compact ? S.hair : S.xs, S.xs, S.hair),
      child: compact
          // Kısa blok: "Başlık · 09:00" tek satır.
          ? Row(
              children: [
                for (final mark in marks) ...[
                  mark,
                  const SizedBox(width: S.xs),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                const SizedBox(width: S.xs),
                Text(task.startString, maxLines: 1, style: timeStyle),
                ...owner,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final mark in marks) ...[
                      mark,
                      const SizedBox(width: S.xs),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    ...owner,
                  ],
                ),
                Text(
                  task.timeString,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: timeStyle,
                ),
              ],
            ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          // Sahip adı cümlenin içine `Consumer` üzerinden giriyor: bloğun geri
          // kalanı bir provider'a bağlı değil ve öyle kalsın — burada uyanan
          // tek şey etiket.
          child: Consumer(
            builder: (context, ref, child) => Semantics(
              button: true,
              label: _semanticLabelWith(ownerNameFor(ref, task.ownerId)),
              excludeSemantics: true,
              onTap: widget.onEdit,
              child: child,
            ),
            child: Focus(
              key: ValueKey('focus-${task.id}'),
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              onFocusChange: (has) => setState(() => _focused = has),
              child: DecoratedBox(
                // Odak halkası bloğun *dışına* çiziliyor: içeri çizilseydi
                // 15 dakikalık bir blokta yazının üstüne binerdi.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.xs + 2),
                  border: Border.all(
                    color: _focused ? c.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                position: DecorationPosition.foreground,
                // Önizleme burada: bloğun tamamına çapalanır, böylece açılan
                // kart bloğun kenarından çıkar, içindeki bir metnin yanından
                // değil.
                child: ShadPopover(
                  controller: _preview,
                  popover: (context) => Preview(
                    task: task,
                    day: widget.day,
                    done: done,
                    onEdit: () {
                      _preview.hide();
                      widget.onEdit();
                    },
                    // Kart kapanmıyor: bir işi işaretledikten sonra kartın
                    // kaybolması, "oldu mu" sorusunu cevapsız bırakırdı.
                    // Kutunun kendisi cevabı gösteriyor.
                    onToggleDone: widget.onToggleDone,
                    onMoveToPool: widget.onMoveToPool == null
                        ? null
                        : () {
                            _preview.hide();
                            widget.onMoveToPool!();
                          },
                    skipped: widget.skipped,
                    onToggleSkip: widget.onToggleSkip == null
                        ? null
                        : () {
                            _preview.hide();
                            widget.onToggleSkip!();
                          },
                  ),
                  // Sağ tık menüsü: içerideki uzun basma sürükleme başlatıyor ve
                  // `longPressEnabled` açık olsaydı taşımaya çalışan her el hareketi
                  // menüyü açardı. Menü yalnız sağ tıkla gelir.
                  child: ShadContextMenuRegion(
                    longPressEnabled: false,
                    items: [
                      // En üstte: menünün en sık istenen satırı bu. Sağ tık
                      // menüsü fare kullanıcısının kestirmesi, önizlemedeki
                      // kutuyu açmayı beklemesin.
                      ShadContextMenuItem(
                        leading: Icon(
                          done
                              ? Icons.remove_done_rounded
                              : Icons.check_rounded,
                          size: I.sm,
                        ),
                        onPressed: widget.onToggleDone,
                        child: Text(done ? 'Geri al' : 'Yaptım'),
                      ),
                      ShadContextMenuItem(
                        leading: const Icon(Icons.edit_outlined, size: I.sm),
                        onPressed: widget.onEdit,
                        child: const Text('Düzenle'),
                      ),
                      ShadContextMenuItem(
                        leading: const Icon(Icons.copy_outlined, size: I.sm),
                        onPressed: widget.onDuplicate,
                        child: const Text('Kopyala'),
                      ),
                      // Rutinde bu eylem hiç görünmüyor: "her gün tekrarlayan
                      // ama hiçbir gün görünmeyen iş" tanımsız (plan K2).
                      if (widget.onMoveToPool != null)
                        ShadContextMenuItem(
                          leading: const Icon(Icons.inbox_rounded, size: I.sm),
                          onPressed: widget.onMoveToPool,
                          child: const Text('Kenara al'),
                        ),
                      // Rutinde havuzun yerini bu alıyor (K4).
                      if (widget.onToggleSkip != null)
                        ShadContextMenuItem(
                          leading: Icon(
                            widget.skipped
                                ? Icons.undo_rounded
                                : Icons.redo_rounded,
                            size: I.sm,
                          ),
                          onPressed: widget.onToggleSkip,
                          child: Text(
                            widget.skipped ? 'Atlamayı kaldır' : 'Bugün atla',
                          ),
                        ),
                      ShadContextMenuItem(
                        leading: const Icon(Icons.delete_outline, size: I.sm),
                        onPressed: widget.onDelete,
                        child: const Text('Sil'),
                      ),
                    ],
                    child: GestureDetector(
                      onTap: _preview.toggle,
                      onLongPressStart: widget.onLongPressStart,
                      onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
                      onLongPressEnd: widget.onLongPressEnd,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: style.fill,
                            borderRadius: R.radiusXs,
                            // Yan yana aynı renkli iki blok birbirine karışmasın.
                            border: Border.all(color: style.edge, width: 0.8),
                          ),
                          child: ClipRRect(
                            borderRadius: R.radiusXs,
                            child: Row(
                              // Şerit bloğun tam boyunca inmeli; stretch olmazsa
                              // içeriğin yüksekliği kadar kalıp yarım şerit gibi durur.
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 3,
                                  child: ColoredBox(color: style.stripe),
                                ),
                                Expanded(
                                  child: compact
                                      // Kısa blokta başlık kırpılıyor; tam adı yalnız
                                      // burada tooltip veriyor. Uzun blokta zaten
                                      // görünüyor, orada tooltip gürültü olurdu.
                                      ? ShadTooltip(
                                          builder: (context) => Text(title),
                                          child: body,
                                        )
                                      : body,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Alt kenardaki süre tutamacı. Dikey sürükleme bu çocukta başladığı
        // için jest arenasında bloğun uzun basmasından önce gelir.
        //
        // Şerit bloğun İÇİNDE kalır: Stack sınırının dışına taşan piksel
        // dokunuş almaz, yani "bottom: -2" gibi bir taşma tutamağı sessizce
        // küçültürdü.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 12,
          child: RawGestureDetector(
            key: ValueKey('resize-${task.id}'),
            behavior: HitTestBehavior.translucent,
            gestures: {
              _EagerVerticalDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _EagerVerticalDragRecognizer
                  >(_EagerVerticalDragRecognizer.new, (recognizer) {
                    // Not: burada cascade (`..`) kullanılamaz — ok gövdeli
                    // lambda içinde cascade geri çağırıma bağlanır.
                    recognizer.onStart = (_) => widget.onResizeStart();
                    recognizer.onUpdate = widget.onResizeUpdate;
                    recognizer.onEnd = (_) => widget.onResizeEnd();
                    recognizer.onCancel = widget.onResizeEnd;
                  }),
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Center(
                child: Container(
                  width: 20,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: style.ink.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Kaydırılabilir ızgara içindeki süre tutamağı için dikey sürükleme tanıyıcısı.
///
/// Neden özel: tutamak, dikey kaydırma yapan [SingleChildScrollView]'ın içinde
/// duruyor. İkisi de dikey sürüklemeyi tanıdığı için jest arenasında kaydırma
/// kazanıyor ve tutamak **hiç çalışmıyordu** — parmak tutamaktan aşağı
/// çekildiğinde blok yerine sayfa kayıyordu.
///
/// Çözüm: parmak tutamağa değdiği anda jesti sahiplen. Tutamak zaten 12
/// piksellik dar ve amacı belli bir hedef; oraya kasten dokunan kullanıcı
/// sayfayı kaydırmak istemiyordur.
class _EagerVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'süre tutamağı (öncelikli dikey sürükleme)';
}
