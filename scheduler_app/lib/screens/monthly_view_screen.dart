import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import 'day_view_screen.dart';
import 'year_view_screen.dart';

class MonthlyViewScreen extends ConsumerStatefulWidget {
  /// Açılışta gösterilecek ay (0 = Ocak). Boşsa içinde bulunulan ay.
  final int? initialMonth;
  const MonthlyViewScreen({super.key, this.initialMonth});

  @override
  ConsumerState<MonthlyViewScreen> createState() => _MonthlyViewScreenState();
}

class _MonthlyViewScreenState extends ConsumerState<MonthlyViewScreen> {
  late final PageController _pageController = PageController(
      initialPage: widget.initialMonth ?? DateTime.now().month - 1);

  static const List<String> _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];
  /// Doğrudan büyük harfli: Dart'ın toUpperCase'i Türkçe 'i' -> 'İ' yapmaz.
  static const List<String> _weekDays = [
    'PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ'
  ];

  /// İlk dokunuşta seçilen gün; ikinci dokunuş o günü açar.
  DateTime? _selectedDay;

  /// İki aşamalı seçim: önce gün vurgulanır, sonra açılır.
  void _tapDay(DateTime date) {
    if (_selectedDay != null && DateUtils.isSameDay(_selectedDay!, date)) {
      _openDay(date);
    } else {
      setState(() => _selectedDay = date);
    }
  }

  Future<void> _openDay(DateTime date) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DayViewScreen(date: date)),
      );

  Future<void> _openRoutines() => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surfaceAlt,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (_) => const _RoutinesSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final int year = DateTime.now().year;
    final DateTime today = DateTime.now();
    // Store'u izle: hücrelerdeki iş noktaları her mutasyonda tazelensin.
    final store = ref.watch(appStoreProvider);

    return Scaffold(
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: 12,
          itemBuilder: (context, monthIndex) {
            final month = monthIndex + 1;
            final daysInMonth = DateUtils.getDaysInMonth(year, month);
            final leading = DateTime(year, month, 1).weekday - 1;
            final weeks = ((leading + daysInMonth) / 7).ceil();

            return Column(
              children: [
                _header(_months[monthIndex], year),
                _weekHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: _Grid(
                      weeks: weeks,
                      leading: leading,
                      daysInMonth: daysInMonth,
                      year: year,
                      month: month,
                      today: today,
                      selectedDay: _selectedDay,
                      store: store,
                      onTapDay: _tapDay,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showQuickAdd(
          context,
          date: _selectedDay ?? Task.dayKey(DateTime.now()),
        ),
        tooltip: 'Hızlı ekle',
        child: const Icon(Icons.add, size: 22),
      ),
    );
  }

  Widget _header(String monthName, int year) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.grid_view_outlined,
                color: AppColors.inkDim, size: 19),
            tooltip: '12 ay',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => YearViewScreen(year: year)),
              );
              if (mounted) setState(() {});
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('$monthName $year',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    )),
                const Text('kaydırarak ayları gez',
                    style: TextStyle(color: AppColors.inkFaint, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.repeat, color: AppColors.inkDim, size: 19),
            tooltip: 'Rutinler',
            onPressed: _openRoutines,
          ),
        ],
      ),
    );
  }

  Widget _weekHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: _weekDays
            .map((d) => Expanded(
                  child: Text(d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: (d == 'CMT' || d == 'PAZ')
                            ? AppColors.inkFaint
                            : AppColors.inkDim,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      )),
                ))
            .toList(),
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
                  isSelected: date != null &&
                      selectedDay != null &&
                      DateUtils.isSameDay(date, selectedDay!),
                  onTap: date == null ? null : () => onTapDay(date),
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

  const _Cell({
    required this.dayNum,
    required this.date,
    required this.store,
    required this.isWeekend,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Aya ait olmayan günler kutu almaz; yerleri boş zemin kalır.
    if (dayNum == null) return const SizedBox.shrink();

    final tasks = store.tasksForDate(date!);

    // Seçili gün en baskın; sonra bugün; sonra hafta içi/sonu tonu.
    final Color fill = isSelected
        ? AppColors.blue.withValues(alpha: 0.22)
        : isToday
            ? AppColors.blue.withValues(alpha: 0.12)
            : (isWeekend ? AppColors.gridWeekend : AppColors.gridDay);

    final Color borderColor = isSelected
        ? AppColors.blue
        : isToday
            ? AppColors.blue.withValues(alpha: 0.55)
            : AppColors.lineSoft;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(5, 5, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: isToday
                  ? const BoxDecoration(
                      color: AppColors.blue, shape: BoxShape.circle)
                  : null,
              child: Text('$dayNum',
                  style: TextStyle(
                    color: isToday
                        ? Colors.white
                        : (isWeekend ? AppColors.pink : AppColors.ink),
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                  )),
            ),
            const SizedBox(height: 2),
            // Hücreye sığmayan işler kırpılır (gün görünümünde tamamı var).
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: tasks.map((t) => _entry(t, date!)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aylık ızgarada tek satırlık iş kaydı. Rutinler soluk + ↻ işaretli.
  Widget _entry(Task task, DateTime day) {
    final done = task.isDoneOn(day);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 4, right: 3),
            decoration: BoxDecoration(
              color: done ? Colors.transparent : task.color,
              shape: BoxShape.circle,
              border: Border.all(color: task.color, width: 1),
            ),
          ),
          Expanded(
            child: Text(
              task.isRoutine ? '↻ ${task.title}' : task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: task.color.withValues(alpha: done ? 0.4 : 0.95),
                fontSize: 10,
                height: 1.15,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: task.color.withValues(alpha: 0.5),
              ),
            ),
          ),
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
    final routines = ref.watch(routinesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.repeat, size: 17, color: AppColors.inkDim),
              const SizedBox(width: 8),
              const Text('Rutinler',
                  style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${routines.length}',
                  style: const TextStyle(
                      color: AppColors.inkFaint, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          if (routines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Henüz rutin yok. Bir iş eklerken türünü "Rutin" seçersen burada listelenir.',
                style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: routines.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final t = routines[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        showTaskEditor(context, date: t.date, existing: t),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.lineSoft),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 28,
                            decoration: BoxDecoration(
                              color: t.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title,
                                    style: const TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    t.repeat.describe(t.date),
                                    if (t.scheduled)
                                      '${t.startString} · ${t.durationString}',
                                  ].join('  ·  '),
                                  style: const TextStyle(
                                      color: AppColors.inkFaint, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: AppColors.inkFaint),
                        ],
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
