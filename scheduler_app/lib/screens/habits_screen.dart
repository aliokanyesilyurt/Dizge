import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/habit.dart';
import '../models/task.dart' show kTaskColors;
import '../theme.dart';
import '../widgets/habit_heatmap.dart';
import 'section_header.dart';

/// Alışkanlık takibi: her alışkanlık için güncel seri (streak), tamamlanma
/// oranı ve GitHub tarzı ısı haritası. Esnek ritim (her gün / haftada N) destekli.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final store = ref.read(appStoreProvider);
    final activeStreaks = habits.where((h) => h.currentStreak > 0).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddHabit(context, store),
        child: const Icon(Icons.add, size: 22),
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
            const Divider(color: AppColors.lineSoft, height: 1),
            Expanded(
              child: habits.isEmpty
                  ? const _Empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
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

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_outlined,
                size: 34, color: AppColors.inkFaint),
            SizedBox(height: 12),
            Text(
              'Henüz alışkanlık yok.\nSpor, gitar, kod… küçük başla, zinciri kırma.',
              textAlign: TextAlign.center,
              style: TextStyle(
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

class _HabitCard extends ConsumerWidget {
  final Habit habit;
  const _HabitCard({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(appStoreProvider);
    final today = DateTime.now();
    final doneToday = habit.isDoneOn(today);
    final streak = habit.currentStreak;
    final rate = habit.completionRate(30);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineSoft),
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      habit.cadence == HabitCadence.daily
                          ? 'Her gün'
                          : 'Haftada ${habit.targetPerWeek}',
                      style: const TextStyle(
                        color: AppColors.inkFaint,
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
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _confirmDelete(context, store, habit),
                icon: const Icon(Icons.more_horiz,
                    size: 18, color: AppColors.inkFaint),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(
                icon: Icons.local_fire_department_rounded,
                value: '$streak',
                label: streak == 1 ? 'gün seri' : 'gün seri',
                color: streak > 0 ? AppColors.amber : AppColors.inkFaint,
              ),
              const SizedBox(width: 20),
              _Stat(
                icon: Icons.percent_rounded,
                value: '${(rate * 100).round()}',
                label: 'son 30 gün',
                color: habit.color,
              ),
            ],
          ),
          const SizedBox(height: 16),
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
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: AppColors.pink)),
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
  const _TodayButton(
      {required this.done, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: done ? color.withValues(alpha: 0.9) : AppColors.hover,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: done ? color : AppColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(done ? Icons.check_rounded : Icons.add_rounded,
                  size: 15,
                  color: done ? Colors.white : AppColors.inkDim),
              const SizedBox(width: 4),
              Text(
                done ? 'Bugün' : 'Bugün',
                style: TextStyle(
                  color: done ? Colors.white : AppColors.inkDim,
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
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.inkFaint,
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
    return AlertDialog(
      title: const Text('Yeni alışkanlık'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.ink),
            decoration: const InputDecoration(
              hintText: 'Ör. Sabah koşusu',
              hintStyle: TextStyle(color: AppColors.inkFaint),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Renk',
              style: TextStyle(color: AppColors.inkDim, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in kTaskColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Ritim',
              style: TextStyle(color: AppColors.inkDim, fontSize: 12.5)),
          const SizedBox(height: 8),
          SegmentedButton<HabitCadence>(
            segments: const [
              ButtonSegment(
                  value: HabitCadence.daily, label: Text('Her gün')),
              ButtonSegment(
                  value: HabitCadence.weekly, label: Text('Haftada N')),
            ],
            selected: {_cadence},
            onSelectionChanged: (s) => setState(() => _cadence = s.first),
          ),
          if (_cadence == HabitCadence.weekly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Hedef: ',
                    style: TextStyle(color: AppColors.inkDim, fontSize: 13)),
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
                Text('$_target/hafta',
                    style: const TextStyle(
                        color: AppColors.ink, fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        ElevatedButton(
          onPressed: () {
            final title = _controller.text.trim();
            if (title.isEmpty) return;
            widget.store.addHabit(Habit(
              title: title,
              color: _color,
              cadence: _cadence,
              targetPerWeek: _target,
            ));
            Navigator.pop(context);
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
