import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/day_rescue.dart';
import '../core/energy_filter_controller.dart';
import '../core/grid_density_controller.dart';
import '../core/pool_panel_controller.dart';
import '../core/telemetry.dart';
import '../core/time_grid.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/week_time_grid.dart';
import 'week/daily_habit_strip.dart';
import 'week/pool_panel.dart';
import 'week/week_header_bar.dart';

/// Haftalık görünüm — uygulamanın ana ekranı.
///
/// Google Takvim'in hafta modelini izler: dikeyde saatler, yatayda günler,
/// işler zaman blokları. Farkı, kromun tamamen sakinleştirilmiş olması.
///
/// Yapı — üstten alta:
///   1. Başlık: tarih aralığı, hafta gezinme, yoğunluk düğmesi
///   2. Gün başlıkları (yükseltilmiş "chrome" katmanı, dikeyde sabit)
///   3. "Saatsiz" satırı: saati olmayan işler (Google'daki tüm gün satırı)
///   4. Kaydırılabilir zaman ızgarası ([WeekTimeGrid])
///
/// 2–3 tek bir yüzeyde toplanır ve ızgaranın üzerine hafif bir gölge düşürür;
/// böylece kaydırılan içerik başlığın *altına* giriyor hissi oluşur.
///
/// Haftalar arası geçiş [PageView] ile; sağa/sola kaydırma ya da ok tuşları.
class WeekViewScreen extends ConsumerStatefulWidget {
  const WeekViewScreen({super.key});

  @override
  ConsumerState<WeekViewScreen> createState() => _WeekViewScreenState();
}

class _WeekViewScreenState extends ConsumerState<WeekViewScreen> {
  /// Sayfa indeksini tarihe bağlayan sabit nokta: uygulamanın açıldığı haftanın
  /// pazartesisi [_anchorPage]'e denk gelir. Böylece geçmişe de geleceğe de
  /// sınırsız kaydırılabilir.
  static const int _anchorPage = 10000;

  late final DateTime _anchorMonday = mondayOf(DateTime.now());
  late final PageController _pages = PageController(initialPage: _anchorPage);

  /// Haftalar arası geçerken dikey konum korunsun diye paylaşılan kaydırma
  /// konumu (her sayfa kendi ScrollController'ını bundan besler).
  final ValueNotifier<double> _sharedScrollOffset = ValueNotifier(0);

  int _page = _anchorPage;

  DateTime get _monday =>
      _anchorMonday.add(Duration(days: 7 * (_page - _anchorPage)));

  @override
  void dispose() {
    _pages.dispose();
    _sharedScrollOffset.dispose();
    _poolHover.dispose();
    super.dispose();
  }

  /// Bu genişliğin altında havuz sütunu takvimi yutar; orada panel bir açılır
  /// katmana iniyor, ekranda yalnız ince şerit kalıyor.
  static const double _poolColumnMinWidth = 900;

  static const _weekDays = ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ'];
  static const _months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  void _goToPage(int page, {String reason = 'arrow'}) {
    _pages.animateToPage(page, duration: Motion.slow, curve: Motion.curve);
    ref
        .read(telemetryProvider)
        .capture(
          Ev.weekChanged,
          props: {'delta': page - _page, 'reason': reason},
        );
  }

  void _shift(int weeks) => _goToPage(_page + weeks);

  void _goToToday() {
    if (_page == _anchorPage) return;
    _goToPage(_anchorPage, reason: 'today');
  }

  String _rangeLabel(DateTime monday) {
    final end = monday.add(const Duration(days: 6));
    final a = '${monday.day} ${_months[monday.month - 1]}';
    // Aynı ay içindeyse ay adını iki kez yazma: "3 – 9 Ağustos 2026".
    if (monday.month == end.month) {
      return '${monday.day} – ${end.day} ${_months[end.month - 1]} ${end.year}';
    }
    return '$a – ${end.day} ${_months[end.month - 1]} ${end.year}';
  }

  // --- Etkileşimler ----------------------------------------------------------

  Future<void> _openEditor(DateTime day, {Task? existing}) =>
      showTaskEditor(context, date: day, existing: existing);

  Future<void> _quickAdd(DateTime day, double? hour) =>
      showQuickAdd(context, date: day, startHour: hour);

  void _move(Task task, DateTime toDay, double newStartHour) {
    final undo = _snapshot(task);
    ref
        .read(appStoreProvider)
        .moveTask(task, toDay: toDay, newStartHour: newStartHour);
    _offerUndo('İş taşındı', undo);
  }

  void _resize(Task task, double duration) {
    final undo = _snapshot(task);
    ref.read(appStoreProvider).resizeTask(task, duration);
    _offerUndo('Süre değişti', undo);
  }

  void _delete(Task task) {
    final store = ref.read(appStoreProvider);
    store.removeTask(task);
    _offerUndo('İş silindi', () => store.restoreTask(task));
  }

  Future<void> _duplicate(Task task, DateTime day) async {
    final copy = task.duplicateTo(day);
    ref.read(appStoreProvider).addTask(copy);
    // Kopya doğrudan düzenleyiciye açılıyor: birebir aynı iki blok yan yana
    // durursa hangisinin kopya olduğu anlaşılmaz.
    await _openEditor(day, existing: copy);
  }

  /// Bir görevin ızgarada değişebilen alanlarının anlık kopyası; geri çağrıldığında
  /// eski hâli yerine koyar.
  ///
  /// Neden tam bir "undo yığını" değil: geri alma tek adımlık ve bildirim
  /// süresince yaşıyor. Kalıcı bir geçmiş, senkron kaydıyla birlikte tasarlanması
  /// gereken ayrı bir iş.
  VoidCallback _snapshot(Task task) {
    final date = task.date;
    final startHour = task.startHour;
    final duration = task.durationHours;
    final repeat = task.repeat;

    return () {
      task
        ..date = date
        ..startHour = startHour
        ..durationHours = duration
        ..repeat = repeat;
      ref.read(appStoreProvider).updateTask(task);
    };
  }

  // --- Havuz ------------------------------------------------------------------

  /// Panelin ekrandaki yeri. Izgara paneli tanımıyor; yalnız "bu nokta benim
  /// dışımda mı" diye soruyor, cevabı burası veriyor.
  final GlobalKey _poolKey = GlobalKey();

  /// Sürüklenen blok panelin üstünde mi — panel bunu dinleyip vurgulanıyor.
  final ValueNotifier<bool> _poolHover = ValueNotifier(false);

  bool _isOverPool(Offset globalPosition) {
    final box = _poolKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final local = box.globalToLocal(globalPosition);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }

  void _moveToPool(Task task) {
    final store = ref.read(appStoreProvider);
    final day = task.date;
    store.moveToPool(task);
    _offerUndo('Kenara alındı', () => store.pullFromPool(task, toDay: day));
  }

  void _pullFromPool(Task task, DateTime day, double hour) {
    final store = ref.read(appStoreProvider);
    store.pullFromPool(task, toDay: day, startHour: hour);
    _offerUndo('Takvime kondu', () => store.moveToPool(task));
  }

  /// Panelden "takvime geri koy": gün seçilmediği için iş eski gününe döner.
  void _restoreFromPool(Task task) {
    final store = ref.read(appStoreProvider);
    store.pullFromPool(task);
    _offerUndo('Takvime kondu', () => store.moveToPool(task));
  }

  /// Dar ekranda panel yerine açılan katman.
  ///
  /// Sütun burada mümkün değil: 390px'te 248 piksellik bir panel takvimi
  /// yutar. Sürükle-bırak da bu katmanda yok — telefonda havuza atmanın yolu
  /// bloğa dokunup "Kenara al", geri koymanın yolu buradaki listeye dokunmak.
  Future<void> _openPoolSheet() async {
    final store = ref.read(appStoreProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: Consumer(
            builder: (context, ref, _) => PoolPanel(
              tasks: ref.watch(poolProvider),
              onCollapse: () => Navigator.pop(sheetContext),
              onOpenTask: (task) {
                Navigator.pop(sheetContext);
                _openEditor(task.date, existing: task);
              },
              onRestore: (task) {
                Navigator.pop(sheetContext);
                store.pullFromPool(task);
              },
            ),
          ),
        ),
      ),
    );
  }

  // --- "Günü kurtar" ----------------------------------------------------------

  /// Bugünün kurtarma planı (plan §6'nın sözleşmesi [planDayRescue]'da).
  ///
  /// Her build'de yeniden hesaplanıyor — bilinçli: kapsam "şu andan sonrası"
  /// olduğu için gün ilerledikçe daralır, düğmedeki sayı da onunla küçülmeli.
  /// Önbelleğe alınsaydı sabah açılan uygulamada akşam hâlâ sabahki sayı
  /// yazardı.
  DayRescuePlan _rescuePlan(AppStore store, DateTime today) => planDayRescue(
    store.tasksForDate(today),
    day: today,
    afterHour: hourOf(DateTime.now()),
  );

  Future<void> _rescueDay(AppStore store, DateTime today) async {
    final plan = _rescuePlan(store, today);
    if (plan.isEmpty) return;

    // Beş ve üzeri: önce özet. Altında doğrudan uygulanır — iki işi kenara
    // almak için onay istemek düğmeyi iki tıklık bir işe çevirir ve "hızlı
    // kaçış" olma sebebini siler. Geri alma her iki hâlde de var.
    if (plan.total >= 5) {
      final ok = await _confirmRescue(plan);
      if (!ok || !mounted) return;
    }

    store.applyDayRescue(plan);
    _offerUndo(
      plan.describe(),
      () => store.undoDayRescue(plan),
      // Tek işlik bir geri almadan uzun: burada kımıldayan sekiz iş var,
      // kullanıcının ekranı taraması zaman alıyor.
      duration: const Duration(seconds: 10),
    );
  }

  /// Kalabalık kurtarmalarda önce ne olacağını gösterir.
  ///
  /// Liste süs değil: "6 iş taşınacak" cümlesi hangi altı iş olduğunu
  /// söylemiyor ve kullanıcının güvenmesi için tam olarak o lazım.
  Future<bool> _confirmRescue(DayRescuePlan plan) async {
    const shown = 6;
    final all = [...plan.toPool, ...plan.toSkip];
    final rest = all.length - shown;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Günü kurtaralım mı?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bugünün kalanından ${plan.total} iş çekilecek. '
              'Sabit işler, başlamış işler ve tamamladıkların yerinde kalıyor.',
            ),
            const SizedBox(height: S.md),
            for (final task in all.take(shown))
              Padding(
                padding: const EdgeInsets.only(bottom: S.xs),
                child: Row(
                  children: [
                    Icon(
                      task.isRoutine
                          ? Icons.repeat_rounded
                          : Icons.inbox_rounded,
                      size: 14,
                      color: context.colors.inkFaint,
                    ),
                    const SizedBox(width: S.sm),
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (rest > 0)
              Padding(
                padding: const EdgeInsets.only(top: S.xs),
                child: Text(
                  've $rest tane daha',
                  style: TextStyle(
                    color: context.colors.inkFaint,
                    fontSize: T.caption,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kurtar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Bir rutinin tek gününü atlar / atlamayı geri alır.
  void _toggleSkip(Task task, DateTime day) {
    final store = ref.read(appStoreProvider);
    final next = !task.isSkippedOn(day);
    store.skipRoutineOn(task, day, next);
    _offerUndo(
      next ? 'Bugünlük atlandı' : 'Atlama kaldırıldı',
      () => store.skipRoutineOn(task, day, !next),
    );
  }

  /// Mutasyondan sonra "Geri al" bildirimi gösterir.
  void _offerUndo(
    String label,
    VoidCallback undo, {
    Duration duration = const Duration(seconds: 5),
  }) {
    final sonner = ShadSonner.maybeOf(context);
    // Toaster yoksa (ör. ekranı tek başına kuran bir test) sessizce geç:
    // geri alma bir kolaylık, mutasyonun kendisi zaten gerçekleşti.
    if (sonner == null) return;

    final id = UniqueKey();
    sonner.show(
      ShadToast(
        id: id,
        title: Text(label),
        duration: duration,
        action: ShadButton.ghost(
          child: const Text('Geri al'),
          onPressed: () {
            undo();
            // Bildirim kendini kapatmıyor; geri alındıktan sonra ekranda
            // kalması "hâlâ geri alınabilir" izlenimi verirdi.
            sonner.hide(id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Store'u burada izliyoruz: alttaki sayfalar zaten bu build'in çocuğu,
    // her mutasyonda tüm hafta yeniden hesaplanır.
    final store = ref.watch(appStoreProvider);
    final today = Task.dayKey(DateTime.now());
    final c = context.colors;

    // Yoğunluk artık ekranın kendi durumu değil: diske yazılan bir tercih.
    final density = ref.watch(gridDensityProvider);
    final metrics = GridMetrics(hourHeight: density.hourHeight);

    // "Bugün enerjim": ızgara bunun üstündeki eforları soluklaştırır.
    final energy = ref.watch(energyFilterProvider);

    // Sol/sağ ok hafta değiştirir. Buradaki `Shortcuts`, odağa uygulamanın
    // kendi varsayılan ok tuşu kısayollarından (yön tabanlı odak gezinme) daha
    // yakın olduğu için o kazanır. Düzenleyici/hızlı ekleme ayrı bir rota
    // olduğundan metin alanlarındaki ok tuşları buraya hiç ulaşmaz.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _ShiftWeekIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _ShiftWeekIntent(1),
      },
      child: Actions(
        actions: {
          _ShiftWeekIntent: CallbackAction<_ShiftWeekIntent>(
            onInvoke: (intent) {
              _shift(intent.weeks);
              return null;
            },
          ),
        },
        // Odak zincirine bir giriş noktası: `Shortcuts` yalnız odaklanmış
        // düğümün atalarında aranır, ekranda hiçbir şey odaklı değilse ok
        // tuşları buraya hiç ulaşmazdı.
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: c.bg,
            body: SafeArea(
              bottom: false,
              // Havuz paneli hafta sütununun *yanında*: sürükleyip bırakırken
              // takvim de panel de aynı anda görünmeli, yoksa "şu işi
              // perşembeye koyayım" hareketi iki adıma bölünür.
              child: Row(
                children: [
                  Expanded(
                    child: _weekColumn(
                      c,
                      store,
                      today,
                      density,
                      metrics,
                      energy,
                    ),
                  ),
                  _poolSide(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ekranın havuz dışında kalan tarafı: başlık, tik şeridi, hafta sayfaları.
  Widget _weekColumn(
    AppPalette c,
    AppStore store,
    DateTime today,
    GridDensity density,
    GridMetrics metrics,
    Energy? energy,
  ) {
    return Column(
      children: [
        WeekHeaderBar(
          rangeLabel: _rangeLabel(_monday),
          offsetLabel: _page == _anchorPage
              ? 'Bu hafta'
              : '${_weekOffsetLabel()} hafta',
          isCurrentWeek: _page == _anchorPage,
          density: density,
          energy: energy,
          onPrevious: () => _shift(-1),
          onNext: () => _shift(1),
          onToday: _goToToday,
          onDensityChanged: (next) =>
              ref.read(gridDensityProvider.notifier).set(next),
          onEnergyChanged: (next) =>
              ref.read(energyFilterProvider.notifier).set(next),
          onCreate: _createFromHeader,
          rescuableCount: _rescuePlan(store, today).total,
          onRescue: () => _rescueDay(store, today),
          isEmptyWeek: store.tasksForWeek(_monday).every((day) => day.isEmpty),
          isFirstRun: store.tasks.isEmpty,
        ),
        // Şerit `PageView`'in dışında: hafta sayfaları kaysa da tik
        // her zaman bugüne yazılır (bkz. [DailyHabitStrip]).
        DailyHabitStrip(
          habits: store.habits,
          day: today,
          onToggle: (habit) =>
              store.toggleHabit(habit, today, source: 'week_strip'),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            onPageChanged: (page) {
              setState(() => _page = page);
              ref
                  .read(telemetryProvider)
                  .capture(
                    Ev.weekChanged,
                    props: {'delta': 0, 'reason': 'swipe'},
                  );
            },
            itemBuilder: (context, page) {
              final monday = _anchorMonday.add(
                Duration(days: 7 * (page - _anchorPage)),
              );
              final tasksByDay = store.tasksForWeek(monday);

              return Column(
                children: [
                  // Gün başlıkları + saatsiz şeridi tek yükseltilmiş katman.
                  _Chrome(
                    child: Column(
                      children: [
                        _DayHeaderRow(
                          monday: monday,
                          today: today,
                          labels: _weekDays,
                          tasksByDay: tasksByDay,
                          onTapDay: (day) => _quickAdd(day, null),
                        ),
                        _UntimedRow(
                          monday: monday,
                          tasksByDay: tasksByDay,
                          energyLimit: energy,
                          onTapTask: (task, day) =>
                              _openEditor(day, existing: task),
                          onToggle: (task, day) =>
                              store.setTaskDone(task, day, !task.isDoneOn(day)),
                        ),
                      ],
                    ),
                  ),
                  // Izgara, sayfa zeminine değil kendi beyaz yaprağına
                  // çizilir: başlıkla birlikte tek bir yükseltilmiş yüzey.
                  Expanded(
                    child: ColoredBox(
                      color: c.surface,
                      child: Stack(
                        children: [
                          WeekTimeGrid(
                            // Sayfa değiştikçe yeni durum kurulsun ama aynı
                            // hafta için gereksiz yeniden kurulum olmasın.
                            key: ValueKey('week-${monday.toIso8601String()}'),
                            monday: monday,
                            tasksByDay: tasksByDay,
                            metrics: metrics,
                            today: today,
                            scrollOffset: _sharedScrollOffset,
                            initialScrollHour: _sharedScrollOffset.value > 0
                                ? null
                                : _openingHour,
                            onTapTask: (task, day) =>
                                _openEditor(day, existing: task),
                            onTapEmpty: _quickAdd,
                            energyLimit: energy,
                            onMove: _move,
                            onResize: _resize,
                            onDuplicate: _duplicate,
                            onDelete: _delete,
                            isOverPool: _isOverPool,
                            onDropToPool: _moveToPool,
                            onToggleSkip: _toggleSkip,
                            onPullFromPool: _pullFromPool,
                            poolHover: _poolHover,
                          ),
                          // Boş hafta artık ızgaranın üstünde hiçbir şey
                          // çizmiyor (T2): bilgi başlık çubuğundaki bağlam
                          // satırında. Buradaki katmanın kalkması, havuzdan
                          // gelen bırakmanın ekranın tam ortasında kesilmesi
                          // sorununu da kökünden kaldırdı.
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
    // Kayan düğme yok: başlıktaki "Yeni" ile aynı işi yapıyordu ve ekranda
    // iki birincil eylem, tasarım sözleşmesinin ihlali. Ayrıca sağ alt köşe
    // ızgaranın en kalabalık saatlerinin üstüne oturuyordu.
  }

  /// Ekranın sağ kenarı: geniş ekranda panel ya da şerit, dar ekranda yalnız
  /// şerit (dokununca katman açılır).
  Widget _poolSide() {
    final pooled = ref.watch(poolProvider);
    final open = ref.watch(poolPanelOpenProvider);
    final wide = MediaQuery.sizeOf(context).width >= _poolColumnMinWidth;

    // Boş havuz + kapalı panel = ekranda hiçbir iz yok. Havuzu hiç kullanmayan
    // birinden 44 piksel almak, kullanan birinin bir tıklamasından pahalı.
    if (pooled.isEmpty && !open) return const SizedBox.shrink();

    return KeyedSubtree(
      key: _poolKey,
      child: (open && wide)
          ? PoolPanel(
              tasks: pooled,
              hover: _poolHover,
              onCollapse: () =>
                  ref.read(poolPanelOpenProvider.notifier).set(false),
              onOpenTask: (task) => _openEditor(task.date, existing: task),
              onRestore: _restoreFromPool,
            )
          : PoolRail(
              count: pooled.length,
              onExpand: wide
                  ? () => ref.read(poolPanelOpenProvider.notifier).set(true)
                  : _openPoolSheet,
            ),
    );
  }

  /// Açılışta ekranın ortalayacağı saat: şimdiden bir saat öncesi. Kullanıcı
  /// gece yarısı boşluğuna değil, gününe bakarak başlasın.
  double get _openingHour => (hourOfDay(DateTime.now()) - 1).clamp(0.0, 22.0);

  /// Başlıktaki "Yeni".
  ///
  /// Görünen haftaya değil **bugüne** ekler; hafta geçmişteyken oraya iş
  /// yazmak neredeyse hep yanlışlıktır. Geçmiş bir güne bilerek eklemek için
  /// ızgarada o saate tıklamak var — o niyet açık.
  Future<void> _createFromHeader() => _quickAdd(
    Task.dayKey(DateTime.now()),
    snapHour(hourOfDay(DateTime.now()), minutes: 30),
  );

  String _weekOffsetLabel() {
    final delta = _page - _anchorPage;
    if (delta == -1) return 'Geçen';
    if (delta == 1) return 'Gelecek';
    return delta < 0 ? '${-delta} hafta önce,' : '$delta hafta sonra,';
  }
}

/// Hafta değiştirme niyeti; sol/sağ ok tuşlarına bağlı.
class _ShiftWeekIntent extends Intent {
  const _ShiftWeekIntent(this.weeks);
  final int weeks;
}

// --- Ortak küçük parçalar ----------------------------------------------------

/// Gün başlıkları + saatsiz şeridini taşıyan yükseltilmiş yüzey.
class _Chrome extends StatelessWidget {
  const _Chrome({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.lineSoft)),
        boxShadow: c.shadowSm,
      ),
      child: child,
    );
  }
}

// --- Gün başlıkları ----------------------------------------------------------

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.monday,
    required this.today,
    required this.labels,
    required this.tasksByDay,
    required this.onTapDay,
  });

  final DateTime monday;
  final DateTime today;
  final List<String> labels;

  /// Gün başına iş sayısı rozetini beslemek için. Izgaranın kendisi zaten bu
  /// listeyi alıyor; başlık ikinci bir sorgu açmıyor.
  final List<List<Task>> tasksByDay;

  final ValueChanged<DateTime> onTapDay;

  /// Bu genişliğin altında sayaç rozeti düşer. 390px'te bir gün sütunu ~47px;
  /// rozet oraya sığmıyor ve sığdırmaya çalışmak gün sayısını kırpardı.
  static const double _badgeMinWidth = 700;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showBadges = MediaQuery.sizeOf(context).width >= _badgeMinWidth;

    return Padding(
      padding: const EdgeInsets.only(top: S.xs, bottom: S.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Saat sütununun hizasında duran zaman dilimi rozeti.
          SizedBox(
            width: kTimeGutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: S.sm, bottom: S.xs),
              child: Text(
                _utcOffsetLabel(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.dense,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayHeaderCell(
                day: monday.add(Duration(days: i)),
                label: labels[i],
                isToday: monday.add(Duration(days: i)) == today,
                isWeekend: i >= 5,
                taskCount: showBadges ? tasksByDay[i].length : 0,
                onTap: () => onTapDay(monday.add(Duration(days: i))),
              ),
            ),
        ],
      ),
    );
  }

  /// "GMT+3" — Google Takvim'in sol üst köşesindeki küçük bilgi.
  static String _utcOffsetLabel() {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs();
    final minutes = offset.inMinutes.abs() % 60;
    return minutes == 0
        ? 'GMT$sign$hours'
        : 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.label,
    required this.isToday,
    required this.isWeekend,
    required this.taskCount,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isToday;
  final bool isWeekend;

  /// 0 ise rozet çizilmez — hem boş gün sessiz kalır hem dar ekranda
  /// [_DayHeaderRow] sayacı bu değeri sıfırlayarak rozeti düşürür.
  final int taskCount;

  final VoidCallback onTap;

  /// Bugünün sayı dairesi. 34px, 20px yazıyı 1.3 ölçeğe kadar taşır.
  static const double _circle = 34;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      button: true,
      // Ekran okuyucu "3" değil, ne olduğunu duysun.
      label: _semanticLabel(),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: R.radiusSm,
        hoverColor: c.hover,
        child: DecoratedBox(
          // Hafta sonu ayrımı yalnız zeminde ve çok hafif. Yazıyı soluklaştırıp
          // renkle bağırmak, cumartesiyi okunmaz yapıp hiçbir şey kazandırmaz.
          decoration: BoxDecoration(
            color: isWeekend ? c.gridWeekend : Colors.transparent,
            borderRadius: R.radiusSm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    // `inkFaint` 11px'te zemine karşı 3.2:1 kalıyordu. Gün adı
                    // hangi sütunun hangi güne ait olduğunu söyleyen tek yazı;
                    // sessiz kalmalı ama okunmalı — `inkDim` ikisini de verir.
                    color: isToday ? c.accent : c.inkDim,
                    fontSize: T.micro,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: S.xs),
                // Rozet sayının *yanında* duruyor, üstünde değil: üstte olsaydı
                // ya satır yüksekliğini büyütürdü ya gün adını iterdi.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: Motion.fast,
                      curve: Motion.curve,
                      width: _circle,
                      height: _circle,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? c.accent : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        maxLines: 1,
                        style: TextStyle(
                          color: isToday ? c.onAccent : c.ink,
                          fontSize: T.headline,
                          fontWeight: isToday
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    if (taskCount > 0) ...[
                      const SizedBox(width: S.xs),
                      ShadBadge.secondary(
                        padding: const EdgeInsets.symmetric(
                          horizontal: S.xs,
                          vertical: S.hair,
                        ),
                        child: Text(
                          '$taskCount',
                          style: const TextStyle(
                            fontSize: T.dense,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel() {
    final buffer = StringBuffer('$label ${day.day}');
    if (isToday) buffer.write(', bugün');
    if (taskCount > 0) buffer.write(', $taskCount iş');
    return buffer.toString();
  }
}

// --- Saatsiz işler satırı ----------------------------------------------------

/// Google Takvim'deki "tüm gün" şeridinin karşılığı. Saati olmayan işler
/// ızgarada bir yere konamaz; burada gün sütununun tepesinde durur.
///
/// Yükseklik içeriğe göre büyür ama üst sınırı vardır: kalabalık bir gün
/// ızgarayı yutmasın diye şerit kendi içinde kaydırılır.
class _UntimedRow extends StatelessWidget {
  const _UntimedRow({
    required this.monday,
    required this.tasksByDay,
    required this.energyLimit,
    required this.onTapTask,
    required this.onToggle,
  });

  final DateTime monday;
  final List<List<Task>> tasksByDay;

  /// Izgarayla aynı kural: enerjinin üstündeki işler burada da soluklaşır.
  /// Saatsiz olmak işi kolaylaştırmıyor.
  final Energy? energyLimit;
  final void Function(Task, DateTime) onTapTask;
  final void Function(Task, DateTime) onToggle;

  static const double _chipHeight = 24.0;
  static const double _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final untimed = [
      for (final day in tasksByDay) day.where((t) => !t.scheduled).toList(),
    ];
    final maxCount = untimed.fold<int>(
      0,
      (m, list) => list.length > m ? list.length : m,
    );
    if (maxCount == 0) return const SizedBox.shrink();

    final rows = maxCount.clamp(1, _maxRows.toInt());
    final height = rows * (_chipHeight + 4) + 10;

    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: kTimeGutterWidth,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: S.sm, top: S.sm),
                child: Text(
                  'Saatsiz',
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: T.dense,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.xs, S.xs, S.xs, S.xs),
                children: [
                  for (final task in untimed[i])
                    _UntimedChip(
                      task: task,
                      day: monday.add(Duration(days: i)),
                      dimmed: task.exceedsEnergy(energyLimit),
                      onTap: onTapTask,
                      onToggle: onToggle,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UntimedChip extends StatelessWidget {
  const _UntimedChip({
    required this.task,
    required this.day,
    required this.dimmed,
    required this.onTap,
    required this.onToggle,
  });

  final Task task;
  final DateTime day;
  final bool dimmed;
  final void Function(Task, DateTime) onTap;
  final void Function(Task, DateTime) onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = task.isDoneOn(day);
    // Atlanan rutin şeritte de üstü çizili ve solgun görünmeli: "Günü kurtar"
    // saatsiz rutinlere de dokunuyor, ızgarada değişip burada değişmemesi
    // düğmenin yarım çalıştığı izlenimi verirdi.
    final skipped = task.isSkippedOn(day);
    final style = c.tag(task.color);

    return GestureDetector(
      onTap: () => onTap(task, day),
      onLongPress: () => onToggle(task, day),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Opacity(
          opacity: (dimmed || skipped) ? 0.4 : 1,
          child: AnimatedContainer(
            duration: Motion.fast,
            height: _UntimedRow._chipHeight,
            margin: const EdgeInsets.only(bottom: S.xs),
            padding: const EdgeInsets.symmetric(horizontal: S.sm),
            decoration: BoxDecoration(
              color: style.fill.withValues(alpha: done ? 0.45 : 1),
              borderRadius: R.radiusXs,
            ),
            child: Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : (skipped ? Icons.redo_rounded : Icons.circle_outlined),
                  size: 11,
                  color: style.text.withValues(alpha: 0.85),
                ),
                const SizedBox(width: S.xs),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: style.text,
                      fontSize: T.micro,
                      fontWeight: FontWeight.w600,
                      decoration: (done || skipped)
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
