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
    _pages.animateToPage(page, duration: Motion.slow, curve: Motion.curve);
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

  void _cycleDensity() => setState(() => _density = _density.next);

  @override
  Widget build(BuildContext context) {
    // Store'u burada izliyoruz: alttaki sayfalar zaten bu build'in çocuğu,
    // her mutasyonda tüm hafta yeniden hesaplanır.
    final store = ref.watch(appStoreProvider);
    final today = Task.dayKey(DateTime.now());
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(c),
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
                      // Gün başlıkları + saatsiz şeridi tek yükseltilmiş katman.
                      _Chrome(
                        child: Column(
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
                          ],
                        ),
                      ),
                      // Izgara, sayfa zeminine değil kendi beyaz yaprağına
                      // çizilir: başlıkla birlikte tek bir yükseltilmiş yüzey.
                      Expanded(
                        child: ColoredBox(
                          color: c.surface,
                          child: WeekTimeGrid(
                            // Sayfa değiştikçe yeni durum kurulsun ama aynı
                            // hafta için gereksiz yeniden kurulum olmasın.
                            key: ValueKey('week-${monday.toIso8601String()}'),
                            monday: monday,
                            tasksByDay: tasksByDay,
                            metrics: _metrics,
                            today: today,
                            scrollOffset: _sharedScrollOffset,
                            initialScrollHour: _sharedScrollOffset.value > 0
                                ? null
                                : _openingHour,
                            onTapTask: (task, day) =>
                                _openEditor(day, existing: task),
                            onTapEmpty: _quickAdd,
                            onMove: _move,
                            onResize: _resize,
                          ),
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
        child: const Icon(Icons.add_rounded, size: 24),
      ),
    );
  }

  /// Açılışta ekranın ortalayacağı saat: şimdiden bir saat öncesi. Kullanıcı
  /// gece yarısı boşluğuna değil, gününe bakarak başlasın.
  double get _openingHour => (hourOfDay(DateTime.now()) - 1).clamp(0.0, 22.0);

  Widget _header(AppPalette c) {
    final monday = _monday;
    final isCurrentWeek = _page == _anchorPage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
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
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  isCurrentWeek ? 'Bu hafta' : '${_weekOffsetLabel()} hafta',
                  style: TextStyle(
                    color: isCurrentWeek ? c.accent : c.inkFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),

          // "Bugün" yalnızca gerektiğinde belirir — sakin krom.
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.curve,
            child: isCurrentWeek
                ? const SizedBox(width: 0)
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _GhostButton(label: 'Bugün', onTap: _goToToday),
                  ),
          ),

          _IconAction(
            icon: _densityIcon,
            tooltip: 'Yoğunluk: ${_density.label}',
            onTap: _cycleDensity,
          ),
          const SizedBox(width: 4),

          // Geri/ileri tek bir hap içinde: iki ayrı düğme yerine tek nesne.
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: R.radiusPill,
              border: Border.all(color: c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconAction(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Önceki hafta',
                  onTap: () => _shift(-1),
                  bare: true,
                ),
                SizedBox(height: 20, child: VerticalDivider(width: 1, color: c.line)),
                _IconAction(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Sonraki hafta',
                  onTap: () => _shift(1),
                  bare: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _densityIcon => switch (_density) {
        GridDensity.compact => Icons.density_small_rounded,
        GridDensity.cozy => Icons.density_medium_rounded,
        GridDensity.spacious => Icons.density_large_rounded,
      };

  String _weekOffsetLabel() {
    final delta = _page - _anchorPage;
    if (delta == -1) return 'Geçen';
    if (delta == 1) return 'Gelecek';
    return delta < 0 ? '${-delta} hafta önce,' : '$delta hafta sonra,';
  }
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

/// Kenarlıksız, yalnızca üzerine gelince zemin alan ikon düğmesi.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.bare = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Hap içindeyken kendi zeminini çizmez.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: bare ? null : const CircleBorder(),
        borderRadius: bare ? R.radiusPill : null,
        hoverColor: c.hover,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: bare ? 10 : 9, vertical: 9),
          child: Icon(icon, size: 20, color: c.inkDim),
        ),
      ),
    );
  }
}

/// İnce kenarlıklı, sessiz hap düğme ("Bugün").
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: R.radiusPill,
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: R.radiusPill,
        hoverColor: c.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: c.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
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
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Saat sütununun hizasında duran zaman dilimi rozeti.
          SizedBox(
            width: kTimeGutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 4),
              child: Text(
                _utcOffsetLabel(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: 9.5,
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
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isToday;
  final bool isWeekend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: R.radiusSm,
      hoverColor: c.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isToday
                    ? c.accent
                    : (isWeekend ? c.inkFaint : c.inkDim),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.curve,
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? c.accent : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isToday ? c.shadowSm : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: isToday
                      ? c.onAccent
                      : (isWeekend ? c.inkDim : c.ink),
                  fontSize: 15,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
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

  static const double _chipHeight = 24.0;
  static const double _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final untimed = [
      for (final day in tasksByDay) day.where((t) => !t.scheduled).toList(),
    ];
    final maxCount =
        untimed.fold<int>(0, (m, list) => list.length > m ? list.length : m);
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
                padding: const EdgeInsets.only(right: 10, top: 9),
                child: Text(
                  'Saatsiz',
                  style: TextStyle(
                    color: c.inkFaint,
                    fontSize: 9.5,
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
                padding: const EdgeInsets.fromLTRB(3, 6, 3, 4),
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
    final c = context.colors;
    final done = task.isDoneOn(day);
    final style = c.tag(task.color);

    return GestureDetector(
      onTap: () => onTap(task, day),
      onLongPress: () => onToggle(task, day),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: _UntimedRow._chipHeight,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: style.fill.withValues(alpha: done ? 0.45 : 1),
            borderRadius: R.radiusXs,
          ),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 11,
                color: style.text.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
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
