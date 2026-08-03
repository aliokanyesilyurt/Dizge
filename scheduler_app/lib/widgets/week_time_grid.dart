import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    required this.onDuplicate,
    required this.onDelete,
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

  /// Sağ tık menüsünün eylemleri.
  final void Function(Task task, DateTime day) onDuplicate;
  final void Function(Task task) onDelete;

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
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _initialOffset(),
  );

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
        grabDy: (local.dy - blockTop).clamp(
          0.0,
          _m.hourHeight * task.durationHours,
        ),
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
      velocity = (1 - (height - local.dy) / _edgeZone) * _maxAutoScrollPerTick;
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
    final target = (_scroll.offset + _autoScrollVelocity).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
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
    setState(
      () => _resize = _ResizeState(task: task, duration: task.durationHours),
    );
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    final resize = _resize;
    if (resize == null) return;
    final start = resize.task.startHour ?? 0;
    final next = snapHour(
      resize.duration + details.delta.dy / _m.hourHeight,
    ).clamp(kMinDurationHours, _m.dayEnd - start);
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
    final c = context.colors;

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
                            palette: c,
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
                      if (_todayIndex != null)
                        _nowIndicator(c, width, _todayIndex!),

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
    final diff = DateTime(
      widget.today.year,
      widget.today.month,
      widget.today.day,
    ).difference(widget.monday).inDays;
    return (diff >= 0 && diff < 7) ? diff : null;
  }

  List<Widget> _buildBlocks(double canvasWidth) {
    final columnWidth = _columnWidth(canvasWidth);
    final blocks = <Widget>[];

    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final day = _dayAt(dayIndex);
      final scheduled = widget.tasksByDay[dayIndex]
          .where((t) => t.scheduled)
          .toList();
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

        // Google Takvim'deki gibi bloklar sütun kenarlarına yapışmaz; aralarında
        // ince bir nefes payı kalır.
        const gap = 3.0;
        final left =
            dayIndex * columnWidth +
            slot.leftFraction * (columnWidth - gap) +
            gap / 2;
        final width = math.max(
          12.0,
          slot.widthFraction * (columnWidth - gap) - gap / 2,
        );
        final height = math.max(
          _m.hourHeight * kMinDurationHours,
          duration * _m.hourHeight - 2,
        );

        blocks.add(
          Positioned(
            left: left,
            top: _m.yFor(slot.start),
            width: width,
            height: height,
            child: Opacity(
              // Sürüklenen bloğun aslı soluklaşır; hayaleti parmağı takip eder.
              opacity: dragging ? 0.28 : 1,
              child: _EventBlock(
                task: task,
                day: day,
                done: task.isDoneOn(day),
                // Kısa blokta saat satırı sığmaz; başlık ve saat tek satıra iner.
                compact: height < 34,
                onEdit: () => widget.onTapTask(task, day),
                onDuplicate: () => widget.onDuplicate(task, day),
                onDelete: () => widget.onDelete(task),
                onLongPressStart: (d) => _onDragStart(task, dayIndex, d),
                onLongPressMoveUpdate: _onDragUpdate,
                onLongPressEnd: (_) => _onDragEnd(),
                onResizeStart: () => _onResizeStart(task),
                onResizeUpdate: _onResizeUpdate,
                onResizeEnd: _onResizeEnd,
              ),
            ),
          ),
        );
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
      height: math.max(30.0, drag.task.durationHours * _m.hourHeight - 1),
      child: IgnorePointer(
        child: _DragPreview(
          task: drag.task,
          label: '${Task.formatTime(drag.startHour)} – ${Task.formatTime(end)}',
        ),
      ),
    );
  }

  /// Kırmızı "şu an" çizgisi: nokta bugünün sütununda, çizgi haftanın tamamında
  /// (Google Takvim'deki davranış).
  Widget _nowIndicator(AppPalette c, double canvasWidth, int todayIndex) {
    final columnWidth = _columnWidth(canvasWidth);
    final y = _m.yFor(hourOfDay(_now));
    if (y < 0 || y > _m.totalHeight) return const SizedBox.shrink();

    return Positioned(
      top: y - 5,
      left: 0,
      right: 0,
      height: 10,
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: 4.5,
              left: 0,
              right: 0,
              child: Container(height: 1.5, color: c.nowLine),
            ),
            Positioned(
              top: 0,
              left: todayIndex * columnWidth - 1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: c.nowLine,
                  shape: BoxShape.circle,
                  // Halka, altındaki ızgara yaprağının rengiyle "kesip" noktayı
                  // çizgiden ayırır.
                  border: Border.all(color: c.surface, width: 1.5),
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
    final c = context.colors;
    final first = metrics.dayStart.ceil();
    final last = metrics.dayEnd.floor();

    return Stack(
      children: [
        for (var h = first; h <= last; h++)
          Positioned(
            // Etiket kendi çizgisinin biraz üstünde durur (Google Takvim'de
            // olduğu gibi) — böylece saat, altındaki dilimi adlandırır.
            top: metrics.yFor(h.toDouble()) - 6,
            right: 10,
            child: Text(
              // İlk ve son etiket kenara yapışıp kırpılır; Google da onları
              // gizler.
              (h >= 24 || h == 0) ? '' : '${h.toString().padLeft(2, '0')}:00',
              style: TextStyle(
                // `inkFaint` değil: 10.5px'te zemine karşı 3.2:1 kalıyordu ve
                // saat sütunu dekorasyon değil, saati oradan okuyorsun.
                // `inkDim` hâlâ ikincil ama AA'yı iki temada da geçiyor.
                color: c.inkDim,
                fontSize: 10.5,
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
    required this.palette,
    required this.todayIndex,
    required this.dropDayIndex,
  });

  final GridMetrics metrics;
  final AppPalette palette;
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
        Paint()..color = palette.gridTodayWash,
      );
    }
    if (dropDayIndex != null) {
      canvas.drawRect(
        Rect.fromLTWH(dropDayIndex! * columnWidth, 0, columnWidth, size.height),
        Paint()..color = palette.dropTarget.withValues(alpha: 0.10),
      );
    }

    final hourPaint = Paint()
      ..color = palette.gridHourLine
      ..strokeWidth = 1;
    final halfPaint = Paint()
      ..color = palette.gridHalfLine
      ..strokeWidth = 1;
    final columnPaint = Paint()
      ..color = palette.gridColumnLine
      ..strokeWidth = 1;

    // Yatay: tam saatler belirgin, yarım saatler soluk. Yarım saat çizgileri
    // yalnızca yeterince yer varken çizilir; sıkışıkken görsel gürültü olur.
    final drawHalf = metrics.hourHeight >= 64;
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
      old.palette != palette ||
      old.todayIndex != todayIndex ||
      old.dropDayIndex != dropDayIndex;
}

// --- Etkinlik bloğu ----------------------------------------------------------

class _EventBlock extends StatefulWidget {
  const _EventBlock({
    required this.task,
    required this.day,
    required this.done,
    required this.compact,
    required this.onEdit,
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

  /// Blok kısaysa başlık ve saat tek satırda birleşir.
  final bool compact;

  /// Tam düzenleyiciyi açar. Bloğa tıklamak artık doğrudan buraya gitmiyor —
  /// önce hafif bir önizleme açılıyor, "Düzenle" oradan çağırıyor.
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  final void Function(LongPressStartDetails) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final void Function(LongPressEndDetails) onLongPressEnd;
  final VoidCallback onResizeStart;
  final void Function(DragUpdateDetails) onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  State<_EventBlock> createState() => _EventBlockState();
}

class _EventBlockState extends State<_EventBlock> {
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

  /// Ekran okuyucunun duyduğu cümle: "Toplantı, Salı 14:00 – 15:30, tamamlandı".
  ///
  /// Blok içindeki parçalar `excludeSemantics` ile susturuluyor; yoksa okuyucu
  /// başlığı, saati ve ikonları ayrı ayrı, bağlamsız okurdu.
  String get _semanticLabel {
    final task = widget.task;
    final parts = <String>[
      task.title.isEmpty ? 'Başlıksız' : task.title,
      '${_weekdayNames[widget.day.weekday - 1]} ${task.timeString}',
      if (task.isRoutine) 'rutin',
      if (widget.done) 'tamamlandı',
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
      fontSize: 11.5,
      height: 1.2,
      fontWeight: FontWeight.w600,
      decoration: done ? TextDecoration.lineThrough : null,
      decorationColor: style.ink.withValues(alpha: 0.7),
    );
    final timeStyle = TextStyle(
      color: style.ink.withValues(alpha: 0.82),
      fontSize: 10.5,
      height: 1.2,
      fontWeight: FontWeight.w500,
    );

    // Tamamlandı yalnız renge/çizgiye dayanmaz: ✓ ikonu da var (WCAG 1.4.1).
    final marks = <Widget>[
      if (done) Icon(Icons.check, size: compact ? 10 : 11, color: style.ink),
      if (task.isRoutine)
        Icon(
          Icons.repeat,
          size: compact ? 9.5 : 10,
          color: style.ink.withValues(alpha: 0.85),
        ),
    ];

    final body = Container(
      padding: EdgeInsets.fromLTRB(5, compact ? 1 : 3, 5, 2),
      child: compact
          // Kısa blok: "Başlık · 09:00" tek satır.
          ? Row(
              children: [
                for (final mark in marks) ...[mark, const SizedBox(width: 3)],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(task.startString, maxLines: 1, style: timeStyle),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final mark in marks) ...[
                      mark,
                      const SizedBox(width: 3),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
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
          child: Semantics(
            button: true,
            label: _semanticLabel,
            excludeSemantics: true,
            onTap: widget.onEdit,
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
                  popover: (context) => _Preview(
                    task: task,
                    day: widget.day,
                    done: done,
                    onEdit: () {
                      _preview.hide();
                      widget.onEdit();
                    },
                  ),
                  // Sağ tık menüsü: içerideki uzun basma sürükleme başlatıyor ve
                  // `longPressEnabled` açık olsaydı taşımaya çalışan her el hareketi
                  // menüyü açardı. Menü yalnız sağ tıkla gelir.
                  child: ShadContextMenuRegion(
                    longPressEnabled: false,
                    items: [
                      ShadContextMenuItem(
                        leading: const Icon(Icons.edit_outlined, size: 16),
                        onPressed: widget.onEdit,
                        child: const Text('Düzenle'),
                      ),
                      ShadContextMenuItem(
                        leading: const Icon(Icons.copy_outlined, size: 16),
                        onPressed: widget.onDuplicate,
                        child: const Text('Kopyala'),
                      ),
                      ShadContextMenuItem(
                        leading: const Icon(Icons.delete_outline, size: 16),
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

/// Bloğa tıklayınca açılan hafif önizleme.
///
/// Neden doğrudan düzenleyici değil: bir işin ne olduğuna bakmak, onu
/// değiştirmekten çok daha sık yapılan bir şey. Tam sheet ekranı kaplayıp
/// takvimi gizliyordu; burada hafta arkada durmaya devam ediyor. Düzenlemek
/// isteyen tek tıkla oraya geçiyor.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.task,
    required this.day,
    required this.done,
    required this.onEdit,
  });

  final Task task;
  final DateTime day;
  final bool done;
  final VoidCallback onEdit;

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
      constraints: const BoxConstraints(maxWidth: 260),
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
                margin: const EdgeInsets.only(top: 2, right: 8),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (done)
                Icon(Icons.check_circle_outline, size: 16, color: c.inkDim),
            ],
          ),
          const SizedBox(height: 8),
          for (final (icon, text) in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 13, color: c.inkFaint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.inkDim,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onEdit,
              child: const Text('Düzenle'),
            ),
          ),
        ],
      ),
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
    final c = context.colors;
    final style = c.event(task.color);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: R.radiusXs,
        border: Border.all(color: c.surface, width: 1.5),
        boxShadow: c.shadowLg,
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
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: style.ink,
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
                            color: style.ink.withValues(alpha: 0.9),
                            fontSize: 11.5,
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
