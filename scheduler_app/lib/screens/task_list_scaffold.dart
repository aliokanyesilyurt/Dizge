import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: title, subtitle: subtitle),
            Expanded(
              child: tasks.isEmpty
                  ? EmptyState(icon: emptyIcon, text: emptyText)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
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
      floatingActionButton: FloatingActionButton(
        onPressed: onAdd,
        child: const Icon(Icons.add_rounded, size: 24),
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
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.lineSoft),
              ),
              child: Icon(icon, size: 26, color: c.inkFaint),
            ),
            const SizedBox(height: 18),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.inkDim,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.inkFaint,
                fontSize: 13,
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
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
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
              const SizedBox(width: 13),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (t.categoryName.isNotEmpty || t.scheduled)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          [
                            if (t.scheduled) t.timeString,
                            if (t.categoryName.isNotEmpty) t.categoryName,
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.trailing,
                style: TextStyle(
                  color: c.inkDim,
                  fontSize: 12,
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
