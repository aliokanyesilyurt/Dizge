import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
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
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosProvider);
    final open = todos.where((t) => !t.isDoneOn(t.date)).length;

    return TaskListScaffold(
      title: 'Yapılacaklar',
      subtitle: '$open açık · ${todos.length} toplam',
      emptyIcon: Icons.checklist_rounded,
      emptyText: 'Yapılacak iş yok.\nTek günlük bir iş ekleyince burada görünür.',
      tasks: todos,
      trailingTextFor: (t) => '${t.date.day} ${_months[t.date.month - 1]}',
      onTap: (t) => showTaskEditor(context, date: t.date, existing: t),
      onAdd: () => showQuickAdd(context, date: Task.dayKey(DateTime.now())),
    );
  }
}
