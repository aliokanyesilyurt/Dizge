import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../widgets/cancel_action.dart';
import '../widgets/task_editor_sheet.dart';
import 'task_list_scaffold.dart';

/// Tekrar eden işler (Repeat.isRoutine), takvimden bağımsız düz liste.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    final store = ref.read(appStoreProvider);

    // Liste takvimden bağımsız ama onay kutusu olamaz: tekrar eden bir iş
    // "tamamen bitmiş" olmaz, bir **günü** biter. O gün burada bugün.
    final today = Task.dayKey(DateTime.now());
    final doneToday = routines.where((t) => t.isDoneOn(today)).length;

    return TaskListScaffold(
      title: 'Rutinler',
      subtitle: '${routines.length} tekrar eden iş · bugün $doneToday tamam',
      emptyIcon: Icons.repeat_rounded,
      // Ayrım metinde de duruyor (plan §Zc): rutin sürekli ve saatli,
      // alışkanlık süreksiz ve saatsiz. Boş durum, iş yanlış ekrana
      // konmadan önce okunan tek yer.
      emptyText:
          'Henüz rutin yok.\nSaati belli, düzenli tekrar eden işler burada. '
          'Saat gerektirmeyen bir şeyse yeri Alışkanlıklar.',
      tasks: routines,
      trailingTextFor: (t) => t.repeat.describe(t.date),
      isDone: (t) => t.isDoneOn(today),
      onToggleDone: (t) => store.setTaskDone(t, today, !t.isDoneOn(today)),
      // Kutunun kapsamı satırda yazsın: "bugün açık" / "bugün tamam".
      checkScopeLabel: 'bugün',
      // Rutinde iptal = bugünü atlamak. Yapılacaklar ekranındaki satırla
      // aynı ikon, aynı etiket: iki listede aynı düğmenin iki farklı adı
      // olsaydı, ayrımı öğrenmek kullanıcının işi olurdu (plan K3).
      actionFor: (t) {
        final cancelled = store.isCancelledOn(t, today);
        return TaskRowAction(
          icon: cancelIcon(cancelled),
          label: cancelLabel(cancelled),
          onPressed: () =>
              toggleCancelOn(context, store, t, today, source: 'list'),
        );
      },
      onTap: (t) => showTaskEditor(context, date: t.date, existing: t),
      // Rutin, hızlı eklemede değil tam editörde kurulur (tekrar kuralı seçimi
      // gerekir), bu yüzden buradan doğrudan editör açılıyor.
      onAdd: () => showTaskEditor(context, date: DateTime.now()),
    );
  }
}
