import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../theme.dart';
import 'monthly_view_screen.dart';

class YearViewScreen extends ConsumerWidget {
  final int? year;
  const YearViewScreen({super.key, this.year});

  static const List<String> _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int year = this.year ?? DateTime.now().year;
    // Store'u izle: aylardan dönünce noktalar elle setState olmadan tazelenir.
    final store = ref.watch(appStoreProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('$year',
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontSize: 16,
            )),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(14),
          // Sabit 3 sütun geniş ekranda ayları aşırı geriyordu; genişliğe göre
          // sütun sayısı belirlensin ki webde de derli toplu dursun.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 250,
            childAspectRatio: 0.92,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            return _MiniMonth(
              year: year,
              month: index + 1,
              monthName: _months[index],
              store: store,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MonthlyViewScreen(initialMonth: index),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final int daysInMonth = DateUtils.getDaysInMonth(year, month);
    final int offset = DateTime(year, month, 1).weekday - 1;
    final DateTime today = DateTime.now();

    // Görevi olan günler (renkli nokta için)
    final Map<int, Color> markedDays = {};
    for (int d = 1; d <= daysInMonth; d++) {
      final list = store.tasksForDate(DateTime(year, month, d));
      if (list.isNotEmpty) markedDays[d] = list.first.color;
    }

    Widget dayCell(int slot) {
      final d = slot - offset + 1;
      if (d < 1 || d > daysInMonth) return const SizedBox.shrink();
      final isToday =
          today.year == year && today.month == month && today.day == d;
      final mark = markedDays[d];
      final isWeekend = DateTime(year, month, d).weekday >= 6;

      // Her gün, aylık görünümdeki gibi yumuşak köşeli kendi kutusunda.
      return Padding(
        padding: const EdgeInsets.all(1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isToday
                ? AppColors.blue
                : (isWeekend ? AppColors.gridWeekend : AppColors.gridDay),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isToday ? AppColors.blue : AppColors.lineSoft,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  color: isToday
                      ? Colors.white
                      : (isWeekend ? AppColors.pink : AppColors.ink),
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
                    color: isToday ? Colors.white : mark,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.lineSoft, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthName,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
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
    );
  }
}
