import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation_controller.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/owner_avatar.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';

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

  const _Cell({
    required this.dayNum,
    required this.date,
    required this.store,
    required this.isWeekend,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    required this.onToggleTask,
  });

  @override
  Widget build(BuildContext context) {
    // Aya ait olmayan günler kutu almaz; yerleri boş zemin kalır.
    if (dayNum == null) return const SizedBox.shrink();

    final c = context.colors;
    final tasks = store.tasksForDate(date!);

    // Seçili gün en baskın; sonra bugün; sonra hafta içi/sonu tonu.
    final Color fill = isSelected
        ? c.accentSoft
        : (isWeekend ? c.gridWeekend : c.gridDay);

    final Color borderColor = isSelected
        ? c.accent
        : isToday
        ? c.accent.withValues(alpha: 0.5)
        : c.lineSoft;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          margin: const EdgeInsets.all(S.xs),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: R.radiusSm,
            border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
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

  /// Aylık ızgarada tek satırlık iş kaydı. Rutinler soluk + ↻ işaretli.
  ///
  /// Satırın kendisi bir onay kutusu: dokunmak işi o gün için tamamlar.
  /// Eskiden hücrenin tamamı tek bir dokunuş hedefiydi ve aylık takvimde
  /// yapılabilen tek şey günü açmaktı — tek bir işe hiç ulaşılamıyordu.
  ///
  /// Hücrenin boşluğu eski davranışında: bir dokunuş seçer, ikincisi günü
  /// açar. İki hedef üst üste binmiyor çünkü satır dokunuşu yutuyor.
  Widget _entry(AppPalette c, Task task, DateTime day) {
    final done = task.isDoneOn(day);
    final tag = c.tag(task.color);

    return Semantics(
      checked: done,
      label: task.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggleTask(task, day),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: _entryBody(c, task, day, done: done, tag: tag),
        ),
      ),
    );
  }

  Widget _entryBody(
    AppPalette c,
    Task task,
    DateTime day, {
    required bool done,
    required TagStyle tag,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.hair),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nokta zaten tamamlanmışlığı söylüyordu (dolu = açık, boş = bitmiş);
          // artık bitmişken ✓ oluyor. İşaret de değişsin ki bilgi yalnız
          // dolgunun varlığına bağlı kalmasın (WCAG 1.4.1).
          SizedBox(
            width: S.md,
            child: done
                ? Padding(
                    padding: const EdgeInsets.only(top: S.hair, right: S.xs),
                    child: Icon(
                      Icons.check_rounded,
                      size: I.xs,
                      color: c.inkFaint,
                    ),
                  )
                : Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: S.xs, right: S.xs),
                    decoration: BoxDecoration(
                      color: task.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: task.color, width: 1),
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              task.isRoutine ? '↻ ${task.title}' : task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: done ? c.inkFaint : tag.text,
                fontSize: T.dense,
                height: 1.2,
                fontWeight: FontWeight.w500,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: c.inkFaint,
              ),
            ),
          ),
          // Sahiplik rozeti (Y4.4d). Hücre dar olduğu için 12px ve **satırın
          // sonunda**: başa koymak, zaten tek satıra sığmayan başlıktan bir
          // parça daha alırdı. Kişisel bağlamda kendini gizler.
          if (task.ownerId != null) ...[
            const SizedBox(width: S.xs),
            Padding(
              // Nokta ve yazı üstten hizalı; rozet de onlarla aynı çizgide
              // dursun diye 1px iniyor.
              padding: const EdgeInsets.only(top: S.hair),
              child: OwnerAvatar(ownerId: task.ownerId, size: I.xs),
            ),
          ],
        ],
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
