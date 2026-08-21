import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/day_rescue.dart';
import '../core/energy_filter_controller.dart';
import '../core/grid_density_controller.dart';
import '../core/pool_panel_controller.dart';
import '../core/telemetry.dart';
import '../core/time_grid.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/cancel_action.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/undo_toast.dart';
import '../widgets/week_time_grid.dart';
import 'week/daily_habit_strip.dart';
import 'week/day_headers.dart';
import 'week/pool_panel.dart';
import 'week/untimed_row.dart';
import 'week/week_chrome.dart';
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
                      size: I.xs,
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

  /// İşin bu gününü tamamlar / geri alır.
  ///
  /// Tek kapı: önizleme kartındaki kutu da sağ tık menüsündeki "Yaptım" da
  /// buraya geliyor. [slotHour] doluysa işaretlenen gün değil, gün içindeki
  /// o tekrar (Z6).
  void _toggleDone(Task task, DateTime day, double? slotHour) {
    final store = ref.read(appStoreProvider);
    if (slotHour != null) {
      store.setTaskSlotDone(
        task,
        day,
        slotHour,
        !task.isSlotDone(day, slotHour),
      );
    } else {
      store.setTaskDone(task, day, !task.isDoneOn(day));
    }
  }

  /// "Bugün iptal" — rutinde günü atlar, tek günlük işte havuza alır.
  ///
  /// Eskiden burada yalnız rutinin atlaması vardı; tek günlük işin karşılığı
  /// ("Kenara al") ayrı bir menü satırıydı ve kullanıcı hangisinin geçerli
  /// olduğunu bilmek zorundaydı. Artık ayrımı [toggleCancelOn] içeride
  /// yapıyor (plan K3).
  void _cancelOn(Task task, DateTime day) =>
      toggleCancelOn(context, ref.read(appStoreProvider), task, day);

  /// Mutasyondan sonra "Geri al" bildirimi gösterir.
  ///
  /// Gövdesi [offerUndo]'ya taşındı: aynı bildirim artık aylık hücrede ve iki
  /// liste ekranında da çıkıyor (plan K3). Buradaki kısa ad yerinde kalıyor,
  /// çağrı yerleri `context`'i her seferinde tekrar yazmasın diye.
  void _offerUndo(
    String label,
    VoidCallback undo, {
    Duration duration = const Duration(seconds: 5),
  }) => offerUndo(context, label, undo, duration: duration);

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
                  WeekChrome(
                    child: Column(
                      children: [
                        DayHeaderRow(
                          monday: monday,
                          today: today,
                          labels: _weekDays,
                          tasksByDay: tasksByDay,
                          onTapDay: (day) => _quickAdd(day, null),
                        ),
                        UntimedRow(
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
                            onToggleDone: _toggleDone,
                            energyLimit: energy,
                            onMove: _move,
                            onResize: _resize,
                            onDuplicate: _duplicate,
                            onDelete: _delete,
                            isOverPool: _isOverPool,
                            onDropToPool: _moveToPool,
                            onCancel: _cancelOn,
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
