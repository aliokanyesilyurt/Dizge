import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme.dart';

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.inkFaint,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.lineSoft, height: 1),
            Expanded(
              child: tasks.isEmpty
                  ? _Empty(icon: emptyIcon, text: emptyText)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
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
        child: const Icon(Icons.add, size: 22),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppColors.inkFaint),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkFaint,
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
    final t = widget.task;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.hover : AppColors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.lineSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 26,
                decoration: BoxDecoration(
                  color: t.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (t.categoryName.isNotEmpty || t.scheduled)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            if (t.scheduled) t.timeString,
                            if (t.categoryName.isNotEmpty) t.categoryName,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.inkFaint,
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
                style: const TextStyle(
                  color: AppColors.inkDim,
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
