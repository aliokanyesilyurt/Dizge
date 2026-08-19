import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/time_grid.dart';
import '../models/task.dart';
import '../theme.dart';
import 'week_grid/block_preview.dart';
import 'week_grid/event_block.dart';
import 'week_grid/grid_chrome.dart';
import 'week_grid/interaction.dart';

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
    this.energyLimit,
    this.isOverPool,
    this.onDropToPool,
    this.onToggleSkip,
    this.onPullFromPool,
    this.poolHover,
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

  /// Kullanıcının o günkü enerjisi; bunun üstünde efor isteyen bloklar
  /// **soluklaşır, gizlenmez**. Gizlemek işi unutturur; soluklaştırmak
  /// "bugün olmasa da olur" der. null => filtre kapalı.
  final Energy? energyLimit;

  /// Verilen küresel nokta havuz panelinin üstünde mi?
  ///
  /// Izgara paneli tanımıyor — yalnız "burası benim dışım mı" diye soruyor.
  /// Panelin nerede durduğu, ne kadar geniş olduğu, hatta var olup olmadığı
  /// ekranın bilgisi.
  final bool Function(Offset globalPosition)? isOverPool;

  /// Blok havuzun üstüne bırakıldı.
  final void Function(Task task)? onDropToPool;

  /// Rutinin verilen günü atlanacak / atlaması kaldırılacak. Rutinler havuza
  /// giremediği için (K2) bloğun "kenara alma" karşılığı bu.
  final void Function(Task task, DateTime day)? onToggleSkip;

  /// Havuzdan sürüklenen iş ızgaraya bırakıldı.
  final void Function(Task task, DateTime day, double hour)? onPullFromPool;

  /// Sürüklenen blok havuzun üstündeyken true olur; panel bunu dinleyip
  /// kendini vurguluyor. Geri çağırım yerine dinlenebilir bir değer, çünkü
  /// aradaki ekranı her piksel hareketinde yeniden çizmek gereksiz.
  final ValueNotifier<bool>? poolHover;

  @override
  State<WeekTimeGrid> createState() => _WeekTimeGridState();
}

class _WeekTimeGridState extends State<WeekTimeGrid> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _initialOffset(),
  );

  final GlobalKey _canvasKey = GlobalKey();

  DragState? _drag;
  ResizeState? _resize;

  /// Havuzdan sürüklenen iş şu an hangi gün sütununun üstünde (yoksa null).
  int? _poolDropDay;

  /// "Şu an" çizgisini dakikada bir tazeler.
  Timer? _clock;
  late DateTime _now = DateTime.now();

  /// Sürükleme ekran kenarına yaklaşınca ızgarayı kendiliğinden kaydırır.
  Timer? _autoScroll;
  double _autoScrollVelocity = 0;

  static const double _edgeZone = 64.0;

  /// Enerji filtresinin elediği bloğun saydamlığı. Okunmaya devam edecek kadar
  /// koyu, "bugün bu değil" diyecek kadar geride.
  static const double _dimmedOpacity = 0.4;
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
      _drag = DragState(
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

    drag.lastGlobal = details.globalPosition;

    // Havuzun üstündeyken blok bir güne/saate oturmaz: orada saat yok.
    final overPool = widget.isOverPool?.call(details.globalPosition) ?? false;
    if (overPool != drag.overPool) {
      HapticFeedback.selectionClick();
      setState(() => drag.overPool = overPool);
      widget.poolHover?.value = overPool;
    }
    if (overPool) {
      _updateAutoScroll(details.globalPosition);
      return;
    }

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
    widget.poolHover?.value = false;

    // Havuzun üstünde bırakıldı: gün/saat hesabı hiç yapılmıyor, iş takvimden
    // çekiliyor. Rutinler bu yola giremez (bkz. plan K2) — blok sürüklenebilir
    // ama havuz onu kabul etmez, yerinde kalır.
    if (drag.overPool) {
      if (!drag.task.isRoutine) widget.onDropToPool?.call(drag.task);
      return;
    }

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
      () => _resize = ResizeState(task: task, duration: task.durationHours),
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
              child: HourGutter(metrics: _m),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return DragTarget<Task>(
                    // Yalnız havuzdan gelen iş kabul ediliyor. Izgaranın kendi
                    // blokları ayrı bir jest sistemiyle taşınıyor; ikisi
                    // karışırsa aynı hareket iki kez işlenir.
                    onWillAcceptWithDetails: (details) =>
                        widget.onPullFromPool != null && details.data.inPool,
                    onMove: (details) => _onPoolDragOver(details.offset, width),
                    onLeave: (_) => _clearPoolDrop(),
                    onAcceptWithDetails: (details) =>
                        _onPoolDrop(details.data, details.offset, width),
                    builder: (context, _, _) => _canvas(c, width),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Havuzdan sürüklenen iş ızgaranın üstünde gezerken hedef sütunu vurgular.
  void _onPoolDragOver(Offset globalPosition, double width) {
    final local = _toCanvas(globalPosition);
    if (local == null) return;
    final day = _dayIndexAt(local.dx, width);
    if (day != _poolDropDay) setState(() => _poolDropDay = day);
  }

  void _clearPoolDrop() {
    if (_poolDropDay != null) setState(() => _poolDropDay = null);
  }

  void _onPoolDrop(Task task, Offset globalPosition, double width) {
    _clearPoolDrop();
    final local = _toCanvas(globalPosition);
    if (local == null) return;

    final day = _dayAt(_dayIndexAt(local.dx, width));
    // Boş alana dokunmayla aynı hassasiyet: kullanıcı 09:00 isterken 09:15
    // açılmasın.
    final hour = clampStartWithin(
      snapHour(_m.hourAt(local.dy), minutes: 30),
      task.durationHours,
      dayStart: _m.dayStart,
      dayEnd: _m.dayEnd,
    );
    widget.onPullFromPool?.call(task, day, hour);
  }

  /// Izgaranın kendisi: zemin, bloklar, şimdi çizgisi.
  Widget _canvas(AppPalette c, double width) => Stack(
    key: _canvasKey,
    children: [
      // 1) Zemin: saat çizgileri, gün ayraçları, bugün tonu.
      Positioned.fill(
        child: CustomPaint(
          painter: GridPainter(
            metrics: _m,
            palette: c,
            todayIndex: _todayIndex,
            // Vurgulanan sütun ya taşınan bloğun ya da havuzdan gelen işin
            // hedefi; ikisi aynı anda olamaz.
            dropDayIndex: _drag?.dayIndex ?? _poolDropDay,
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

      // 3) Saat penceresi şeritleri (bloklardan ÖNCE, altta kalsın).
      ..._buildWindowBands(width),

      // 4) Etkinlik blokları.
      ..._buildBlocks(width),

      // 5) "Şu an" çizgisi.
      if (_todayIndex != null) _nowIndicator(c, width, _todayIndex!),

      // 6) Sürüklenen bloğun hayaleti (en üstte).
      if (_drag != null && !_drag!.overPool) _dragGhost(width, _drag!),
    ],
  );

  /// Bugünün hafta içindeki sırası (0-6); bu haftada değilse null.
  int? get _todayIndex {
    final diff = DateTime(
      widget.today.year,
      widget.today.month,
      widget.today.day,
    ).difference(widget.monday).inDays;
    return (diff >= 0 && diff < 7) ? diff : null;
  }

  /// Saat penceresi olan işlerin arkasındaki soluk şerit.
  ///
  /// Şerit bloğun **arkasında** duruyor ve dokunuş almıyor: o bir kısıtın
  /// resmi, tıklanacak bir nesne değil. Blok şeridin içinde serbestçe kayar;
  /// pencereyi görünür kılmak, işi neden oraya taşıyamadığını ekranda
  /// söylemek demek (plan §Zb).
  List<Widget> _buildWindowBands(double canvasWidth) {
    final columnWidth = _columnWidth(canvasWidth);
    final bands = <Widget>[];

    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      for (final task in widget.tasksByDay[dayIndex]) {
        final start = task.windowStart;
        final end = task.windowEnd;
        if (start == null || end == null) continue;

        final top = _m.yFor(start);
        bands.add(
          Positioned(
            // Kimlik testin tutamağı: ızgarada başka süslenmiş kutular da
            // var, şeridi onlardan ayıran şey bu.
            //
            // Gün de anahtarda: pencereli bir **rutin** haftanın birkaç
            // gününde aynı `Task` nesnesiyle görünüyor ve bütün şeritler tek
            // bir Stack'e giriyor. Yalnız `task.id` yazsaydık Flutter aynı
            // anahtarı iki kez görüp ağacı düşürürdü.
            key: ValueKey('window-band-${task.id}@$dayIndex'),
            left: dayIndex * columnWidth + 2,
            top: top,
            width: math.max(0.0, columnWidth - 4),
            height: math.max(0.0, _m.yFor(end) - top),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: task.color.withValues(alpha: 0.10),
                  borderRadius: R.radiusXs,
                  border: Border.all(color: task.color.withValues(alpha: 0.28)),
                ),
              ),
            ),
          ),
        );
      }
    }
    return bands;
  }

  List<Widget> _buildBlocks(double canvasWidth) {
    final columnWidth = _columnWidth(canvasWidth);
    final blocks = <Widget>[];

    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final day = _dayAt(dayIndex);
      // Yerleşim **işler** değil **tekrarlar** üzerinden: gün içinde birkaç
      // kez olan bir iş (Z6) o gün birden çok blok çiziyor ve her biri
      // çakışma paylaşımına kendi başına giriyor. Tek seferlik işte liste tek
      // öğeli olduğu için davranış değişmiyor.
      final occurrences = <(Task, double)>[];
      for (final t in widget.tasksByDay[dayIndex]) {
        if (!t.scheduled) continue;
        for (final hour in t.occurrenceHours) {
          occurrences.add((t, hour));
        }
      }
      if (occurrences.isEmpty) continue;

      // Çakışanları sütunlara paylaştır (saf mantık, core/time_grid.dart).
      final slots = layoutEvents<(Task, double)>(
        occurrences,
        startOf: (o) => o.$2,
        endOf: (o) => o.$2 + o.$1.durationHours,
      );

      for (final slot in slots) {
        final task = slot.item.$1;
        final hour = slot.item.$2;

        // Aynı işin birden çok bloğu varsa sürükleme ve süre çekme kapalı.
        // Üç dozdan birini sürüklemek modelde tanımsız: onMove tek bir
        // `startHour` yazıyor, yani hareket sessizce **hepsini** taşırdı.
        // Saatler düzenleyiciden değişiyor; blok yine açılıyor, işaretleniyor,
        // kopyalanıyor, siliniyor.
        final many = task.hasManyTimes;
        final dragging = _drag?.task.id == task.id;
        final dimmed = task.exceedsEnergy(widget.energyLimit);
        final skipped = task.isSkippedOn(day);

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
              // Enerji filtresi de aynı kanaldan geçiyor: sürüklenen blok zaten
              // en solgun hâlinde olmalı, iki solgunluk çarpışmamalı.
              //
              // Atlanan rutin de aynı solgunluğa iniyor — "bugün bu yok"
              // demenin en sessiz yolu. Silmiyoruz: yarın yine gelecek.
              opacity: dragging
                  ? 0.28
                  : ((dimmed || skipped) ? _dimmedOpacity : 1),
              child: EventBlock(
                task: task,
                day: day,
                // Çoklu saatte tik o **tekrarın** kendisi: sabah dozu
                // işaretliyken akşamki boş görünmeli.
                done: many ? task.isSlotDone(day, hour) : task.isDoneOn(day),
                skipped: skipped,
                dimmed: dimmed,
                // Kısa blokta saat satırı sığmaz; başlık ve saat tek satıra iner.
                compact: height < 34,
                onMoveToPool: (widget.onDropToPool == null || task.isRoutine)
                    ? null
                    : () => widget.onDropToPool!(task),
                // Aynanın öteki yüzü: "Kenara al" rutinde hiç yok, "Bugün
                // atla" da tek günlük işte hiç yok. Her blokta o işin
                // yapabileceği tek "bugün bunu geç" eylemi duruyor.
                onToggleSkip: (widget.onToggleSkip == null || !task.isRoutine)
                    ? null
                    : () => widget.onToggleSkip!(task, day),
                onEdit: () => widget.onTapTask(task, day),
                onDuplicate: () => widget.onDuplicate(task, day),
                onDelete: () => widget.onDelete(task),
                onLongPressStart: many
                    ? (_) {}
                    : (d) => _onDragStart(task, dayIndex, d),
                onLongPressMoveUpdate: _onDragUpdate,
                onLongPressEnd: (_) => _onDragEnd(),
                onResizeStart: many ? () {} : () => _onResizeStart(task),
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

  Widget _dragGhost(double canvasWidth, DragState drag) {
    final columnWidth = _columnWidth(canvasWidth);
    final end = drag.startHour + drag.task.durationHours;
    return Positioned(
      left: drag.dayIndex * columnWidth + 2,
      top: _m.yFor(drag.startHour),
      width: columnWidth - 4,
      height: math.max(30.0, drag.task.durationHours * _m.hourHeight - 1),
      child: IgnorePointer(
        child: DragPreview(
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
              child: Container(
                height: 1.5,
                // Parıltı ince çizgiyi siyah zeminde neon bir iz hâline
                // getiriyor; koyu temada "şu an" bir bakışta bulunuyor.
                decoration: BoxDecoration(
                  color: c.nowLine,
                  boxShadow: c.glowOf(c.nowLine),
                ),
              ),
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
                  boxShadow: c.glowOf(c.nowLine),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
