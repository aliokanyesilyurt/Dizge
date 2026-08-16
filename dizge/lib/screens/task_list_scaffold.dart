import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/content_column.dart';
import '../widgets/owner_avatar.dart';
import 'section_header.dart';

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
  final VoidCallback onAdd;

  const TaskListScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emptyIcon,
    required this.emptyText,
    required this.tasks,
    required this.trailingTextFor,
    required this.onTap,
    required this.onAdd,
  });

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
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
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

  const _Row({required this.task, required this.trailing, required this.onTap});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.task;

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
                        color: c.ink,
                        fontSize: T.strong,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (t.categoryName.isNotEmpty || t.scheduled)
                      Padding(
                        padding: const EdgeInsets.only(top: S.xs),
                        child: Text(
                          [
                            if (t.scheduled) t.timeString,
                            if (t.categoryName.isNotEmpty) categoryLabel(t.categoryName),
                          ].join('  ·  '),
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
            ],
          ),
        ),
      ),
    );
  }
}
