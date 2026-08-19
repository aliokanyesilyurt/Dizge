/// Editörün "Tekrar" satırı: rutinin hangi günlerde döneceği ve ne zaman
/// biteceği.
///
/// Durum sayfada kalıyor; bu widget bir [Repeat] alıp değişeni geri veriyor.
library;

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme.dart';
import 'editor_controls.dart';
import 'property_row.dart';

class RepeatRow extends StatelessWidget {
  const RepeatRow({
    super.key,
    required this.date,
    required this.repeat,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });

  /// Rutinin başladığı gün: "Haftanın Günleri" ilk seçildiğinde varsayılan
  /// gün buradan geliyor, bitiş takvimi de buradan başlıyor.
  final DateTime date;
  final Repeat repeat;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<Repeat> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PropertyRow(
      icon: Icons.autorenew_rounded,
      label: 'Tekrar',
      value: repeat.describe(date),
      open: open,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChipTile(
                text: 'Her Gün',
                selected: repeat.type == RepeatType.daily,
                onTap: () => onChanged(repeat.copyWith(type: RepeatType.daily)),
              ),
              ChoiceChipTile(
                text: 'Haftanın Günleri',
                selected: repeat.type == RepeatType.weekly,
                onTap: () => onChanged(
                  repeat.copyWith(
                    type: RepeatType.weekly,
                    weekdays: repeat.weekdays.isEmpty
                        ? {date.weekday}
                        : repeat.weekdays,
                  ),
                ),
              ),
              ChoiceChipTile(
                text: 'Her Ay',
                selected: repeat.type == RepeatType.monthly,
                onTap: () =>
                    onChanged(repeat.copyWith(type: RepeatType.monthly)),
              ),
            ],
          ),
          if (repeat.type == RepeatType.weekly) ...[
            const SizedBox(height: S.md),
            Row(
              spacing: 6,
              children: List.generate(7, (i) {
                final day = i + 1;
                final sel = repeat.weekdays.contains(day);
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final next = {...repeat.weekdays};
                      sel ? next.remove(day) : next.add(day);
                      onChanged(repeat.copyWith(weekdays: next));
                    },
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? c.accentSoft : c.surface,
                        borderRadius: R.radiusSm,
                        border: Border.all(color: sel ? c.accent : c.line),
                      ),
                      child: Text(
                        Repeat.weekdayShort[i],
                        style: TextStyle(
                          fontSize: T.caption,
                          fontWeight: FontWeight.w600,
                          color: sel ? c.navActiveInk : c.inkDim,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: S.md),
          Row(
            children: [
              Icon(Icons.event_busy_rounded, size: I.sm, color: c.inkFaint),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(
                  repeat.until == null
                      ? 'Bitiş yok — süresiz tekrar eder'
                      : 'Bitiş: ${fmtDate(repeat.until!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.inkDim, fontSize: T.body),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (repeat.until != null) {
                    onChanged(repeat.copyWith(clearUntil: true));
                    return;
                  }
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date.add(const Duration(days: 30)),
                    firstDate: date,
                    lastDate: DateTime(date.year + 5),
                  );
                  if (picked != null) onChanged(repeat.copyWith(until: picked));
                },
                child: Text(repeat.until == null ? 'Bitiş ekle' : 'Kaldır'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
