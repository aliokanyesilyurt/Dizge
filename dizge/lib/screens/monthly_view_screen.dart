import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation_controller.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/cancel_action.dart';
import '../widgets/owner_avatar.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/undo_toast.dart';

class MonthlyViewScreen extends ConsumerStatefulWidget {
  /// Açılışta gösterilecek ay (o ayın herhangi bir günü). Boşsa içinde
  /// bulunulan ay.
  final DateTime? initialMonth;
  const MonthlyViewScreen({super.key, this.initialMonth});

  @override
  ConsumerState<MonthlyViewScreen> createState() => _MonthlyViewScreenState();
}

/// Ayı tek bir tam sayıya indirger: `2026-08` → `24319`.
///
/// `PageView`'in sayfa numarası bu. Eskiden sayfa numarası ayın sıra numarası
/// (0–11) idi ve yıl ekranın dışından geliyordu; ızgara **12 sayfada
/// bitiyordu**, yani Aralık'tan Ocak'a geçmenin yolu yoktu. Yıl da sayfa
/// numarasının içine girince sınır kendiliğinden kalktı.
int monthIndexOf(DateTime d) => d.year * 12 + d.month - 1;

/// [monthIndexOf]'un tersi: sayfa numarasından ayın ilk günü.
DateTime monthOfIndex(int index) => DateTime(index ~/ 12, index % 12 + 1);

class _MonthlyViewScreenState extends ConsumerState<MonthlyViewScreen> {
  late final int _initialPage = monthIndexOf(
    widget.initialMonth ?? DateTime.now(),
  );

  late final PageController _pageController = PageController(
    initialPage: _initialPage,
  );

  /// Başlığın gösterdiği ay. Sayfa numarasını ayrıca tutuyoruz çünkü başlık
  /// artık `PageView`'in **dışında**: içerideyken her ayın kendi kopyası
  /// vardı, oklar yatayda kayıyor ve hafta satırı ayla birlikte sürükleniyordu.
  late int _page = _initialPage;

  static const List<String> _months = [
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

  /// Doğrudan büyük harfli: Dart'ın toUpperCase'i Türkçe 'i' -> 'İ' yapmaz.
  static const List<String> _weekDays = [
    'PZT',
    'SAL',
    'ÇAR',
    'PER',
    'CUM',
    'CMT',
    'PAZ',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// İlk dokunuşta seçilen gün; ikinci dokunuş o günü açar.
  DateTime? _selectedDay;

  /// Ay değiştirir. Ölçüt denetleyicinin kendi sayfası: kaydırmanın ortasında
  /// oka basılırsa hedef, başlığın gösterdiği aydan değil gerçekten
  /// bulunulan yerden hesaplanmalı.
  void _shift(int months) =>
      _goToPage((_pageController.page?.round() ?? _page) + months);

  void _goToPage(int page) => _pageController.animateToPage(
    page,
    duration: Motion.base,
    curve: Motion.curve,
  );

  /// İki aşamalı seçim: önce gün vurgulanır, sonra açılır.
  void _tapDay(DateTime date) {
    if (_selectedDay != null && DateUtils.isSameDay(_selectedDay!, date)) {
      _openDay(date);
    } else {
      setState(() => _selectedDay = date);
    }
  }

  // Gün de ayın üstüne binen bir rota değil, kabuğun bir alt kademesi.
  void _openDay(DateTime date) =>
      ref.read(navigationProvider.notifier).openDay(date);

  /// Hücredeki bir iş satırına dokunuldu: o günü tamamla / geri al.
  void _toggleTask(Task task, DateTime day) =>
      ref.read(appStoreProvider).setTaskDone(task, day, !task.isDoneOn(day));

  /// Satırın menüsünden "Bugün iptal" seçildi: o günü iptal et / geri al.
  void _cancelTask(Task task, DateTime day) => toggleCancelOn(
    context,
    ref.read(appStoreProvider),
    task,
    day,
    source: 'month',
  );

  /// Bir iş başka bir günün hücresine bırakıldı (plan H2).
  ///
  /// Havuzdan gelen iş takvime iner; takvimdeki iş yalnız gününü değiştirir,
  /// saati olduğu gibi kalır.
  void _dropOnDay(Task task, DateTime day) {
    final store = ref.read(appStoreProvider);
    if (task.inPool) {
      store.pullFromPool(task, toDay: day);
      offerUndo(context, 'Takvime kondu', () => store.moveToPool(task));
      return;
    }
    final from = task.date;
    store.moveTaskToDay(task, day);
    offerUndo(context, 'İş taşındı', () => store.moveTaskToDay(task, from));
  }

  Future<void> _openRoutines() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _RoutinesSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final DateTime today = DateTime.now();
    // Store'u izle: hücrelerdeki iş noktaları her mutasyonda tazelensin.
    final store = ref.watch(appStoreProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Başlık ve hafta satırı `PageView`'in **dışında**: içerideyken
            // her ayın kendi kopyası vardı ve gün adları ayla birlikte
            // yatayda sürükleniyordu.
            _header(c, monthOfIndex(_page), today),
            _weekHeader(c),
            Expanded(
              // Sayfa sayısı yok: takvimin ne sonu var ne başı. Sayfalar
              // tembel kurulduğu için sınırsızlığın bedeli de sıfır.
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) {
                  final shown = monthOfIndex(index);
                  final daysInMonth = DateUtils.getDaysInMonth(
                    shown.year,
                    shown.month,
                  );
                  final leading =
                      DateTime(shown.year, shown.month, 1).weekday - 1;
                  final weeks = ((leading + daysInMonth) / 7).ceil();

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.lg),
                    child: _Grid(
                      weeks: weeks,
                      leading: leading,
                      daysInMonth: daysInMonth,
                      year: shown.year,
                      month: shown.month,
                      today: today,
                      selectedDay: _selectedDay,
                      store: store,
                      onTapDay: _tapDay,
                      onToggleTask: _toggleTask,
                      onCancelTask: _cancelTask,
                      onDropTask: _dropOnDay,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showQuickAdd(
          context,
          date: _selectedDay ?? Task.dayKey(DateTime.now()),
        ),
        tooltip: 'Hızlı ekle',
        child: const Icon(Icons.add_rounded, size: I.lg),
      ),
    );
  }

  Widget _header(AppPalette c, DateTime shown, DateTime today) {
    final onThisMonth = shown.year == today.year && shown.month == today.month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.sm, S.md, S.sm, S.xs),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.grid_view_rounded, color: c.inkDim, size: I.md),
            tooltip: '12 ay',
            // Bakılan yılı yanında götürüyor: 2028'in Haziran'ından çıkan
            // kişi 2028'in ızgarasına düşsün, bu yılınkine değil.
            onPressed: () =>
                ref.read(navigationProvider.notifier).openYear(shown.year),
          ),
          IconButton(
            icon: Icon(Icons.chevron_left_rounded, color: c.inkDim, size: I.md),
            tooltip: 'Önceki ay',
            onPressed: () => _shift(-1),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_months[shown.month - 1]} ${shown.year}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: S.hair),
                // Bu satır iki iş yapıyor ama asla ikisini birden: bulunulan
                // aydayken kaydırmayı öğretiyor, uzaktayken geri dönüş kapısı
                // oluyor. Ayrı bir düğme sırası başlığı iki kat yükseltirdi.
                if (onThisMonth)
                  Text(
                    'kaydırarak ayları gez',
                    style: TextStyle(color: c.inkFaint, fontSize: T.micro),
                  )
                else
                  _TodayLink(onTap: () => _goToPage(monthIndexOf(today))),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right_rounded,
              color: c.inkDim,
              size: I.md,
            ),
            tooltip: 'Sonraki ay',
            onPressed: () => _shift(1),
          ),
          IconButton(
            icon: Icon(Icons.repeat_rounded, color: c.inkDim, size: I.md),
            tooltip: 'Rutinler',
            onPressed: _openRoutines,
          ),
        ],
      ),
    );
  }

  Widget _weekHeader(AppPalette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
      child: Row(
        children: _weekDays
            .map(
              (d) => Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: (d == 'CMT' || d == 'PAZ') ? c.inkFaint : c.inkDim,
                    fontSize: T.dense,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Başlığın alt satırındaki "Bugün" dönüşü.
///
/// Düğme kılığında değil bağlantı kılığında: başlığın ipucu satırının yerine
/// geçiyor ve o satırın dikey ritmini bozmaması gerek. Metin küçük ama hedef
/// değil — dokunma alanı metnin çevresinde ayrıca genişletiliyor.
class _TodayLink extends StatelessWidget {
  const _TodayLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      button: true,
      label: 'Bugünün ayına dön',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.hair,
            ),
            child: Text(
              'Bugün',
              style: TextStyle(
                color: c.accent,
                fontSize: T.micro,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Her günün ayrı bir kutu olduğu aylık tablo.
class _Grid extends StatelessWidget {
  final int weeks;
  final int leading;
  final int daysInMonth;
  final int year;
  final int month;
  final DateTime today;
  final DateTime? selectedDay;
  final AppStore store;
  final void Function(DateTime date) onTapDay;

  /// Hucredeki bir is satirina dokunuldu: o gunu tamamla / geri al.
  final void Function(Task task, DateTime day) onToggleTask;

  /// Aynı satıra uzun basıldı: o günü iptal et / iptali geri al.
  final void Function(Task task, DateTime day) onCancelTask;

  /// Bir iş bu ızgaradaki bir güne bırakıldı.
  final void Function(Task task, DateTime day) onDropTask;

  const _Grid({
    required this.weeks,
    required this.leading,
    required this.daysInMonth,
    required this.year,
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.store,
    required this.onTapDay,
    required this.onToggleTask,
    required this.onCancelTask,
    required this.onDropTask,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(weeks, (w) {
        return Expanded(
          child: Row(
            children: List.generate(7, (dow) {
              final dayNum = w * 7 + dow - leading + 1;
              final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
              final date = inMonth ? DateTime(year, month, dayNum) : null;
              return Expanded(
                child: _Cell(
                  dayNum: inMonth ? dayNum : null,
                  date: date,
                  store: store,
                  isWeekend: dow >= 5,
                  isToday: date != null && DateUtils.isSameDay(date, today),
                  isSelected:
                      date != null &&
                      selectedDay != null &&
                      DateUtils.isSameDay(date, selectedDay!),
                  onTap: date == null ? null : () => onTapDay(date),
                  onToggleTask: onToggleTask,
                  onCancelTask: onCancelTask,
                  onDropTask: onDropTask,
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _Cell extends StatelessWidget {
  final int? dayNum;
  final DateTime? date;
  final AppStore store;
  final bool isWeekend;
  final bool isToday;

  /// İlk dokunuşla seçilmiş gün: vurgulanır ama henüz açılmaz.
  final bool isSelected;
  final VoidCallback? onTap;

  /// Is satirina dokunulunca cagrilir (hucrenin bosluguna degil).
  final void Function(Task task, DateTime day) onToggleTask;

  /// Is satirina uzun basilinca cagrilir.
  final void Function(Task task, DateTime day) onCancelTask;

  final void Function(Task task, DateTime day) onDropTask;

  const _Cell({
    required this.dayNum,
    required this.date,
    required this.store,
    required this.isWeekend,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    required this.onToggleTask,
    required this.onCancelTask,
    required this.onDropTask,
  });

  /// Bu hücre sürüklenen işi kabul eder mi?
  ///
  /// Rutin buraya hiç gelmez (sürüklenemiyor); yine de denetim burada da var
  /// ki başka bir kaynaktan gelen rutin sessizce bir güne çakılmasın. Kendi
  /// gününe bırakılan iş reddedilir: satır yerinde bırakıldığında dokunmatikte
  /// hızlı menü açılıyor ve bunun için bırakmanın "kabul edilmemiş" olması
  /// gerekiyor.
  bool _accepts(Task task) {
    if (task.isRoutine) return false;
    if (task.inPool) return true;
    return !DateUtils.isSameDay(task.date, date);
  }

  @override
  Widget build(BuildContext context) {
    // Aya ait olmayan günler kutu almaz; yerleri boş zemin kalır.
    if (dayNum == null) return const SizedBox.shrink();

    final c = context.colors;
    var tasks = store.tasksForDate(date!);
    if (store.activeGroupId != '*all*') {
      tasks = tasks.where((t) => t.groupId == store.activeGroupId).toList();
    }

    // Seçili gün en baskın; sonra bugün; sonra hafta içi/sonu tonu.
    final Color fill = isSelected
        ? c.accentSoft
        : (isWeekend ? c.gridWeekend : c.gridDay);

    final Color borderColor = isSelected
        ? c.accent
        : isToday
        ? c.accent.withValues(alpha: 0.5)
        : c.lineSoft;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onAcceptWithDetails: (details) => onDropTask(details.data, date!),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        return _body(c, tasks, fill, borderColor, hovered);
      },
    );
  }

  Widget _body(
    AppPalette c,
    List<Task> tasks,
    Color fill,
    Color borderColor,
    bool hovered,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          margin: const EdgeInsets.all(S.xs),
          decoration: BoxDecoration(
            // Bırakma hedefi haftalık ızgaradakiyle aynı tonda: kullanıcı
            // "buraya düşecek" rengini bir kez öğreniyor.
            color: hovered ? c.dropTarget : fill,
            borderRadius: R.radiusSm,
            border: Border.all(
              color: hovered ? c.accent : borderColor,
              width: (isSelected || hovered) ? 1.5 : 1,
            ),
            boxShadow: isSelected || isToday ? c.shadowSm : null,
          ),
          padding: const EdgeInsets.fromLTRB(S.xs, S.xs, S.xs, S.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(color: c.accent, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    color: isToday
                        ? c.onAccent
                        : (isWeekend ? c.inkFaint : c.ink),
                    fontSize: T.micro,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: S.xs),
              // Hücreye sığmayan işler kırpılır (gün görünümünde tamamı var).
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: tasks.map((t) => _entry(c, t, date!)).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Aylık ızgarada tek satırlık iş kaydı. Rutinler ↻ işaretli.
  ///
  /// Satırın kendisi bir onay kutusu: dokunmak işi o gün için tamamlar.
  /// Eskiden hücrenin tamamı tek bir dokunuş hedefiydi ve aylık takvimde
  /// yapılabilen tek şey günü açmaktı — tek bir işe hiç ulaşılamıyordu.
  ///
  /// Hücrenin boşluğu eski davranışında: bir dokunuş seçer, ikincisi günü
  /// açar. İki hedef üst üste binmiyor çünkü satır dokunuşu yutuyor.
  Widget _entry(AppPalette c, Task task, DateTime day) {
    return _TaskBox(
      task: task,
      day: day,
      onToggleTask: onToggleTask,
      onCancelTask: onCancelTask,
    );
  }
}

class _TaskBox extends StatefulWidget {
  final Task task;
  final DateTime day;
  final void Function(Task task, DateTime day) onToggleTask;
  final void Function(Task task, DateTime day) onCancelTask;

  const _TaskBox({
    required this.task,
    required this.day,
    required this.onToggleTask,
    required this.onCancelTask,
  });

  @override
  State<_TaskBox> createState() => _TaskBoxState();
}

class _TaskBoxState extends State<_TaskBox> {
  bool _hovered = false;

  /// Sürüklemenin başladığı andaki küresel köşe. Dokunmatikte "uzun bas,
  /// kıpırdamadan bırak" hızlı menüyü açıyor (plan H3); bırakılan yerin buna
  /// yakın olup olmadığı o kararı veriyor.
  Offset? _dragOrigin;

  /// Bu kadar pikselden az kayan bırakma "kıpırdamadı" sayılır.
  static const double _stillSlop = 12;

  /// Dokunmatik mi? Fare varken sürükleme anında başlıyor; parmakta düz
  /// sürükleme ay kaydırmasıyla çakışacağı için uzun basma bekleniyor.
  static bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _onDragStarted() {
    final box = context.findRenderObject() as RenderBox?;
    _dragOrigin = box?.localToGlobal(Offset.zero);
  }

  void _onDragEnd(DraggableDetails details) {
    final origin = _dragOrigin;
    _dragOrigin = null;
    if (!_touch || details.wasAccepted || origin == null || !mounted) return;
    if ((details.offset - origin).distance < _stillSlop) {
      _showQuickActions(context);
    }
  }

  /// Uzun basış (masaüstünde sağ tık): satırın bütün eylemleri.
  ///
  /// Kısa dokunuş en sık istenen şeyi — tamamlamayı — yapıyor; iptal ve
  /// düzenleme daha seyrek, hücrede de onlara ayrı hedef açacak yer yok.
  /// "Tamamla" menüde de var ki uzun basan kişi aradığını bulsun.
  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        final done = widget.task.isDoneOn(widget.day);
        final cancelled = widget.task.isSkippedOn(widget.day);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  done ? Icons.undo_rounded : Icons.check_circle_rounded,
                  color: done ? c.inkDim : c.accent,
                ),
                title: Text(done ? 'Tamamlanmayı geri al' : 'Tamamla'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onToggleTask(widget.task, widget.day);
                },
              ),
              ListTile(
                leading: Icon(
                  cancelIcon(cancelled),
                  color: cancelled ? c.inkDim : c.danger,
                ),
                title: Text(cancelLabel(cancelled)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCancelTask(widget.task, widget.day);
                },
              ),
              ListTile(
                leading: Icon(Icons.edit_rounded, color: c.inkDim),
                title: const Text('Düzenle'),
                onTap: () {
                  Navigator.pop(ctx);
                  showTaskEditor(
                    context,
                    date: widget.day,
                    existing: widget.task,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = widget.task.isDoneOn(widget.day);
    final cancelled = widget.task.isSkippedOn(widget.day);
    final tag = c.tag(widget.task.color);
    // Rutin aylıkta sürüklenmez (plan H2); uzun basması hızlı menüde kalır.
    final draggable = !widget.task.isRoutine;

    final row = Semantics(
      checked: done,
      label: widget.task.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onToggleTask(widget.task, widget.day),
          // Dokunmatikte sürüklenebilen satırın uzun basması sürüklemenin;
          // menü orada "kıpırdamadan bırak"la açılıyor ([_onDragEnd]).
          onLongPress: (draggable && _touch)
              ? null
              : () => _showQuickActions(context),
          onSecondaryTap: () => _showQuickActions(context),
          child: Container(
            margin: const EdgeInsets.only(bottom: S.hair),
            padding: const EdgeInsets.symmetric(
              horizontal: S.xs,
              vertical: S.hair,
            ),
            decoration: BoxDecoration(
              color: (done || cancelled) ? Colors.transparent : tag.fill,
              borderRadius: R.radiusXs,
              border: Border.all(
                color: (done || cancelled) ? c.lineSoft : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                if (!done && !cancelled && !_hovered)
                  Container(
                    width: 3,
                    height: 12,
                    margin: const EdgeInsets.only(right: S.xs),
                    decoration: BoxDecoration(
                      color: widget.task.color,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                // Bitmiş/iptal işte işaret hep görünüyor: bilgi yalnız
                // üstü çizili yazıya bağlı kalmasın (WCAG 1.4.1). Açık işte
                // yalnız fare üstündeyken — satırın bir onay kutusu olduğunu
                // söylüyor.
                if (_hovered || done || cancelled)
                  Padding(
                    padding: const EdgeInsets.only(right: S.xs),
                    child: Icon(
                      done
                          ? Icons.check_circle_rounded
                          // İptal edilen gün ✓ değil ↷: "yapıldı" ile
                          // "bugünlük geçildi" aynı işaretle anlatılamaz.
                          : (cancelled
                                ? cancelIcon(false)
                                : Icons.radio_button_unchecked_rounded),
                      size: I.xs,
                      color: done
                          ? c.inkFaint
                          : (cancelled ? c.danger : tag.text),
                    ),
                  ),
                Expanded(
                  child: Text(
                    widget.task.isRoutine
                        ? '↻ ${widget.task.title}'
                        : widget.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (done || cancelled) ? c.inkFaint : tag.text,
                      fontSize: T.dense,
                      fontWeight: FontWeight.w600,
                      decoration: (done || cancelled)
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: c.inkFaint,
                    ),
                  ),
                ),
                // Sahiplik rozeti (Y4.4d). Hücre dar olduğu için satırın
                // **sonunda**: başa koymak, zaten tek satıra sığmayan
                // başlıktan bir parça daha alırdı. Kişisel bağlamda kendini
                // gizler.
                if (widget.task.ownerId != null) ...[
                  const SizedBox(width: S.xs),
                  OwnerAvatar(ownerId: widget.task.ownerId, size: I.xs),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!draggable) return row;

    final feedback = _MonthDragFeedback(task: widget.task);
    final ghost = Opacity(opacity: 0.3, child: row);
    if (_touch) {
      return LongPressDraggable<Task>(
        data: widget.task,
        feedback: feedback,
        childWhenDragging: ghost,
        onDragStarted: _onDragStarted,
        onDragEnd: _onDragEnd,
        child: row,
      );
    }
    return Draggable<Task>(
      data: widget.task,
      feedback: feedback,
      childWhenDragging: ghost,
      child: row,
    );
  }
}

/// Aylıkta sürüklenen satırın imlecin altındaki hâli.
class _MonthDragFeedback extends StatelessWidget {
  const _MonthDragFeedback({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tag = c.tag(task.color);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
        decoration: BoxDecoration(
          color: tag.fill,
          borderRadius: R.radiusXs,
          border: Border.all(color: task.color, width: 1.2),
          boxShadow: c.shadowMd,
        ),
        child: Text(
          task.title.isEmpty ? 'Başlıksız' : task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tag.text,
            fontSize: T.dense,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Tüm rutinlerin listesi — buradan düzenlenip silinebilir.
class _RoutinesSheet extends ConsumerWidget {
  const _RoutinesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final routines = ref.watch(routinesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat_rounded, size: I.md, color: c.inkDim),
              const SizedBox(width: S.sm),
              Text('Rutinler', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.sm,
                  vertical: S.xs,
                ),
                decoration: BoxDecoration(
                  color: c.hover,
                  borderRadius: R.radiusPill,
                ),
                child: Text(
                  '${routines.length}',
                  style: TextStyle(
                    color: c.inkDim,
                    fontSize: T.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.lg),
          if (routines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.xl),
              child: Text(
                'Henüz rutin yok. Bir iş eklerken türünü "Rutin" seçersen '
                'burada listelenir.',
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.body,
                  height: 1.5,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: routines.length,
                separatorBuilder: (_, _) => const SizedBox(height: S.sm),
                itemBuilder: (_, i) {
                  final t = routines[i];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: R.radiusMd,
                      onTap: () =>
                          showTaskEditor(context, date: t.date, existing: t),
                      child: Container(
                        padding: const EdgeInsets.all(S.md),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: R.radiusMd,
                          border: Border.all(color: c.lineSoft),
                          boxShadow: c.shadowSm,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 30,
                              decoration: BoxDecoration(
                                color: t.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: S.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.ink,
                                      fontSize: T.strong,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: S.xs),
                                  Text(
                                    [
                                      t.repeat.describe(t.date),
                                      if (t.scheduled)
                                        '${t.startString} · ${t.durationString}',
                                    ].join('  ·  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.inkFaint,
                                      fontSize: T.micro,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: I.md,
                              color: c.inkFaint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
