import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pool_labels.dart';
import '../data/app_store.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/undo_toast.dart';
import 'task_list_scaffold.dart';

/// Kenarda bekleyen işler — havuzun ikinci kapısı.
///
/// Havuz bugüne kadar yalnız haftalık ızgaranın sağ kenarındaydı ve **boşken
/// hiç görünmüyordu**: hiç kullanmamış biri için ekranda sıfır iz vardı.
/// "Havuzun nerede olduğu belli değil" şikâyetinin sebebi buydu — özelliğin
/// eksikliği değil, keşfedilemezliği (plan K4).
///
/// Haftalık şerit yerinde kalıyor: sürükle-bırak hedefi olarak orada olması
/// gerekiyor. Değişen tek şey, havuzun artık kenar çubuğunda da bir satırı
/// olması.
class PoolScreen extends ConsumerWidget {
  const PoolScreen({super.key});

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
    final pooled = ref.watch(poolProvider);
    final store = ref.read(appStoreProvider);

    return TaskListScaffold(
      title: kPoolName,
      subtitle: pooled.isEmpty
          ? 'takvimden çekilen işler burada birikir'
          : '${pooled.length} iş bekliyor · en uzun bekleyen üstte',
      emptyIcon: Icons.inbox_rounded,
      // Boş durum bir kusur değil, bir tarif: kullanıcı buraya işin nasıl
      // geldiğini öğrenmek için de girer.
      emptyText:
          'Havuz boş.\nBir işi "Bugün iptal" ile takvimden '
          'çekince burada birikir — silinmez, unutulmaz.',
      tasks: pooled,
      // Havuzdaki iş hangi günden çekildiyse o gün yazıyor: geri koyarken
      // "ne zamandı bu" sorusunun cevabı satırda dursun.
      trailingTextFor: (t) => '${t.date.day} ${_months[t.date.month - 1]}',
      // Onay kutusu yok: kenara alınmış bir işi "yaptım" diye işaretlemek,
      // önce takvime dönmesi gereken bir işi atlamak olurdu. Havuzun tek
      // eylemi geri koymak.
      actionFor: (t) => TaskRowAction(
        icon: Icons.event_available_rounded,
        label: 'Takvime geri koy',
        onPressed: () {
          store.pullFromPool(t);
          offerUndo(context, 'Takvime kondu', () => store.moveToPool(t));
        },
      ),
      onTap: (t) => showTaskEditor(context, date: t.date, existing: t),
      // Kayan "yeni" düğmesi yok: havuz yeni iş kurulan yer değil, var olan
      // işin bekleme yeri. İş takvimde doğar, buraya çekilir.
    );
  }
}
