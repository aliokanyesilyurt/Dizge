import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/habit.dart';
import '../../theme.dart';

/// Ana ekranın üstündeki günlük tik şeridi.
///
/// Alışkanlıklar bugüne kadar yalnız kendi ekranındaydı: tik atmak için
/// takvimden çıkıp başka bir bölüme gitmek gerekiyordu. Zincir psikolojisi
/// günlük temasa dayanır; günde bir kez bile açılmayan bir ekranda yaşayamaz.
/// Şerit yeni bir veri modeli getirmiyor — var olan [Habit]'i göz hizasına
/// taşıyor.
///
/// **Her zaman bugünü işaretler.** Hafta sayfaları ileri geri kaysa da şerit
/// yerinde ve aynı günde kalır; bu yüzden [WeekViewScreen] içinde `PageView`'in
/// *dışında* durur ve başında "BUGÜN" etiketi taşır. Geçen haftaya bakarken
/// atılan bir tikin sessizce oraya yazılması, seriyi yalan söyleten türden bir
/// sürpriz olurdu.
///
/// Durum tutmaz: gördüğü listeyi ve günü parametre alır, tiki geri bildirir.
class DailyHabitStrip extends StatelessWidget {
  const DailyHabitStrip({
    super.key,
    required this.habits,
    required this.day,
    required this.onToggle,
  });

  final List<Habit> habits;

  /// Tikin yazılacağı gün — çağıran her zaman bugünü verir, ama test ve
  /// ileride "geçmiş günü tamamla" akışı için parametre.
  final DateTime day;

  final ValueChanged<Habit> onToggle;

  @override
  Widget build(BuildContext context) {
    // Alışkanlık yoksa şerit hiç yok: boş bir kutu da olsa ana ekranda yer
    // kaplayan her şey bir bedel, karşılığı olmayan hiçbir şey durmamalı.
    if (habits.isEmpty) return const SizedBox.shrink();

    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 0, S.md, S.sm),
      child: Row(
        children: [
          Padding(
            // Çiplerin gövdesiyle aynı optik hatta otursun.
            padding: const EdgeInsets.only(right: S.sm, bottom: S.hair),
            child: Text(
              'BUGÜN',
              style: TextStyle(
                color: c.inkFaint,
                fontSize: T.dense,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            // Alışkanlık sayısı kullanıcının elinde; on tanesi de olabilir.
            // Sarmak yerine yatay kaydırma: şerit tek satır kalsın, ızgaranın
            // yüksekliğini yemesin.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final habit in habits)
                    Padding(
                      padding: const EdgeInsets.only(right: S.sm),
                      child: _HabitChip(
                        habit: habit,
                        day: day,
                        onTap: () => onToggle(habit),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek alışkanlığın tik çipi.
class _HabitChip extends StatelessWidget {
  const _HabitChip({
    required this.habit,
    required this.day,
    required this.onTap,
  });

  final Habit habit;
  final DateTime day;
  final VoidCallback onTap;

  /// Uzun başlık şeridi ele geçirmesin; ötesi kırpılır, tamamı ipucunda.
  static const double _maxTitleWidth = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = habit.isDoneOn(day);
    final style = c.tag(habit.color, selected: true);

    return Semantics(
      button: true,
      toggled: done,
      label: _semanticLabel(),
      excludeSemantics: true,
      child: Tooltip(
        message: habit.title,
        child: InkWell(
          onTap: onTap,
          borderRadius: R.radiusPill,
          hoverColor: c.hover,
          focusColor: c.hover,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: S.sm),
            decoration: BoxDecoration(
              color: done ? style.fill : Colors.transparent,
              borderRadius: R.radiusPill,
              // İşaretsiz çip yalnız çizgiyle var olur: yedi tanesi yan yana
              // dururken zemin de renkli olsaydı şerit ızgaradan daha gürültülü
              // olurdu.
              border: Border.all(color: done ? style.fill : c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_rounded : Icons.circle_outlined,
                  size: 14,
                  color: done ? style.text : habit.color,
                ),
                const SizedBox(width: S.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxTitleWidth),
                  child: Text(
                    habit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // İşaretsizken `inkDim`: `inkFaint` bu boyutta AA'nın
                      // altında kalıyor (D4'te saat sütununda ölçüldü).
                      color: done ? style.text : c.inkDim,
                      fontSize: T.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_progressLabel() case final label?) ...[
                  const SizedBox(width: S.xs),
                  _StreakBadge(label: label, isDaily: _isDaily),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isDaily => habit.cadence == HabitCadence.daily;

  /// Rozetin yazısı; gösterilecek bir şey yoksa null.
  ///
  /// Günlük ritimde seri (kaç gün üst üste), haftalıkta bu haftanın ilerlemesi
  /// (2/3). İkisi aynı sayı değil: haftada 3 hedefi olan birine "1 gün seri"
  /// demek, hedefin kendisini görünmez kılardı.
  String? _progressLabel() {
    if (_isDaily) {
      final streak = habit.currentStreak;
      return streak > 0 ? '$streak' : null;
    }
    return '${habit.doneInWeekOf(day)}/${habit.targetPerWeek}';
  }

  String _semanticLabel() {
    final buffer = StringBuffer(habit.title);
    buffer.write(habit.isDoneOn(day) ? ', bugün yapıldı' : ', bugün yapılmadı');
    if (_isDaily) {
      final streak = habit.currentStreak;
      if (streak > 0) buffer.write(', $streak günlük seri');
    } else {
      buffer.write(
        ', bu hafta ${habit.doneInWeekOf(day)} / ${habit.targetPerWeek}',
      );
    }
    return buffer.toString();
  }
}

/// Seri / haftalık ilerleme rozeti.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.label, required this.isDaily});

  final String label;
  final bool isDaily;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return ShadBadge.secondary(
      padding: const EdgeInsets.symmetric(horizontal: S.xs, vertical: S.hair),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDaily) ...[
            // Alev yalnız günlük seride: haftalık ilerleme "2/3" zaten kendi
            // kendini anlatıyor, ikinci bir sembol gürültü olurdu.
            Icon(
              Icons.local_fire_department_rounded,
              size: 11,
              color: c.warning,
            ),
            const SizedBox(width: S.hair),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: T.dense,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
