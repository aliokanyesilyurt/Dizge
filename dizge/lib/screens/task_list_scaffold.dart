import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/content_column.dart';
import '../widgets/owner_avatar.dart';
import '../widgets/task_check.dart';
import 'section_header.dart';

/// Liste satırının sağ ucundaki tek eylem.
///
/// Ayrı bir tür, çünkü üç parçası (ikon, etiket, çağrı) hep birlikte anlamlı:
/// üçünü ayrı alan olarak taşımak, ikisi verilip biri unutulan bir satırın
/// derlenmesine izin verirdi.
@immutable
class TaskRowAction {
  const TaskRowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;

  /// Hem fare ipucu hem ekran okuyucu etiketi. Satırda yazılı görünmüyor.
  final String label;

  final VoidCallback onPressed;
}

/// Rutinler ve Yapılacaklar ekranlarının paylaştığı liste düzeni.
class TaskListScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData emptyIcon;
  final String emptyText;
  final List<Task> tasks;

  /// Satırın sağında gösterilecek metin (tekrar özeti, tarih vb.).
  final String Function(Task) trailingTextFor;
  final ValueChanged<Task> onTap;

  /// Kayan ekleme düğmesi. Null ise hiç çizilmez — her listenin "yeni" diye
  /// bir karşılığı yok (havuz, var olan işlerin bekleme yeri).
  final VoidCallback? onAdd;

  /// Satırın sağ ucundaki tek eylem. Null dönen satırda düğme çıkmaz.
  ///
  /// Tek eylem, çünkü liste satırı bir menü değil: "bugün iptal" ya da
  /// "takvime geri koy" — ekranın o listede yapılabilecek en doğal ikinci
  /// hareketi. Üçüncüsü gerekiyorsa yeri satıra dokunup açılan düzenleyici.
  final TaskRowAction? Function(Task)? actionFor;

  /// Satır başındaki onay kutusunun durumu. Null ise kutu hiç çizilmez —
  /// tamamlama kavramı olmayan bir liste bu iskeleti kullanabilsin diye.
  final bool Function(Task)? isDone;

  /// Kutuya dokunulduğunda çağrılır. [isDone] varsa bu da olmalı.
  final ValueChanged<Task>? onToggleDone;

  /// Kutunun **hangi güne** baktığını söyleyen kısa ek ("bugün").
  ///
  /// Rutinlerde zorunlu: tekrar eden bir işin yanındaki tek kutu, hangi günü
  /// kastettiğini söylemezse "bu rutini tamamen bitirdim" diye okunur.
  /// Yapılacaklarda gereksiz — orada işin zaten tek bir günü var.
  final String? checkScopeLabel;

  const TaskListScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emptyIcon,
    required this.emptyText,
    required this.tasks,
    required this.trailingTextFor,
    required this.onTap,
    this.onAdd,
    this.actionFor,
    this.isDone,
    this.onToggleDone,
    this.checkScopeLabel,
  }) : assert(
         (isDone == null) == (onToggleDone == null),
         'onay kutusu ya tam bağlanır ya hiç çizilmez',
       );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: title, subtitle: subtitle),
              Expanded(
                child: tasks.isEmpty
                    ? EmptyState(icon: emptyIcon, text: emptyText)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          S.gutter,
                          S.xs,
                          S.gutter,
                          S.fabGap,
                        ),
                        itemCount: tasks.length,
                        itemBuilder: (_, i) => _Row(
                          task: tasks[i],
                          trailing: trailingTextFor(tasks[i]),
                          onTap: () => onTap(tasks[i]),
                          done: isDone?.call(tasks[i]),
                          onToggleDone: onToggleDone == null
                              ? null
                              : () => onToggleDone!(tasks[i]),
                          checkScopeLabel: checkScopeLabel,
                          action: actionFor?.call(tasks[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: onAdd == null
          ? null
          : FloatingActionButton(
              onPressed: onAdd,
              child: const Icon(Icons.add_rounded, size: I.lg),
            ),
    );
  }
}

/// Boş durum: ikonu bir daire içinde yumuşatılmış, metni ortalanmış.
///
/// Uygulama genelinde tek bir boş-durum dili olsun diye paylaşılıyor.
/// [title] verilirse iki kademeli okunur: kalın bir tespit, altında soluk bir
/// yönlendirme. Verilmezse [text] tek başına yeterlidir.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String text;

  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              // Sayfada tek başına duran simge: daire [I.hero], içindeki ikon
              // [I.lg]. İkisi de ölçekten okunur ki boş durum, dolu hâlin
              // ritminden kopmasın.
              width: I.hero,
              height: I.hero,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.lineSoft),
              ),
              child: Icon(icon, size: I.lg, color: c.inkFaint),
            ),
            const SizedBox(height: S.lg),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.inkDim,
                  fontSize: T.strong,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: S.xs),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.inkFaint,
                fontSize: T.body,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  final Task task;
  final String trailing;
  final VoidCallback onTap;

  /// Null ise satırda onay kutusu yok.
  final bool? done;
  final VoidCallback? onToggleDone;
  final String? checkScopeLabel;

  /// Satırın sağ ucundaki tek eylem düğmesi. Null ise çizilmez.
  final TaskRowAction? action;

  const _Row({
    required this.task,
    required this.trailing,
    required this.onTap,
    this.done,
    this.onToggleDone,
    this.checkScopeLabel,
    this.action,
  });

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.task;
    final done = widget.done;
    final action = widget.action;

    // Kutunun kapsamı satırda yazıyor ("bugün tamam"). Rutinlerde bu bilgi
    // olmadan kutu, hangi günü kastettiğini söyleyemez.
    final scope = widget.checkScopeLabel;
    final meta = [
      if (t.scheduled) t.timeString,
      if (t.categoryName.isNotEmpty) categoryLabel(t.categoryName),
      if (scope != null && done != null) '$scope ${done ? 'tamam' : 'açık'}',
    ];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          margin: const EdgeInsets.only(bottom: S.sm),
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.lg, S.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: R.radiusMd,
            border: Border.all(color: _hovered ? c.line : c.lineSoft),
            boxShadow: _hovered ? c.shadowMd : c.shadowSm,
          ),
          child: Row(
            children: [
              // Kategori rengi ince bir dikey vuruş olarak; kutu değil, aksan.
              Container(
                width: 3,
                height: 30,
                decoration: BoxDecoration(
                  color: t.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: S.md),
              // Onay kutusu şeridin hemen sağında: göz soldan tarıyor ve
              // "bunu yaptım mı" sorusu başlığı okumadan önce geliyor.
              if (done != null) ...[
                TaskCheck(
                  done: done,
                  onToggle: widget.onToggleDone!,
                  label: t.title,
                ),
                const SizedBox(width: S.sm),
              ],
              // Sahiplik rozeti (Y4.4d). Burada **satır başında**: listede
              // yer var ve göz zaten soldan tarıyor, "kimin işi" sorusu
              // başlığı okumadan yanıtlanıyor. Kişisel bağlamda gizli.
              if (t.ownerId != null) ...[
                OwnerAvatar(ownerId: t.ownerId, size: I.sm),
                const SizedBox(width: S.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: done == true ? c.inkDim : c.ink,
                        fontSize: T.strong,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        // Üstü çizili: tamamlanmışlık yalnız kutunun rengine
                        // bırakılmıyor (WCAG 1.4.1).
                        decoration: done == true
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: c.inkFaint,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: S.xs),
                        child: Text(
                          meta.join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: T.caption,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: S.sm),
              Text(
                widget.trailing,
                style: TextStyle(
                  color: c.inkDim,
                  fontSize: T.caption,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Eylem en sağda ve **yalnız** ikon: etiketi ipucunda ve ekran
              // okuyucuda duruyor. Satırın asıl işi başlığı okutmak; ikinci
              // bir kelime, birinciyle yarışırdı.
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(left: S.xs),
                  child: IconButton(
                    onPressed: action.onPressed,
                    icon: Icon(action.icon, size: I.sm),
                    color: c.inkFaint,
                    tooltip: action.label,
                    // Yoğun: varsayılan 48'lik hedef satırı büyütüyordu.
                    // 40x40 hâlâ parmakla rahat vurulur.
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
