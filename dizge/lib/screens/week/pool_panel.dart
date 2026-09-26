import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/pool_labels.dart';
import '../../models/task.dart';
import '../../theme.dart';

/// "Kenarda Bekleyenler" — havuz paneli.
///
/// Takvimin sağında duran, daraltılabilir bir sütun. Havuza atılan iş
/// takvimden çekilir ama silinmez; burada, bir gün seçilmeyi bekler.
///
/// **Neden sağda bir sütun, açılır katman değil:** havuzun işi sürükleyip
/// bırakmak. Bir katman açıkken takvim görünmez, yani "şu işi perşembeye
/// koyayım" hareketi iki adıma bölünürdü. Sütun ikisini aynı anda gösteriyor.
/// Dar ekranda bu mümkün değil — orada panel bir modal sayfaya iniyor
/// (bkz. [PoolRail]).
///
/// Durum tutmaz: listeyi ve genişliği dışarıdan alır.
class PoolPanel extends StatelessWidget {
  const PoolPanel({
    super.key,
    required this.tasks,
    required this.onCollapse,
    required this.onOpenTask,
    required this.onRestore,
    this.onAdd,
    this.hover,
  });

  final List<Task> tasks;
  final VoidCallback onCollapse;
  final ValueChanged<Task> onOpenTask;

  /// İşi takvime geri koyar (eski gününe).
  final ValueChanged<Task> onRestore;

  /// Havuza doğrudan yeni iş yazar (plan H4). null ise giriş satırı çizilmez.
  final ValueChanged<String>? onAdd;

  /// Izgaradan sürüklenen blok panelin üstünde mi? Sürükleme sırasında
  /// ızgara yazıyor, panel dinliyor — aradaki ekranı yeniden çizmeden.
  final ValueListenable<bool>? hover;

  static const double width = 248;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SizedBox(
      width: width,
      child: ValueListenableBuilder<bool>(
        valueListenable: hover ?? const _AlwaysFalse(),
        builder: (context, isHovered, _) => AnimatedContainer(
          duration: Motion.fast,
          decoration: BoxDecoration(
            color: isHovered ? c.dropTarget : c.surface,
            border: Border(left: BorderSide(color: c.lineSoft)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(count: tasks.length, onCollapse: onCollapse),
              if (onAdd != null) PoolAddField(onAdd: onAdd!),
              Expanded(
                child: tasks.isEmpty
                    ? const _EmptyPool()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          S.sm,
                          S.xs,
                          S.sm,
                          S.lg,
                        ),
                        itemCount: tasks.length,
                        itemBuilder: (context, i) => _PoolCard(
                          task: tasks[i],
                          onTap: () => onOpenTask(tasks[i]),
                          onRestore: () => onRestore(tasks[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel daraltılmışken kalan ince şerit.
///
/// Tamamen gizlemek yerine şerit bırakılıyor: havuzda bekleyen işin sayısı
/// görünmezse havuz sessizce bir çöp kutusuna döner. Sayı hep göz ucunda.
class PoolRail extends StatelessWidget {
  const PoolRail({super.key, required this.count, required this.onExpand});

  final int count;
  final VoidCallback onExpand;

  static const double width = 44;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(left: BorderSide(color: c.lineSoft)),
        ),
        child: Tooltip(
          message: poolCountLabel(count),
          child: InkWell(
            onTap: onExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.md),
              child: Column(
                children: [
                  Icon(Icons.inbox_rounded, size: I.md, color: c.inkDim),
                  const SizedBox(height: S.sm),
                  if (count > 0)
                    ShadBadge(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.xs,
                        vertical: S.hair,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: T.dense,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: S.sm),
                  // Dikey başlık: 44px'e yatay yazı sığmıyor, ikon tek başına
                  // da "burası ne" sorusunu cevaplamıyor.
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          'KENARDA BEKLEYENLER',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: T.dense,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onCollapse});

  final int count;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.md, S.xs, S.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kPoolName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: T.body,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: S.xs),
            ShadBadge.secondary(
              padding: const EdgeInsets.symmetric(
                horizontal: S.xs,
                vertical: S.hair,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: T.dense,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          Tooltip(
            message: 'Paneli daralt',
            child: ShadButton.ghost(
              width: 30,
              height: 30,
              padding: EdgeInsets.zero,
              onPressed: onCollapse,
              child: const Icon(
                Icons.chevron_right_rounded,
                size: I.md,
                semanticLabel: 'Paneli daralt',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPool extends StatelessWidget {
  const _EmptyPool();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: I.lg, color: c.inkFaint),
          const SizedBox(height: S.sm),
          Text(
            'Burası boş',
            style: TextStyle(
              color: c.inkDim,
              fontSize: T.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: S.xs),
          Text(
            'Bu hafta yapman gerekenleri yaz, sonra günlere sürükle.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.inkFaint,
              fontSize: T.micro,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Havuzun başındaki tek satırlık giriş: yaz, Enter → havuza düşer.
///
/// Düzenleyici açılmıyor: havuza yazmak bir beyin boşaltması, her işte
/// kategori/saat sormak o hızı öldürürdü. Ayrıntı sonra, karta dokunarak.
/// Alan Enter'dan sonra odağı koruyor ki beş işi art arda yazmak beş
/// tıklama istemesin.
class PoolAddField extends StatefulWidget {
  const PoolAddField({super.key, required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  State<PoolAddField> createState() => _PoolAddFieldState();
}

class _PoolAddFieldState extends State<PoolAddField> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _text.text.trim();
    if (title.isEmpty) return;
    widget.onAdd(title);
    _text.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.sm, 0, S.sm, S.sm),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
        style: TextStyle(color: c.ink, fontSize: T.caption),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Havuza ekle…',
          hintStyle: TextStyle(color: c.inkFaint, fontSize: T.caption),
          prefixIcon: Icon(Icons.add_rounded, size: I.sm, color: c.inkDim),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: S.sm,
            vertical: S.sm,
          ),
        ),
      ),
    );
  }
}

/// Havuzdaki tek iş.
class _PoolCard extends StatelessWidget {
  const _PoolCard({
    required this.task,
    required this.onTap,
    required this.onRestore,
  });

  final Task task;
  final VoidCallback onTap;
  final VoidCallback onRestore;

  /// Bu kadar gündür bekleyen iş soluklaşır. Havuzun asıl riski çöp kutusuna
  /// dönmesi; solan kart "bunu ya yap ya sil" diyen sessiz bir uyarı.
  static const int _staleDays = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final waited = DateTime.now().difference(task.updatedAt).inDays;
    final stale = waited >= _staleDays;
    final style = c.event(task.color);

    final card = Opacity(
      opacity: stale ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: S.sm),
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: R.radiusSm,
          border: Border.all(color: style.edge, width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: R.radiusSm,
          // Izgaradaki blok sabit yükseklikte; buradaki kart içeriği kadar
          // uzuyor. `stretch` tek başına sonsuz yükseklik ister — şeridin
          // kartın boyunca inmesi için önce yükseklik ölçülmeli.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 3, child: ColoredBox(color: style.stripe)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(S.sm, S.sm, S.sm, S.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title.isEmpty ? 'Başlıksız' : task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: style.ink,
                            fontSize: T.caption,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: S.xs),
                        Text(
                          _waitLabel(waited),
                          style: TextStyle(
                            color: style.ink.withValues(alpha: 0.75),
                            fontSize: T.dense,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: '${task.title}, havuzda, ${_waitLabel(waited)}',
      excludeSemantics: true,
      child: ShadContextMenuRegion(
        items: [
          ShadContextMenuItem(
            leading: const Icon(Icons.event_available_outlined, size: I.sm),
            onPressed: onRestore,
            child: const Text('Takvime geri koy'),
          ),
          ShadContextMenuItem(
            leading: const Icon(Icons.edit_outlined, size: I.sm),
            onPressed: onTap,
            child: const Text('Düzenle'),
          ),
        ],
        // Uzun bas + sürükle, düz sürükleme değil: kartlar dikey kaydırılan bir
        // listede duruyor ve düz sürükleme her kaydırma denemesinde kartı
        // kaldırırdı. Izgaradaki blok da aynı dili konuşuyor — kullanıcı
        // hareketi bir kez öğreniyor.
        child: LongPressDraggable<Task>(
          data: task,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(task: task),
          childWhenDragging: Opacity(opacity: 0.3, child: card),
          // Sürükleme durumunu dışarı bildiren geri çağrılar kalktı (T2):
          // tek tüketicileri, ızgaranın ortasındaki "Bu hafta boş" kartını
          // bırakma sırasında yoldan çekmekti. Kart gidince yamanın da yeri
          // kalmadı — ızgaranın üstünde artık kesecek bir katman yok.
          child: GestureDetector(
            onTap: onTap,
            child: MouseRegion(cursor: SystemMouseCursors.click, child: card),
          ),
        ),
      ),
    );
  }

  /// "3 gündür bekliyor" — sayı değil cümle: rozet olsaydı neyin sayısı
  /// olduğu anlaşılmazdı.
  static String _waitLabel(int days) {
    if (days <= 0) return 'Bugün havuza alındı';
    if (days == 1) return 'Dünden beri bekliyor';
    return '$days gündür bekliyor';
  }
}

/// Dar ekranın havuzu: haftalık görünümün altında daraltılabilir şerit
/// (plan H6).
///
/// Yan panel 900 px'in altında takvimi yutuyor; havuz ayrı bir sekmedeyken de
/// sürükleyecek takvim yanında değil. Şerit ikisini aynı ekranda tutuyor:
/// kartlar yatayda dizili, uzun bas + gün başlığına ya da saate sürükle.
///
/// Kapalıyken yalnız "Havuz · 4" yazan ince bir çubuk kalıyor — sayı göz
/// ucunda, ızgaradan alınan yer bir satır.
class PoolDrawer extends StatelessWidget {
  const PoolDrawer({
    super.key,
    required this.tasks,
    required this.open,
    required this.onToggle,
    required this.onOpenTask,
    required this.onAdd,
  });

  final List<Task> tasks;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<Task> onOpenTask;

  /// Havuza yeni iş yazar (hızlı ekleme, "Havuz" seçili açılır).
  final VoidCallback onAdd;

  static const double barHeight = 40;
  static const double trayHeight = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: barHeight,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                child: Row(
                  children: [
                    Icon(Icons.inbox_rounded, size: I.sm, color: c.inkDim),
                    const SizedBox(width: S.sm),
                    Text(
                      tasks.isEmpty
                          ? kPoolName
                          : '$kPoolName · ${tasks.length}',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: T.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: 'Havuza ekle',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onAdd,
                        icon: Icon(
                          Icons.add_rounded,
                          size: I.md,
                          color: c.inkDim,
                          semanticLabel: 'Havuza ekle',
                        ),
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: I.md,
                      color: c.inkDim,
                      semanticLabel: open ? 'Havuzu kapat' : 'Havuzu aç',
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            SizedBox(
              height: trayHeight,
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        'Havuz boş — + ile yaz, sonra günlere sürükle.',
                        style: TextStyle(color: c.inkFaint, fontSize: T.micro),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.sm),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(width: S.sm),
                      itemBuilder: (context, i) => _DrawerChip(
                        task: tasks[i],
                        onTap: () => onOpenTask(tasks[i]),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Şeritteki tek iş: başlık ve renk şeridi, uzun basınca sürüklenir.
class _DrawerChip extends StatelessWidget {
  const _DrawerChip({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.event(task.color);

    final chip = Container(
      width: 132,
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: R.radiusSm,
        border: Border.all(color: style.edge, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: R.radiusSm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 3, child: ColoredBox(color: style.stripe)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    task.title.isEmpty ? 'Başlıksız' : task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: style.ink,
                      fontSize: T.micro,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Panel kartıyla aynı dil: uzun bas + sürükle. Şerit yatayda kaydığı
    // için düz sürükleme her kaydırmada kartı kaldırırdı.
    return Semantics(
      button: true,
      label: '${task.title}, havuzda',
      excludeSemantics: true,
      child: LongPressDraggable<Task>(
        data: task,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragFeedback(task: task),
        childWhenDragging: Opacity(opacity: 0.3, child: chip),
        child: GestureDetector(onTap: onTap, child: chip),
      ),
    );
  }
}

/// Panelden sürüklenen işin parmağın altındaki hâli.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.event(task.color);

    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.92,
        child: Container(
          width: 168,
          padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.sm),
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: R.radiusXs,
            border: Border.all(color: style.stripe, width: 1.2),
            boxShadow: c.shadowMd,
          ),
          child: Text(
            task.title.isEmpty ? 'Başlıksız' : task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.ink,
              fontSize: T.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// `hover` verilmediğinde kullanılan sabit değer — `ValueListenableBuilder`
/// null kabul etmiyor, testlerde panel tek başına kurulabilsin diye.
class _AlwaysFalse implements ValueListenable<bool> {
  const _AlwaysFalse();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
