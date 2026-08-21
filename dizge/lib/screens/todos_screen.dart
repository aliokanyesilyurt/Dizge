import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../widgets/cancel_action.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import 'task_list_scaffold.dart';

/// Tek günlük işler (rutin olmayanlar), tarihe göre sıralı düz liste.
///
/// Artık [todosProvider]'ı izliyor: başka bir ekranda (ör. haftalık ızgarada
/// sürükleyerek) yapılan değişiklik buraya kendiliğinden yansır.
class TodosScreen extends ConsumerWidget {
  const TodosScreen({super.key});

  static const _months = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosProvider);
    final open = todos.where((t) => !t.isDoneOn(t.date)).length;
    final store = ref.read(appStoreProvider);

    return TaskListScaffold(
      title: 'Yapılacaklar',
      subtitle: '$open açık · ${todos.length} toplam',
      emptyIcon: Icons.checklist_rounded,
      emptyText:
          'Yapılacak iş yok.\nTek günlük bir iş ekleyince burada görünür.',
      tasks: todos,
      trailingTextFor: (t) => '${t.date.day} ${_months[t.date.month - 1]}',
      // Tek günlük işin günü belli: kutu o günü işaretler, ayrıca söylemeye
      // gerek yok (bkz. [TaskListScaffold.checkScopeLabel]).
      isDone: (t) => t.isDoneOn(t.date),
      onToggleDone: (t) => store.setTaskDone(t, t.date, !t.isDoneOn(t.date)),
      // Satırın ikinci hareketi: işi o gün için iptal etmek. Tek günlük işte
      // bu "havuza al" demek ama etiket her ekranda aynı (plan K3) —
      // kullanıcı rutin/tek-günlük ayrımını bilmek zorunda değil.
      actionFor: (t) {
        final cancelled = store.isCancelledOn(t, t.date);
        return TaskRowAction(
          icon: cancelIcon(cancelled),
          label: cancelLabel(cancelled),
          onPressed: () =>
              toggleCancelOn(context, store, t, t.date, source: 'list'),
        );
      },
      onTap: (t) => showTaskEditor(context, date: t.date, existing: t),
      onAdd: () => showQuickAdd(context, date: Task.dayKey(DateTime.now())),
    );
  }
}
