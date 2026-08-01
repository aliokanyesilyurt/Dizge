import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../core/time_grid.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/week_time_grid.dart';

/// Haftalık görünüm — uygulamanın ana ekranı.
///
/// Google Takvim'in hafta görünümündeki temel modeli izler: dikeyde saatler,
/// yatayda günler, işler zaman blokları. Farkı, minimalist koyu palet ve
/// gereksiz kromun (araç çubuğu, kenarlık, gölge) atılmış olması.
///
/// Yapı — üstten alta:
///   1. Başlık: tarih aralığı, hafta gezinme, yoğunluk düğmesi
///   2. Gün başlıkları (kaydırmayla birlikte kayar, dikeyde sabit)
///   3. "Saatsiz" satırı: saati olmayan işler (Google'daki tüm gün satırı)
///   4. Kaydırılabilir zaman ızgarası ([WeekTimeGrid])
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
  late final PageController _pages =
      PageController(initialPage: _anchorPage);

  /// Haftalar arası geçerken dikey konum korunsun diye paylaşılan kaydırma
  /// konumu (her sayfa kendi ScrollController'ını bundan besler).
  final ValueNotifier<double> _sharedScrollOffset = ValueNotifier(0);

  GridDensity _density = GridDensity.cozy;
  int _page = _anchorPage;

  DateTime get _monday =>
      _anchorMonday.add(Duration(days: 7 * (_page - _anchorPage)));

  GridMetrics get _metrics => GridMetrics(hourHeight: _density.hourHeight);

  @override
  void dispose() {
    _pages.dispose();
    _sharedScrollOffset.dispose();
    super.dispose();
  }

  static const _weekDays = ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ'];
  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  void _goToPage(int page, {String reason = 'arrow'}) {
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    ref.read(telemetryProvider).capture(Ev.weekChanged, props: {
      'delta': page - _page,
      'reason': reason,
    });
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
    ref.read(appStoreProvider).moveTask(
          task,
          toDay: toDay,
          newStartHour: newStartHour,
        );
  }

  void _resize(Task task, double duration) =>
      ref.read(appStoreProvider).resizeTask(task, duration);

  void _cycleDensity() {
    setState(() => _density = _density.next);
  }

  @override
  Widget build(BuildContext context) {
    // Store'u burada izliyoruz: alttaki sayfalar zaten bu build'in çocuğu,
    // her mutasyonda tüm hafta yeniden hesaplanır.
    final store = ref.watch(appStoreProvider);
    final today = Task.dayKey(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (page) {
                  setState(() => _page = page);
                  ref.read(telemetryProvider).capture(Ev.weekChanged, props: {
                    'delta': 0,
                    'reason': 'swipe',
                  });
                },
                itemBuilder: (context, page) {
                  final monday =
                      _anchorMonday.add(Duration(days: 7 * (page - _anchorPage)));
                  final tasksByDay = store.tasksForWeek(monday);

                  return Column(
                    children: [
                      _DayHeaderRow(
                        monday: monday,
                        today: today,
                        labels: _weekDays,
                        onTapDay: (day) => _quickAdd(day, null),
                      ),
                      _UntimedRow(
                        monday: monday,
                        tasksByDay: tasksByDay,
                        onTapTask: (task, day) =>
                            _openEditor(day, existing: task),
                        onToggle: (task, day) => store.setTaskDone(
                          task,
                          day,
                          !task.isDoneOn(day),
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.line),
                      Expanded(
                        child: WeekTimeGrid(
                          // Sayfa değiştikçe yeni durum kurulsun ama aynı hafta
                          // için gereksiz yeniden kurulum olmasın.
                          key: ValueKey('week-${monday.toIso8601String()}'),
                          monday: monday,
                          tasksByDay: tasksByDay,
                          metrics: _metrics,
                          today: today,
                          scrollOffset: _sharedScrollOffset,
                          initialScrollHour:
                              _sharedScrollOffset.value > 0 ? null : _openingHour,
                          onTapTask: (task, day) =>
                              _openEditor(day, existing: task),
                          onTapEmpty: _quickAdd,
                          onMove: _move,
                          onResize: _resize,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _quickAdd(
          Task.dayKey(DateTime.now()),
          snapHour(hourOfDay(DateTime.now()), minutes: 30),
        ),
        tooltip: 'Hızlı ekle',
        child: const Icon(Icons.add, size: 22),
      ),
    );
  }

  /// Açılışta ekranın ortalayacağı saat: şimdiden bir saat öncesi. Kullanıcı
  /// gece yarısı boşluğuna değil, gününe bakarak başlasın.
  double get _openingHour =>
      (hourOfDay(DateTime.now()) - 1).clamp(0.0, 22.0);

  Widget _header() {
    final monday = _monday;
    final isCurrentWeek = _page == _anchorPage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _rangeLabel(monday),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  isCurrentWeek ? 'Bu hafta' : '${_weekOffsetLabel()} hafta',
                  style: const TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!isCurrentWeek)
            TextButton(
              onPressed: _goToToday,
              child: const Text('Bugün'),
            ),
          IconButton(
            icon: Icon(_densityIcon, color: AppColors.inkDim, size: 19),
            tooltip: 'Yoğunluk: ${_density.label}',
            onPressed: _cycleDensity,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppColors.inkDim),
            tooltip: 'Önceki hafta',
            onPressed: () => _shift(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppColors.inkDim),
            tooltip: 'Sonraki hafta',
            onPressed: () => _shift(1),
          ),
        ],
      ),
    );
  }

  IconData get _densityIcon => switch (_density) {
        GridDensity.compact => Icons.density_small,
        GridDensity.cozy => Icons.density_medium,
        GridDensity.spacious => Icons.density_large,
      };

  String _weekOffsetLabel() {
    final delta = _page - _anchorPage;
    if (delta == -1) return 'Geçen';
    if (delta == 1) return 'Gelecek';
    return delta < 0 ? '${-delta} hafta önce,' : '$delta hafta sonra,';
  }
}

// --- Gün başlıkları ----------------------------------------------------------

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.monday,
    required this.today,
    required this.labels,
    required this.onTapDay,
  });

  final DateTime monday;
  final DateTime today;
  final List<String> labels;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: kTimeGutterWidth),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayHeaderCell(
                day: monday.add(Duration(days: i)),
                label: labels[i],
                isToday: monday.add(Duration(days: i)) == today,
                isWeekend: i >= 5,
                onTap: () => onTapDay(monday.add(Duration(days: i))),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.label,
    required this.isToday,
    required this.isWeekend,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isToday;
  final bool isWeekend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isToday
                  ? AppColors.blue
                  : (isWeekend ? AppColors.pink : AppColors.inkFaint),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? AppColors.blue : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: isToday ? Colors.white : AppColors.ink,
                fontSize: 14,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
    required this.onTapTask,
    required this.onToggle,
  });

  final DateTime monday;
  final List<List<Task>> tasksByDay;
  final void Function(Task, DateTime) onTapTask;
  final void Function(Task, DateTime) onToggle;

  static const double _chipHeight = 22.0;
  static const double _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final untimed = [
      for (final day in tasksByDay) day.where((t) => !t.scheduled).toList(),
    ];
    final maxCount = untimed.fold<int>(0, (m, list) => list.length > m ? list.length : m);
    if (maxCount == 0) return const SizedBox.shrink();

    final rows = maxCount.clamp(1, _maxRows.toInt());
    final height = rows * (_chipHeight + 3) + 6;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: kTimeGutterWidth,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(right: 8, top: 6),
                child: Text(
                  'Saatsiz',
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
                children: [
                  for (final task in untimed[i])
                    _UntimedChip(
                      task: task,
                      day: monday.add(Duration(days: i)),
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
    required this.onTap,
    required this.onToggle,
  });

  final Task task;
  final DateTime day;
  final void Function(Task, DateTime) onTap;
  final void Function(Task, DateTime) onToggle;

  @override
  Widget build(BuildContext context) {
    final done = task.isDoneOn(day);
    final style = tagStyleFor(task.color);

    return GestureDetector(
      onTap: () => onTap(task, day),
      onLongPress: () => onToggle(task, day),
      child: Container(
        height: _UntimedRow._chipHeight,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: style.fill.withValues(alpha: done ? 0.5 : 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 11,
              color: style.text.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: style.text,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
