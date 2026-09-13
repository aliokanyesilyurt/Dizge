import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation_controller.dart';
import '../data/app_store.dart';
import '../theme.dart';

/// 12 aylık ızgara.
///
/// Yıl artık **ekranın kendi durumu**: eskiden her kuruluşta
/// `DateTime.now().year` okunuyordu, yani geçen yılın Mart'ına bakmanın hiçbir
/// yolu yoktu. [year] yalnız açılış yılını veriyor; başlıktaki oklar oradan
/// devam ediyor.
class YearViewScreen extends ConsumerStatefulWidget {
  /// Açılış yılı. Boşsa içinde bulunulan yıl.
  final int? year;
  const YearViewScreen({super.key, this.year});

  @override
  ConsumerState<YearViewScreen> createState() => _YearViewScreenState();
}

class _YearViewScreenState extends ConsumerState<YearViewScreen> {
  late int _year = widget.year ?? DateTime.now().year;

  void _shift(int years) => setState(() => _year += years);

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
  Widget build(BuildContext context) {
    final c = context.colors;
    final year = _year;
    // Store'u izle: aylardan dönünce noktalar elle setState olmadan tazelenir.
    final store = ref.watch(appStoreProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        centerTitle: true,
        // Oklar başlığın iki yanında: yıl, ikisinin arasında değişen tek şey.
        // Ayrı bir araç çubuğuna konsalardı hangi sayıyı değiştirdikleri
        // okunmazdı.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _YearArrow(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Önceki yıl',
              onTap: () => _shift(-1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.sm),
              child: Text(
                '$year',
                style: TextStyle(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: T.title,
                ),
              ),
            ),
            _YearArrow(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Sonraki yıl',
              onTap: () => _shift(1),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(S.lg),
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
              onTap: () => ref
                  .read(navigationProvider.notifier)
                  .openMonth(DateTime(year, index + 1)),
            );
          },
        ),
      ),
    );
  }
}

/// Başlıktaki yıl oku. Sessiz: yıl değiştirmek gezinme, eylem değil.
class _YearArrow extends StatelessWidget {
  const _YearArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: I.md,
      icon: Icon(icon, color: context.colors.inkDim),
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

    final Map<int, Color> markedDays = {};
    for (int d = 1; d <= daysInMonth; d++) {
      var list = widget.store.tasksForDate(
        DateTime(widget.year, widget.month, d),
      );
      if (widget.store.activeGroupId != '*all*') {
        list = list.where((t) => t.groupId == widget.store.activeGroupId).toList();
      }
      if (list.isNotEmpty) markedDays[d] = list.first.color;
    }

    Widget dayCell(int slot) {
      final d = slot - offset + 1;
      if (d < 1 || d > daysInMonth) return const SizedBox.shrink();
      final isToday = isCurrentMonth && today.day == d;
      final mark = markedDays[d];

      return Padding(
        padding: const EdgeInsets.all(S.hair),
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
                  fontSize: T.dense,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                ),
              ),
              // İşi olan gün, işin rengiyle noktalanır (bugün dahil).
              if (mark != null)
                Container(
                  width: 3.5,
                  height: 3.5,
                  margin: const EdgeInsets.only(top: S.hair),
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
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.md, S.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.monthName,
                    style: TextStyle(
                      color: isCurrentMonth ? c.accent : c.ink,
                      fontSize: T.caption,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (isCurrentMonth) ...[
                    const SizedBox(width: S.xs),
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
              const SizedBox(height: S.sm),
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
