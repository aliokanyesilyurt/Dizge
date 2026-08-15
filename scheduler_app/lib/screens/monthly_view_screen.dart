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
  /// Açılışta gösterilecek ay (0 = Ocak). Boşsa içinde bulunulan ay.
  final int? initialMonth;
  const MonthlyViewScreen({super.key, this.initialMonth});

  @override
  ConsumerState<MonthlyViewScreen> createState() => _MonthlyViewScreenState();
}

class _MonthlyViewScreenState extends ConsumerState<MonthlyViewScreen> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialMonth ?? DateTime.now().month - 1,
  );

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

  // Gün de ayın üstüne binen bir rota değil, kabuğun bir alt kademesi.
  void _openDay(DateTime date) =>
      ref.read(navigationProvider.notifier).openDay(date);

  Future<void> _openRoutines() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _RoutinesSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final int year = DateTime.now().year;
    final DateTime today = DateTime.now();
    // Store'u izle: hücrelerdeki iş noktaları her mutasyonda tazelensin.
    final store = ref.watch(appStoreProvider);

    return Scaffold(
      backgroundColor: c.bg,
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
                _header(c, _months[monthIndex], year),
                _weekHeader(c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.lg),
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
        child: const Icon(Icons.add_rounded, size: 24),
      ),
    );
  }

  Widget _header(AppPalette c, String monthName, int year) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.sm, S.md, S.sm, S.xs),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.grid_view_rounded, color: c.inkDim, size: 19),
            tooltip: '12 ay',
            onPressed: () =>
                ref.read(navigationProvider.notifier).go(AppSection.year),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$monthName $year',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: S.hair),
                Text(
                  'kaydırarak ayları gez',
                  style: TextStyle(color: c.inkFaint, fontSize: T.micro),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.repeat_rounded, color: c.inkDim, size: 19),
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
                  isSelected:
                      date != null &&
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
  Widget _entry(AppPalette c, Task task, DateTime day) {
    final done = task.isDoneOn(day);
    final tag = c.tag(task.color);

    return Padding(
      padding: const EdgeInsets.only(bottom: S.hair),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: S.xs, right: S.xs),
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
              child: OwnerAvatar(ownerId: task.ownerId, size: 12),
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
              Icon(Icons.repeat_rounded, size: 18, color: c.inkDim),
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
                              size: 18,
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
