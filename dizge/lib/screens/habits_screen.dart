import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/habit.dart';
import '../models/task.dart' show kTaskColors;
import '../theme.dart';
import '../widgets/content_column.dart';
import '../widgets/habit_heatmap.dart';
import 'section_header.dart';
import 'task_list_scaffold.dart' show EmptyState;

/// Alışkanlık takibi: her alışkanlık için güncel seri (streak), tamamlanma
/// oranı ve GitHub tarzı ısı haritası. Esnek ritim (her gün / haftada N) destekli.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final habits = ref.watch(habitsProvider);
    final store = ref.read(appStoreProvider);
    final activeStreaks = habits.where((h) => h.currentStreak > 0).length;

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddHabit(context, store),
        child: const Icon(Icons.add_rounded, size: I.lg),
      ),
      body: SafeArea(
        child: ContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Alışkanlıklar',
                subtitle: habits.isEmpty
                    ? 'Zinciri kurmaya başla'
                    : '${habits.length} alışkanlık · $activeStreaks aktif seri',
              ),
              Expanded(
                child: habits.isEmpty
                    ? const EmptyState(
                        icon: Icons.local_fire_department_rounded,
                        title: 'Henüz alışkanlık yok.',
                        text:
                            'Saati olmayan, haftada birkaç kez yeten işler '
                            'burada: spor, gitar, kod… Belli saatte tekrar '
                            'eden bir iş ise yeri Rutinler.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          S.gutter,
                          S.xs,
                          S.gutter,
                          S.fabGap,
                        ),
                        itemCount: habits.length,
                        itemBuilder: (_, i) => _HabitCard(habit: habits[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitCard extends ConsumerWidget {
  final Habit habit;
  const _HabitCard({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final store = ref.read(appStoreProvider);
    final today = DateTime.now();
    final doneToday = habit.isDoneOn(today);
    final streak = habit.currentStreak;
    final rate = habit.completionRate(30);

    return Container(
      margin: const EdgeInsets.only(bottom: S.md),
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.radiusMd,
        border: Border.all(color: c.lineSoft),
        boxShadow: c.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: habit.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: T.strong,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      habit.isEveryDay
                          ? 'Her gün'
                          : 'Haftada ${habit.targetPerWeek}',
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.micro,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Bugün işaretle
              _TodayButton(
                done: doneToday,
                color: habit.color,
                onTap: () => store.toggleHabit(habit, today),
              ),
              const SizedBox(width: S.hair),
              IconButton(
                onPressed: () => _confirmDelete(context, store, habit),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: I.md,
                  color: c.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.lg),
          Row(
            children: [
              _Stat(
                icon: Icons.local_fire_department_rounded,
                value: '$streak',
                label: 'gün seri',
                color: streak > 0 ? c.warning : c.inkFaint,
              ),
              const SizedBox(width: S.xl),
              _Stat(
                icon: Icons.percent_rounded,
                value: '${(rate * 100).round()}',
                label: 'son 30 gün',
                color: habit.color,
              ),
            ],
          ),
          const SizedBox(height: S.lg),
          HabitHeatmap(
            habit: habit,
            onToggleDay: (day) => store.toggleHabit(habit, day),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppStore store, Habit h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alışkanlığı sil'),
        content: Text('"${h.title}" ve tüm geçmişi silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: ctx.colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) store.removeHabit(h);
  }
}

class _TodayButton extends StatelessWidget {
  final bool done;
  final Color color;
  final VoidCallback onTap;
  const _TodayButton({
    required this.done,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onColor = inkOn(color);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
          decoration: BoxDecoration(
            color: done ? color : c.hover,
            borderRadius: R.radiusPill,
            border: Border.all(color: done ? color : c.line),
            boxShadow: done ? c.shadowSm : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done ? Icons.check_rounded : Icons.add_rounded,
                size: I.sm,
                color: done ? onColor : c.inkDim,
              ),
              const SizedBox(width: S.xs),
              Text(
                'Bugün',
                style: TextStyle(
                  color: done ? onColor : c.inkDim,
                  fontSize: T.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      children: [
        Icon(icon, size: I.md, color: color),
        const SizedBox(width: S.sm),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: T.headline,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: S.xs),
        Text(
          label,
          style: TextStyle(
            color: c.inkFaint,
            fontSize: T.micro,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// --- Ekleme diyaloğu ---------------------------------------------------------

void _showAddHabit(BuildContext context, AppStore store) {
  showDialog(
    context: context,
    builder: (_) => _AddHabitDialog(store: store),
  );
}

class _AddHabitDialog extends StatefulWidget {
  final AppStore store;
  const _AddHabitDialog({required this.store});

  @override
  State<_AddHabitDialog> createState() => _AddHabitDialogState();
}

class _AddHabitDialogState extends State<_AddHabitDialog> {
  final _controller = TextEditingController();
  Color _color = kTaskColors.first;

  int _target = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      title: const Text('Yeni alışkanlık'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(color: c.ink),
            decoration: const InputDecoration(hintText: 'Ör. Sabah koşusu'),
          ),
          const SizedBox(height: S.lg),
          Text('Renk', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: S.sm),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final color in kTaskColors)
                GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == color ? c.ink : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.lg),
          // Ritim tek eksen: haftada kaç kez. "Günlük mü haftalık mı" diye
          // ayrı bir soru yok — 7 zaten "her gün" (plan §Zc).
          Text('Ritim', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: S.xs),
          Text(
            'Alışkanlık süreksiz olan iştir: haftada kaç kez yeteceğini sen '
            'söylersin. Her gün belli bir saatte yapılacak bir şey ise onu '
            'rutin olarak ekle.',
            style: TextStyle(color: c.inkFaint, fontSize: T.caption),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              Text('Hedef', style: TextStyle(color: c.inkDim, fontSize: T.body)),
              Expanded(
                child: Slider(
                  value: _target.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: '$_target',
                  onChanged: (v) => setState(() => _target = v.round()),
                ),
              ),
              // Ucundaki 7'yi "7/hafta" diye yazmak eksenin tek olduğunu
              // gizlerdi: kullanıcı orada "her gün"ü arıyor, sayıyı değil.
              Text(
                _target >= 7 ? 'Her gün' : '$_target/hafta',
                style: TextStyle(
                  color: c.ink,
                  fontSize: T.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _controller.text.trim();
            if (title.isEmpty) return;
            widget.store.addHabit(
              Habit(
                title: title,
                color: _color,
                targetPerWeek: _target,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
