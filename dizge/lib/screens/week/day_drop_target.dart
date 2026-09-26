/// Bir güne — saatine değil — bırakma hedefi (plan H5).
library;

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme.dart';

/// Gün başlığını ve saatsiz şeridin gün sütununu bırakma hedefi yapar.
///
/// Saat ızgarasına bırakılan iş bir saate çakılıyor; buraya bırakılan iş
/// yalnız **günü** alıyor. Havuzdan gelen iş için esnekliğin ta kendisi:
/// "perşembe yapacağım" demek "perşembe 14:00'te" demek değil.
///
/// Neyi kabul ettiği burada, ne yapılacağı ekranda: hedef yalnız "şu iş şu
/// güne bırakıldı" der.
class DayDropTarget extends StatelessWidget {
  const DayDropTarget({
    super.key,
    required this.day,
    required this.onDrop,
    required this.child,
  });

  final DateTime day;
  final void Function(Task task, DateTime day) onDrop;
  final Widget child;

  /// Rutin gelmez: haftalık rutini bir güne çekmek bütün haftaları değiştirir
  /// ve bunun yolu ızgaradaki blok. Kendi gününe bırakılan saatsiz iş de
  /// reddedilir — değişecek bir şey yok.
  static bool accepts(Task task, DateTime day) {
    if (task.isRoutine) return false;
    if (task.inPool || task.scheduled) return true;
    return Task.dayKey(task.date) != Task.dayKey(day);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => accepts(details.data, day),
      onAcceptWithDetails: (details) => onDrop(details.data, day),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          // Izgaradaki bırakma sütunuyla aynı ton.
          color: candidates.isEmpty ? Colors.transparent : c.dropTarget,
          borderRadius: R.radiusSm,
        ),
        child: child,
      ),
    );
  }
}
