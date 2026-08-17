import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../widgets/task_editor_sheet.dart';
import 'task_list_scaffold.dart';

/// Tekrar eden işler (Repeat.isRoutine), takvimden bağımsız düz liste.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);

    return TaskListScaffold(
      title: 'Rutinler',
      subtitle: '${routines.length} tekrar eden iş',
      emptyIcon: Icons.repeat_rounded,
      // Ayrım metinde de duruyor (plan §Zc): rutin sürekli ve saatli,
      // alışkanlık süreksiz ve saatsiz. Boş durum, iş yanlış ekrana
      // konmadan önce okunan tek yer.
      emptyText:
          'Henüz rutin yok.\nSaati belli, düzenli tekrar eden işler burada. '
          'Saat gerektirmeyen bir şeyse yeri Alışkanlıklar.',
      tasks: routines,
      trailingTextFor: (t) => t.repeat.describe(t.date),
      onTap: (t) => showTaskEditor(context, date: t.date, existing: t),
      // Rutin, hızlı eklemede değil tam editörde kurulur (tekrar kuralı seçimi
      // gerekir), bu yüzden buradan doğrudan editör açılıyor.
      onAdd: () => showTaskEditor(context, date: DateTime.now()),
    );
  }
}
