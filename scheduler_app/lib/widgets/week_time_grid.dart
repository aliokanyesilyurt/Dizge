import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/time_grid.dart';
import '../models/task.dart';
import '../theme.dart';

/// Google Takvim tarzı haftalık zaman ızgarası.
///
/// Sorumluluğu **yalnızca çizim ve etkileşim**: veriyi dışarıdan alır,
/// değişiklikleri geri çağırımlarla bildirir. Store'u tanımaz — böylece tek
/// gün görünümünde ya da testlerde sahte veriyle de kullanılabilir.
///
/// Etkileşimler:
///   * boş alana **dokun** → o gün/saat için hızlı ekleme,
///   * bloğa **dokun** → düzenle,
///   * bloğu **basılı tut + sürükle** → başka güne/saate taşı (15 dk'ya oturur),
///   * bloğun alt kenarından **çek** → süreyi değiştir,
///   * dikey **kaydır** → gün boyunca gez.
class WeekTimeGrid extends StatefulWidget {
  const WeekTimeGrid({
    super.key,
    required this.monday,
    required this.tasksByDay,
    required this.metrics,
    required this.today,
    required this.onTapTask,
    required this.onTapEmpty,
    required this.onMove,
    required this.onResize,
    this.scrollOffset,
    this.initialScrollHour,
  }) : assert(tasksByDay.length == 7, 'Haftalık ızgara tam 7 gün bekler');

  /// Gösterilen haftanın pazartesisi (saat kırpılmış).
  final DateTime monday;

  /// Pazartesiden pazara, her günün görevleri.
  final List<List<Task>> tasksByDay;

  final GridMetrics metrics;

  /// "Bugün" vurgusu için referans gün. Test edilebilirlik adına dışarıdan
  /// verilir (DateTime.now() widget içinde çağrılmaz).
  final DateTime today;

  final void Function(Task task, DateTime day) onTapTask;
  final void Function(DateTime day, double hour) onTapEmpty;
  final void Function(Task task, DateTime toDay, double newStartHour) onMove;
  final void Function(Task task, double newDurationHours) onResize;

  /// Haftalar arasında geçerken dikey kaydırma konumunu koruyan paylaşımlı
  /// değer. Her sayfa kendi controller'ını buradan besler.
  final ValueNotifier<double>? scrollOffset;

  /// İlk açılışta ekranın ortalayacağı saat (genelde "şimdi"den biraz önce).
  final double? initialScrollHour;

  @override
  State<WeekTimeGrid> createState() => _WeekTimeGridState();
}

/// Sürükleme sırasında taşınan bloğun geçici durumu.
class _DragState {
  _DragState({
    required this.task,
    required this.sourceDayIndex,
    required this.grabDy,
    required this.dayIndex,
    required this.startHour,
  });

  final Task task;
  final int sourceDayIndex;

  /// Parmağın blok içindeki dikey konumu — blok parmağın altından kaymasın.
  final double grabDy;

  int dayIndex;
  double startHour;
}

/// Alt kenardan süre değiştirme durumu.
class _ResizeState {
  _ResizeState({required this.task, required this.duration});

  final Task task;
  double duration;
}

class _WeekTimeGridState extends State<WeekTimeGrid> {
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _initialOffset());

  final GlobalKey _canvasKey = GlobalKey();

  _DragState? _drag;
  _ResizeState? _resize;

  /// "Şu an" çizgisini dakikada bir tazeler.
  Timer? _clock;
  late DateTime _now = DateTime.now();

  /// Sürükleme ekran kenarına yaklaşınca ızgarayı kendiliğinden kaydırır.
  Timer? _autoScroll;
  double _autoScrollVelocity = 0;

  static const double _edgeZone = 64.0;
  static const double _maxAutoScrollPerTick = 14.0;

  double _initialOffset() {
    final hour = widget.initialScrollHour;
    if (hour == null) return widget.scrollOffset?.value ?? 0;
    // İstenen saat ekranın üst üçte birine gelsin.
    return math.max(0, widget.metrics.yFor(hour) - 120);
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _scroll.addListener(_publishScrollOffset);
  }

  void _publishScrollOffset() {
    final notifier = widget.scrollOffset;
    if (notifier != null && _scroll.hasClients) {
      notifier.value = _scroll.offset;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _autoScroll?.cancel();
    _scroll.removeListener(_publishScrollOffset);
    _scroll.dispose();
    super.dispose();
  }

  GridMetrics get _m => widget.metrics;

  DateTime _dayAt(int index) => widget.monday.add(Duration(days: index));

  // --- Koordinat dönüşümleri -------------------------------------------------

  /// Küresel dokunuş noktasını ızgara tuvalinin yerel koordinatına çevirir.
  Offset? _toCanvas(Offset globalPosition) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(globalPosition);
  }

  double _columnWidth(double canvasWidth) => canvasWidth / 7;

  int _dayIndexAt(double dx, double canvasWidth) =>
      (dx / _columnWidth(canvasWidth)).floor().clamp(0, 6);

  // --- Sürükleme -------------------------------------------------------------

  void _onDragStart(Task task, int dayIndex, LongPressStartDetails details) {
    final local = _toCanvas(details.globalPosition);
    if (local == null) return;

    final start = task.startHour ?? 0;
    final blockTop = _m.yFor(start);
    HapticFeedback.mediumImpact();

    setState(() {
      _drag = _DragState(
        task: task,
        sourceDayIndex: dayIndex,
        grabDy: (local.dy - blockTop).clamp(0.0, _m.hourHeight * task.durationHours),
        dayIndex: dayIndex,
        startHour: start,
      );
    });
  }

  void _onDragUpdate(LongPressMoveUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;

    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(details.globalPosition);

    final nextDay = _dayIndexAt(local.dx, box.size.width);
    final rawHour = _m.hourAt(local.dy - drag.grabDy);
    final nextHour = clampStartWithin(
      snapHour(rawHour),
      drag.task.durationHours,
      dayStart: _m.dayStart,
      dayEnd: _m.dayEnd,
    );

    // Yalnızca gerçekten değiştiyse yeniden çiz + dokunsal geri bildirim ver.
    if (nextDay != drag.dayIndex || nextHour != drag.startHour) {
      HapticFeedback.selectionClick();
      setState(() {
        drag.dayIndex = nextDay;
        drag.startHour = nextHour;
      });
    }

    _updateAutoScroll(details.globalPosition);
  }

  void _onDragEnd() {
    _stopAutoScroll();
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);

    final movedDay = drag.dayIndex != drag.sourceDayIndex;
    final movedTime = drag.startHour != (drag.task.startHour ?? 0);
    if (!movedDay && !movedTime) return; // yerinde bırakıldı

    widget.onMove(drag.task, _dayAt(drag.dayIndex), drag.startHour);
  }

  // --- Kenarda otomatik kaydırma ---------------------------------------------

  void _updateAutoScroll(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPosition);
    final height = box.size.height;

    double velocity = 0;
    if (local.dy < _edgeZone) {
      velocity = -(1 - local.dy / _edgeZone) * _maxAutoScrollPerTick;
    } else if (local.dy > height - _edgeZone) {
      velocity =
          (1 - (height - local.dy) / _edgeZone) * _maxAutoScrollPerTick;
    }

    _autoScrollVelocity = velocity;
    if (velocity == 0) {
      _stopAutoScroll();
    } else {
      _autoScroll ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _tickAutoScroll(),
      );
    }
  }

  void _tickAutoScroll() {
    if (!_scroll.hasClients || _drag == null) return _stopAutoScroll();
    final target = (_scroll.offset + _autoScrollVelocity)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (target == _scroll.offset) return;
    _scroll.jumpTo(target);
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _autoScrollVelocity = 0;
  }

  // --- Süre değiştirme -------------------------------------------------------

  void _onResizeStart(Task task) {
    HapticFeedback.selectionClick();
    setState(() => _resize = _ResizeState(task: task, duration: task.durationHours));
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    final resize = _resize;
    if (resize == null) return;
    final start = resize.task.startHour ?? 0;
    final next = snapHour(resize.duration + details.delta.dy / _m.hourHeight)
        .clamp(kMinDurationHours, _m.dayEnd - start);
    if (next != resize.duration) {
      setState(() => resize.duration = next);
    }
  }

  void _onResizeEnd() {
    final resize = _resize;
    if (resize == null) return;
    setState(() => _resize = null);
    if (resize.duration != resize.task.durationHours) {
      widget.onResize(resize.task, resize.duration);
    }
  }

  // --- Boş alana dokunma -----------------------------------------------------

  void _onEmptyTap(Offset localPosition, double canvasWidth) {
    final dayIndex = _dayIndexAt(localPosition.dx, canvasWidth);
    // Boş slot dokunuşu tam/yarım saate oturur; 15 dakikalık hassasiyet burada
    // fazla kırılgan olurdu (kullanıcı 09:00 isterken 09:15 açılmasın).
    final hour = snapHour(_m.hourAt(localPosition.dy), minutes: 30);
    widget.onTapEmpty(_dayAt(dayIndex), hour);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      // Sürükleme sırasında ızgarayı yalnızca otomatik kaydırma hareket
      // ettirsin; parmak zaten bloğu taşıyor.
      physics: _drag != null
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      child: SizedBox(
        height: _m.totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: kTimeGutterWidth,
              child: _HourGutter(metrics: _m),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return Stack(
                    key: _canvasKey,
                    children: [
                      // 1) Zemin: saat çizgileri, gün ayraçları, bugün tonu.
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GridPainter(
                            metrics: _m,
                            todayIndex: _todayIndex,
                            dropDayIndex: _drag?.dayIndex,
                          ),
                        ),
                      ),

                      // 2) Boş alan dokunuşları (bloklardan ÖNCE, altta kalsın).
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (d) => _onEmptyTap(d.localPosition, width),
                        ),
                      ),

                      // 3) Etkinlik blokları.
                      ..._buildBlocks(width),

                      // 4) "Şu an" çizgisi.
                      if (_todayIndex != null) _nowIndicator(width, _todayIndex!),

                      // 5) Sürüklenen bloğun hayaleti (en üstte).
                      if (_drag != null) _dragGhost(width, _drag!),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bugünün hafta içindeki sırası (0-6); bu haftada değilse null.
  int? get _todayIndex {
    final diff = DateTime(widget.today.year, widget.today.month, widget.today.day)
        .difference(widget.monday)
        .inDays;
    return (diff >= 0 && diff < 7) ? diff : null;
  }

  List<Widget> _buildBlocks(double canvasWidth) {
    final columnWidth = _columnWidth(canvasWidth);
    final blocks = <Widget>[];

    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final day = _dayAt(dayIndex);
      final scheduled =
          widget.tasksByDay[dayIndex].where((t) => t.scheduled).toList();
      if (scheduled.isEmpty) continue;

      // Çakışanları sütunlara paylaştır (saf mantık, core/time_grid.dart).
      final slots = layoutEvents<Task>(
        scheduled,
        startOf: (t) => t.startHour!,
        endOf: (t) => t.startHour! + t.durationHours,
      );

      for (final slot in slots) {
        final task = slot.item;
        final dragging = _drag?.task.id == task.id;

        // Süre değiştiriliyorsa canlı önizleme göster.
        final duration = (_resize?.task.id == task.id)
            ? _resize!.duration
            : task.durationHours;

        const gap = 2.0;
        final left = dayIndex * columnWidth +
            slot.leftFraction * (columnWidth - gap) +
            gap / 2;
        final width =
            math.max(12.0, slot.widthFraction * (columnWidth - gap) - gap / 2);

        blocks.add(Positioned(
          left: left,
          top: _m.yFor(slot.start),
          width: width,
          height: math.max(_m.hourHeight * kMinDurationHours,
              duration * _m.hourHeight - 1),
          child: Opacity(
            // Sürüklenen bloğun aslı soluklaşır; hayaleti parmağı takip eder.
            opacity: dragging ? 0.28 : 1,
            child: _EventBlock(
              task: task,
              day: day,
              done: task.isDoneOn(day),
              compact: _m.hourHeight * duration < 42,
              onTap: () => widget.onTapTask(task, day),
              onLongPressStart: (d) => _onDragStart(task, dayIndex, d),
              onLongPressMoveUpdate: _onDragUpdate,
              onLongPressEnd: (_) => _onDragEnd(),
              onResizeStart: () => _onResizeStart(task),
              onResizeUpdate: _onResizeUpdate,
              onResizeEnd: _onResizeEnd,
            ),
          ),
        ));
      }
    }
    return blocks;
  }

  Widget _dragGhost(double canvasWidth, _DragState drag) {
    final columnWidth = _columnWidth(canvasWidth);
    final end = drag.startHour + drag.task.durationHours;
    return Positioned(
      left: drag.dayIndex * columnWidth + 2,
      top: _m.yFor(drag.startHour),
      width: columnWidth - 4,
      height: math.max(28.0, drag.task.durationHours * _m.hourHeight - 1),
      child: IgnorePointer(
        child: _DragPreview(
          task: drag.task,
          label: '${Task.formatTime(drag.startHour)} – ${Task.formatTime(end)}',
        ),
      ),
    );
  }

  Widget _nowIndicator(double canvasWidth, int todayIndex) {
    final columnWidth = _columnWidth(canvasWidth);
    final y = _m.yFor(hourOfDay(_now));
    if (y < 0 || y > _m.totalHeight) return const SizedBox.shrink();

    return Positioned(
      top: y - 4,
      left: 0,
      right: 0,
      height: 8,
      child: IgnorePointer(
        child: Row(
          children: [
            SizedBox(width: todayIndex * columnWidth),
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 0.5),
              decoration: const BoxDecoration(
                color: AppColors.nowLine,
                shape: BoxShape.circle,
              ),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 3.5),
                child: Divider(
                  color: AppColors.nowLine,
                  thickness: 1.4,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Saat sütunu -------------------------------------------------------------

class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.metrics});

  final GridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final first = metrics.dayStart.ceil();
    final last = metrics.dayEnd.floor();

    return Stack(
      children: [
        for (var h = first; h <= last; h++)
          Positioned(
            top: metrics.yFor(h.toDouble()) - 7,
            right: 8,
            child: Text(
              // 24:00 yazmak yerine sonuncuyu gizle (Google Takvim de böyle).
              h >= 24 ? '' : '${h.toString().padLeft(2, '0')}:00',
              style: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }
}

// --- Izgara zemini -----------------------------------------------------------

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.metrics,
    required this.todayIndex,
    required this.dropDayIndex,
  });

  final GridMetrics metrics;
  final int? todayIndex;

  /// Sürükleme sırasında hedeflenen gün — sütunu hafifçe aydınlanır.
  final int? dropDayIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final columnWidth = size.width / 7;

    // Bugünün ve bırakma hedefinin sütun zemini.
    if (todayIndex != null) {
      canvas.drawRect(
        Rect.fromLTWH(todayIndex! * columnWidth, 0, columnWidth, size.height),
        Paint()..color = AppColors.gridTodayWash,
      );
    }
    if (dropDayIndex != null) {
      canvas.drawRect(
        Rect.fromLTWH(dropDayIndex! * columnWidth, 0, columnWidth, size.height),
        Paint()..color = AppColors.dropTarget.withValues(alpha: 0.10),
      );
    }

    final hourPaint = Paint()
      ..color = AppColors.gridHourLine
      ..strokeWidth = 1;
    final halfPaint = Paint()
      ..color = AppColors.gridHalfLine
      ..strokeWidth = 1;
    final columnPaint = Paint()
      ..color = AppColors.gridColumnLine
      ..strokeWidth = 1;

    // Yatay: tam saatler belirgin, yarım saatler soluk. Yarım saat çizgileri
    // yalnızca yeterince yer varken çizilir; sıkışıkken görsel gürültü olur.
    final drawHalf = metrics.hourHeight >= 48;
    for (var h = metrics.dayStart; h <= metrics.dayEnd; h += 1) {
      final y = metrics.yFor(h);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
      if (drawHalf && h + 0.5 < metrics.dayEnd) {
        final yh = metrics.yFor(h + 0.5);
        canvas.drawLine(Offset(0, yh), Offset(size.width, yh), halfPaint);
      }
    }

    // Dikey: gün ayraçları.
    for (var i = 1; i < 7; i++) {
      final x = i * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), columnPaint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.metrics.hourHeight != metrics.hourHeight ||
      old.todayIndex != todayIndex ||
      old.dropDayIndex != dropDayIndex;
}

// --- Etkinlik bloğu ----------------------------------------------------------

class _EventBlock extends StatelessWidget {
  const _EventBlock({
    required this.task,
    required this.day,
    required this.done,
    required this.compact,
    required this.onTap,
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

  /// Blok kısaysa yalnızca başlık gösterilir (saat satırı sığmaz).
  final bool compact;

  final VoidCallback onTap;
  final void Function(LongPressStartDetails) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final void Function(LongPressEndDetails) onLongPressEnd;
  final VoidCallback onResizeStart;
  final void Function(DragUpdateDetails) onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final style = tagStyleFor(task.color);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onTap,
            onLongPressStart: onLongPressStart,
            onLongPressMoveUpdate: onLongPressMoveUpdate,
            onLongPressEnd: onLongPressEnd,
            child: Container(
              padding: EdgeInsets.fromLTRB(6, compact ? 2 : 4, 4, 2),
              decoration: BoxDecoration(
                color: done
                    ? style.fill.withValues(alpha: 0.5)
                    : style.fill,
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(color: task.color, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (task.isRoutine) ...[
                        Icon(Icons.repeat,
                            size: 9.5,
                            color: style.text.withValues(alpha: 0.8)),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          task.title.isEmpty ? 'Başlıksız' : task.title,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.text,
                            fontSize: 11.5,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            decorationColor: style.text.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!compact)
                    Text(
                      task.startString,
                      maxLines: 1,
                      style: TextStyle(
                        color: style.text.withValues(alpha: 0.72),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
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
                      _EagerVerticalDragRecognizer>(
                _EagerVerticalDragRecognizer.new,
                (recognizer) {
                  // Not: burada cascade (`..`) kullanılamaz — ok gövdeli
                  // lambda içinde cascade geri çağırıma bağlanır.
                  recognizer.onStart = (_) => onResizeStart();
                  recognizer.onUpdate = onResizeUpdate;
                  recognizer.onEnd = (_) => onResizeEnd();
                  recognizer.onCancel = onResizeEnd;
                },
              ),
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Center(
                child: Container(
                  width: 22,
                  height: 3,
                  decoration: BoxDecoration(
                    color: style.text.withValues(alpha: 0.35),
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

/// Sürüklenirken parmağı takip eden yükseltilmiş kopya + canlı saat rozeti.
class _DragPreview extends StatelessWidget {
  const _DragPreview({required this.task, required this.label});

  final Task task;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = tagStyleFor(task.color, selected: true);

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(style.fill, AppColors.surfaceAlt),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: task.color, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: task.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 1),
          Flexible(
            child: Text(
              task.title.isEmpty ? 'Başlıksız' : task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.text,
                fontSize: 11.5,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
