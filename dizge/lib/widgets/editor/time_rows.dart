/// Editörün saatle ilgili dört satırı: başlangıç saati, süre, gün içinde
/// tekrar ve saat aralığı.
///
/// Dördü de durum tutmuyor: değeri alıp değişeni geri bildiriyorlar. Bir
/// arada duruyorlar çünkü aynı saat seçiciyi ([askHour]) ve aynı
/// biçimlendirmeyi paylaşıyorlar.
library;

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme.dart';
import 'editor_controls.dart';
import 'property_row.dart';

const List<double> _hourPresets = [7.0, 9.0, 12.0, 14.0, 18.0, 20.0];

/// Hazır aralıklar: sabah / öğleden sonra / akşam.
///
/// Günün kaba dilimleri; ince ayar "Seç…" ile yapılıyor. Amaç iki uç için
/// iki ayrı saat seçtirmeden en sık istenen üç aralığı tek dokunuşa
/// indirmek.
const List<(double, double)> _windowPresets = [
  (9.0, 12.0),
  (13.0, 18.0),
  (18.0, 22.0),
];

/// Saat sorar; iptalde null döner. 24 saat biçimi zorunlu.
Future<double?> askHour(
  BuildContext context, {
  required String helpText,
  required double initial,
}) async {
  final picked = await showTimePicker(
    context: context,
    helpText: helpText,
    initialTime: TimeOfDay(
      hour: initial.floor() % 24,
      minute: ((initial % 1) * 60).round() % 60,
    ),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return picked == null ? null : picked.hour + picked.minute / 60;
}

/// Başlangıç saati — null "saatsiz" demek.
class TimeRow extends StatelessWidget {
  const TimeRow({
    super.key,
    required this.start,
    required this.duration,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });

  final double? start;

  /// Yalnız alt yazıdaki bitiş saatini hesaplamak için; değiştirilmiyor.
  final double duration;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PropertyRow(
      icon: Icons.schedule_rounded,
      label: 'Saat',
      value: start == null ? 'Saatsiz' : Task.formatTime(start!),
      valueColor: start == null ? c.inkFaint : null,
      open: open,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChipTile(
                text: 'Saatsiz',
                selected: start == null,
                onTap: () => onChanged(null),
              ),
              for (final h in _hourPresets)
                ChoiceChipTile(
                  text: Task.formatTime(h),
                  selected: start == h,
                  onTap: () => onChanged(h),
                ),
              ChoiceChipTile(
                text: 'Seç…',
                selected: start != null && !_hourPresets.contains(start),
                onTap: () async {
                  final s = start;
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: s == null
                        ? const TimeOfDay(hour: 9, minute: 0)
                        : TimeOfDay(
                            hour: s.floor() % 24,
                            minute: ((s % 1) * 60).round() % 60,
                          ),
                    builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(
                        ctx,
                      ).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    onChanged(picked.hour + picked.minute / 60);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Text(
            start == null
                ? 'Saatsiz işler günün listesinde en altta durur.'
                : 'Bitiş: ${Task.formatTime((start! + duration).clamp(0.0, 24.0))}  ·  süre ${Task.formatDuration(duration)}',
            style: TextStyle(color: c.inkFaint, fontSize: T.caption),
          ),
        ],
      ),
    );
  }
}

/// İşin ne kadar süreceği.
class DurationRow extends StatelessWidget {
  const DurationRow({
    super.key,
    required this.duration,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });

  final double duration;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<double> onChanged;

  static const _presets = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PropertyRow(
      icon: Icons.timelapse_rounded,
      label: 'Süre',
      value: Task.formatDuration(duration),
      open: open,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _presets)
                ChoiceChipTile(
                  text: Task.formatDuration(d),
                  selected: duration == d,
                  onTap: () => onChanged(d),
                ),
            ],
          ),
          const SizedBox(height: S.xs),
          Row(
            children: [
              Text(
                'İnce ayar',
                style: TextStyle(color: c.inkFaint, fontSize: T.caption),
              ),
              Expanded(
                child: Slider(
                  value: duration.clamp(0.25, 12.0),
                  min: 0.25,
                  max: 12,
                  divisions: 47, // 15 dakikalık adımlar
                  label: Task.formatDuration(duration),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Günde birden çok tekrar: 08:00 / 14:00 / 20:00 gibi.
///
/// Pencereyle karışmasın diye ayrı satır ve ayrı dil: burada iş **birkaç
/// kez** olur, orada bir kez olur ama yeri serbesttir (§Za).
class TimesRow extends StatelessWidget {
  const TimesRow({
    super.key,
    required this.times,
    required this.start,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });

  final List<double> times;

  /// İşin kendi saati: ilk tekrar eklendiğinde listeye o da giriyor.
  final double? start;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<List<double>> onChanged;

  /// Listeye bir saat ekler.
  ///
  /// İlk eklemede işin kendi saati de listeye giriyor: kullanıcı "14:00 da
  /// olsun" derken 08:00'i silmek istememiştir.
  Future<void> _addTime(BuildContext context) async {
    final picked = await askHour(
      context,
      helpText: 'Tekrar saati',
      initial: start ?? 9,
    );
    if (picked == null) return;
    final next = [...times];
    if (next.isEmpty && start != null) next.add(start!);
    if (!next.contains(picked)) next.add(picked);
    next.sort();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final many = times.length > 1;
    return PropertyRow(
      icon: Icons.repeat_one_rounded,
      label: 'Gün içinde tekrar',
      value: many ? '${times.length} kez' : 'Tek sefer',
      valueColor: many ? null : c.inkFaint,
      open: open,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChipTile(
                text: 'Tek sefer',
                selected: !many,
                onTap: () => onChanged(const []),
              ),
              for (final h in [...times]..sort())
                ChoiceChipTile(
                  text: '${Task.formatTime(h)}  ×',
                  selected: true,
                  onTap: () => onChanged([...times]..remove(h)),
                ),
              ChoiceChipTile(
                text: 'Saat ekle…',
                selected: false,
                onTap: () => _addTime(context),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Text(
            many
                ? 'Her tekrar ayrı işaretlenir; gün ancak hepsi bitince '
                      'tamamlanmış sayılır.'
                : 'İlaç, su içme, kontrol turu gibi gün içinde tekrarlayan '
                      'işler için saat ekle.',
            style: TextStyle(color: c.inkFaint, fontSize: T.caption),
          ),
        ],
      ),
    );
  }
}

/// Saat penceresi: işin içinde kalması istenen aralık.
///
/// Süre alanı değil — "09:00–12:00 arasında" demek "üç saat sürecek" demek
/// değil. Alt yazı bu ikisini yan yana gösteriyor ki karışmasın.
class WindowRow extends StatelessWidget {
  const WindowRow({
    super.key,
    required this.window,
    required this.duration,
    required this.open,
    required this.onTap,
    required this.onChanged,
  });

  /// (başlangıç, bitiş) ya da null.
  final (double, double)? window;

  /// Yalnız alt yazıda: aralığın süreyle karışmaması için.
  final double duration;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<(double, double)?> onChanged;

  /// Aralığın iki ucunu sırayla sorar.
  ///
  /// Ters ya da sıfır genişlikli seçim **yazılmıyor**: modelde de okunmuyor
  /// (bkz. `_readWindow`), burada sessizce düzeltmek yerine hiç uygulamamak
  /// kullanıcıya ne olduğunu gösteriyor — seçtiği aralık olduğu gibi duruyor.
  Future<void> _pickWindow(BuildContext context) async {
    final start = await askHour(
      context,
      helpText: 'Aralığın başlangıcı',
      initial: window?.$1 ?? 9,
    );
    if (start == null || !context.mounted) return;

    final end = await askHour(
      context,
      helpText: 'Aralığın bitişi',
      initial: window?.$2 ?? (start + 3).clamp(0.0, 24.0),
    );
    if (end == null) return;

    if (end <= start) return;
    onChanged((start, end));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final has = window != null;
    return PropertyRow(
      icon: Icons.compress_rounded,
      label: 'Saat aralığı',
      value: has
          ? '${Task.formatTime(window!.$1)} – ${Task.formatTime(window!.$2)}'
          : 'Yok',
      valueColor: has ? null : c.inkFaint,
      open: open,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChipTile(
                text: 'Yok',
                selected: !has,
                onTap: () => onChanged(null),
              ),
              for (final w in _windowPresets)
                ChoiceChipTile(
                  text: '${Task.formatTime(w.$1)} – ${Task.formatTime(w.$2)}',
                  selected: window == w,
                  onTap: () => onChanged(w),
                ),
              ChoiceChipTile(
                text: 'Seç…',
                selected: has && !_windowPresets.contains(window!),
                onTap: () => _pickWindow(context),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Text(
            has
                ? 'İş bu aralıkta kalır; "Günü kurtar" dışına taşıyamaz. '
                      'Süre ayrı: ${Task.formatDuration(duration)}.'
                : 'Aralık seçilirse iş yalnız o saatler arasında yer alır.',
            style: TextStyle(color: c.inkFaint, fontSize: T.caption),
          ),
        ],
      ),
    );
  }
}
