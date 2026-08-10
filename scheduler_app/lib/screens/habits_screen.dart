import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/habit.dart';
import '../models/task.dart' show kTaskColors;
import '../theme.dart';
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
        child: const Icon(Icons.add_rounded, size: 24),
      ),
      body: SafeArea(
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
                      text: 'Spor, gitar, kod… küçük başla, zinciri kırma.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                      itemCount: habits.length,
                      itemBuilder: (_, i) => _HabitCard(habit: habits[i]),
                    ),
            ),
          ],
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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
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
              const SizedBox(width: 11),
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
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      habit.cadence == HabitCadence.daily
                          ? 'Her gün'
                          : 'Haftada ${habit.targetPerWeek}',
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: 11.5,
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
              const SizedBox(width: 2),
              IconButton(
                onPressed: () => _confirmDelete(context, store, habit),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: c.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(
                icon: Icons.local_fire_department_rounded,
                value: '$streak',
                label: 'gün seri',
                color: streak > 0 ? c.warning : c.inkFaint,
              ),
              const SizedBox(width: 24),
              _Stat(
                icon: Icons.percent_rounded,
                value: '${(rate * 100).round()}',
                label: 'son 30 gün',
                color: habit.color,
              ),
            ],
          ),
          const SizedBox(height: 18),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                size: 15,
                color: done ? onColor : c.inkDim,
              ),
              const SizedBox(width: 5),
              Text(
                'Bugün',
                style: TextStyle(
                  color: done ? onColor : c.inkDim,
                  fontSize: 12.5,
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
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 7),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: c.inkFaint,
            fontSize: 11.5,
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
  HabitCadence _cadence = HabitCadence.daily;
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
          const SizedBox(height: 20),
          Text('Renk', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          Text('Ritim', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 10),
          SegmentedButton<HabitCadence>(
            segments: const [
              ButtonSegment(value: HabitCadence.daily, label: Text('Her gün')),
              ButtonSegment(
                value: HabitCadence.weekly,
                label: Text('Haftada N'),
              ),
            ],
            selected: {_cadence},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _cadence = s.first),
          ),
          if (_cadence == HabitCadence.weekly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Hedef', style: TextStyle(color: c.inkDim, fontSize: 13)),
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
                Text(
                  '$_target/hafta',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
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
                cadence: _cadence,
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
