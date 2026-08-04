import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation_controller.dart';
import '../data/app_store.dart';
import '../theme.dart';

class YearViewScreen extends ConsumerWidget {
  final int? year;
  const YearViewScreen({super.key, this.year});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final int year = this.year ?? DateTime.now().year;
    // Store'u izle: aylardan dönünce noktalar elle setState olmadan tazelenir.
    final store = ref.watch(appStoreProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          '$year',
          style: TextStyle(
            color: c.ink,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(18),
          // Sabit 3 sütun geniş ekranda ayları aşırı geriyordu; genişliğe göre
          // sütun sayısı belirlensin ki webde de derli toplu dursun.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            childAspectRatio: 0.92,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            return _MiniMonth(
              year: year,
              month: index + 1,
              monthName: _months[index],
              store: store,
              // Rota itmiyoruz: yeni rota kabuğun üstüne biner ve kenar çubuğu
              // kaybolurdu. Ay, yılın *üstü* değil aynı takvimin bir kademe
              // yakını — kabuğun bölümü değişiyor, çerçeve yerinde kalıyor.
              onTap: () =>
                  ref.read(navigationProvider.notifier).openMonth(index),
            );
          },
        ),
      ),
    );
  }
}

class _MiniMonth extends StatefulWidget {
  final int year;
  final int month;
  final String monthName;
  final AppStore store;
  final VoidCallback onTap;

  const _MiniMonth({
    required this.year,
    required this.month,
    required this.monthName,
    required this.store,
    required this.onTap,
  });

  @override
  State<_MiniMonth> createState() => _MiniMonthState();
}

class _MiniMonthState extends State<_MiniMonth> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final int daysInMonth = DateUtils.getDaysInMonth(widget.year, widget.month);
    final int offset = DateTime(widget.year, widget.month, 1).weekday - 1;
    final DateTime today = DateTime.now();
    final isCurrentMonth =
        today.year == widget.year && today.month == widget.month;

    // Görevi olan günler (renkli nokta için)
    final Map<int, Color> markedDays = {};
    for (int d = 1; d <= daysInMonth; d++) {
      final list = widget.store.tasksForDate(
        DateTime(widget.year, widget.month, d),
      );
      if (list.isNotEmpty) markedDays[d] = list.first.color;
    }

    Widget dayCell(int slot) {
      final d = slot - offset + 1;
      if (d < 1 || d > daysInMonth) return const SizedBox.shrink();
      final isToday = isCurrentMonth && today.day == d;
      final mark = markedDays[d];

      return Padding(
        padding: const EdgeInsets.all(1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isToday ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  color: isToday ? c.onAccent : c.inkDim,
                  fontSize: 9,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                ),
              ),
              // İşi olan gün, işin rengiyle noktalanır (bugün dahil).
              if (mark != null)
                Container(
                  width: 3.5,
                  height: 3.5,
                  margin: const EdgeInsets.only(top: 1.5),
                  decoration: BoxDecoration(
                    color: isToday ? c.onAccent : mark,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.radiusMd,
            border: Border.all(
              color: isCurrentMonth
                  ? c.accent.withValues(alpha: 0.45)
                  : (_hovered ? c.line : c.lineSoft),
            ),
            boxShadow: _hovered ? c.shadowMd : c.shadowSm,
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.monthName,
                    style: TextStyle(
                      color: isCurrentMonth ? c.accent : c.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (isCurrentMonth) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  children: List.generate(6, (week) {
                    return Expanded(
                      child: Row(
                        children: List.generate(
                          7,
                          (dow) => Expanded(child: dayCell(week * 7 + dow)),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
