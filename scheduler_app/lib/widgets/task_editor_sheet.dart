import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import 'drawing_canvas.dart';

/// Notion tarzı iş editörü. Kaydedildiyse/silindiyse true döner.
///
/// [draft]: hızlı ekleme sayfasından devralınan, **henüz depoya yazılmamış**
/// taslak. Kullanıcı "Ayrıntılar"a bastığında yazdıkları kaybolmasın diye
/// başlangıç değerleri buradan okunur; vazgeçerse hiçbir kayıt oluşmaz.
Future<bool?> showTaskEditor(
  BuildContext context, {
  required DateTime date,
  Task? existing,
  TimeOfDay? presetStart,
  Task? draft,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceAlt,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (_) => TaskEditorSheet(
      date: date,
      existing: existing,
      presetStart: presetStart,
      draft: draft,
    ),
  );
}

class TaskEditorSheet extends ConsumerStatefulWidget {
  final DateTime date;
  final Task? existing;
  final TimeOfDay? presetStart;
  final Task? draft;

  const TaskEditorSheet({
    super.key,
    required this.date,
    this.existing,
    this.presetStart,
    this.draft,
  });

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _place;
  late final SketchController _sketch;

  late DateTime _date;
  late RepeatType _repeatType;
  late Set<int> _weekdays;
  late DateTime? _until;
  late double? _start;
  late double _duration;
  late Color _color;
  late String _categoryName;
  late bool _drawMode;

  /// Aynı anda tek bir özellik satırı açık kalır (Notion'daki gibi sade).
  String? _open;

  bool get _isRoutine => _repeatType != RepeatType.once;

  @override
  void initState() {
    super.initState();
    // Alanların kaynağı: düzenlenen kayıt > hızlı ekleme taslağı > varsayılan.
    final e = widget.existing ?? widget.draft;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _place = TextEditingController(text: e?.place ?? '');
    _sketch = SketchController(e?.sketch?.strokes);

    _date = e?.date ?? Task.dayKey(widget.date);
    _repeatType = e?.repeat.type ?? RepeatType.once;
    _weekdays = {...?e?.repeat.weekdays};
    _until = e?.repeat.until;
    _start = e?.startHour ??
        (widget.presetStart == null
            ? null
            : widget.presetStart!.hour + widget.presetStart!.minute / 60.0);
    _duration = e?.durationHours ?? 1.0;
    final cat = AppData.categories.first;
    _color = e?.color ?? cat.color;
    _categoryName = e?.categoryName ?? cat.name;
    _drawMode = e?.sketch != null && !e!.sketch!.isEmpty;

    ref.read(telemetryProvider).capture(Ev.editorOpened, props: {
      'mode': widget.existing == null ? 'create' : 'edit',
      'from_draft': widget.draft != null,
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _place.dispose();
    super.dispose();
  }

  void _toggle(String key) =>
      setState(() => _open = _open == key ? null : key);

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _open = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşin bir başlığı olmalı.')),
      );
      return;
    }
    final repeat = _repeatType == RepeatType.once
        ? const Repeat.once()
        : Repeat(_repeatType,
            weekdays: _repeatType == RepeatType.weekly
                ? (_weekdays.isEmpty ? {_date.weekday} : _weekdays)
                : const {},
            until: _until);

    final isNew = widget.existing == null;
    final task = widget.existing ??
        Task(title: title, color: _color, date: _date);
    task
      ..title = title
      ..note = _drawMode ? '' : _note.text.trim()
      ..place = _place.text.trim()
      ..sketch =
          (_drawMode && !_sketch.isEmpty) ? _sketch.toSketch(_color) : null
      ..startHour = _start
      ..durationHours = _duration
      ..color = _color
      ..categoryName = _categoryName
      ..repeat = repeat
      ..date = _date;

    // Mutasyon store üzerinden gider: dinleyen ekranlar tazelenir, değişiklik
    // şifreli depoya yazılır ve senkron kuyruğuna düşer.
    final store = ref.read(appStoreProvider);
    isNew ? store.addTask(task) : store.updateTask(task);
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    if (e.isRoutine) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rutini sil'),
          content: const Text(
              'Bu bir rutin. Sadece bu günü mü, yoksa rutinin tamamını mı kaldıralım?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'day'),
                child: const Text('Bu günden itibaren')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('Tamamı',
                  style: TextStyle(color: Color(0xFFE57373))),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      final store = ref.read(appStoreProvider);
      choice == 'all'
          ? store.removeTask(e)
          : store.endRoutineBefore(e, widget.date);
    } else {
      ref.read(appStoreProvider).removeTask(e);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabber(),
            _titleField(),
            const Divider(height: 1, color: AppColors.lineSoft),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _kindRow(),
                  if (_isRoutine) _repeatRow(),
                  _dateRow(),
                  _timeRow(),
                  if (_start != null) _durationRow(),
                  _categoryRow(),
                  _placeRow(),
                  _noteRow(),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.inkFaint,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _titleField() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 12, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 26,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Başlıksız',
                  hintStyle: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (widget.existing != null)
              IconButton(
                tooltip: 'Sil',
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.inkDim),
                onPressed: _delete,
              ),
          ],
        ),
      );

  // ---- Özellik satırları ---------------------------------------------------

  Widget _kindRow() {
    return _PropertyRow(
      icon: _isRoutine ? Icons.repeat : Icons.today_outlined,
      label: 'Tür',
      value: _isRoutine ? 'Rutin' : 'Tek günlük',
      valueColor: _isRoutine ? AppColors.blue : AppColors.ink,
      open: _open == 'kind',
      onTap: () => _toggle('kind'),
      child: Row(
        children: [
          Expanded(
            child: _BigChoice(
              icon: Icons.today_outlined,
              title: 'Tek günlük',
              subtitle: 'Sadece seçilen günde',
              selected: !_isRoutine,
              onTap: () => setState(() => _repeatType = RepeatType.once),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigChoice(
              icon: Icons.repeat,
              title: 'Rutin',
              subtitle: 'Tekrar ederek gelir',
              selected: _isRoutine,
              onTap: () => setState(() {
                if (!_isRoutine) {
                  _repeatType = RepeatType.daily;
                  _open = 'repeat';
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _repeatRow() {
    final repeat = Repeat(_repeatType, weekdays: _weekdays, until: _until);
    return _PropertyRow(
      icon: Icons.autorenew,
      label: 'Tekrar',
      value: repeat.describe(_date),
      open: _open == 'repeat',
      onTap: () => _toggle('repeat'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Her gün', _repeatType == RepeatType.daily,
                  () => setState(() => _repeatType = RepeatType.daily)),
              _chip('Haftanın günleri', _repeatType == RepeatType.weekly, () {
                setState(() {
                  _repeatType = RepeatType.weekly;
                  if (_weekdays.isEmpty) _weekdays = {_date.weekday};
                });
              }),
              _chip('Her ay', _repeatType == RepeatType.monthly,
                  () => setState(() => _repeatType = RepeatType.monthly)),
            ],
          ),
          if (_repeatType == RepeatType.weekly) ...[
            const SizedBox(height: 12),
            Row(
              spacing: 5,
              children: List.generate(7, (i) {
                final day = i + 1;
                final sel = _weekdays.contains(day);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      sel ? _weekdays.remove(day) : _weekdays.add(day);
                    }),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.blue.withValues(alpha: 0.22)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: sel ? AppColors.blue : AppColors.line),
                      ),
                      child: Text(
                        Repeat.weekdayShort[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? AppColors.blue : AppColors.inkDim,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event_busy_outlined,
                  size: 15, color: AppColors.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _until == null
                      ? 'Bitiş yok — süresiz tekrar eder'
                      : 'Bitiş: ${_fmtDate(_until!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AppColors.inkDim, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (_until != null) {
                    setState(() => _until = null);
                    return;
                  }
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date.add(const Duration(days: 30)),
                    firstDate: _date,
                    lastDate: DateTime(_date.year + 5),
                  );
                  if (picked != null) setState(() => _until = picked);
                },
                child: Text(_until == null ? 'Bitiş ekle' : 'Kaldır'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateRow() {
    final today = Task.dayKey(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    return _PropertyRow(
      icon: Icons.calendar_today_outlined,
      label: _isRoutine ? 'Başlangıç' : 'Tarih',
      value: _fmtDate(_date),
      open: _open == 'date',
      onTap: () => _toggle('date'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip('Bugün', _date == today, () => setState(() => _date = today)),
          _chip('Yarın', _date == tomorrow,
              () => setState(() => _date = tomorrow)),
          _chip(
            'Takvimden seç…',
            _date != today && _date != tomorrow,
            () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(_date.year - 2),
                lastDate: DateTime(_date.year + 5),
              );
              if (picked != null) setState(() => _date = Task.dayKey(picked));
            },
          ),
        ],
      ),
    );
  }

  static const List<double> _hourPresets = [7.0, 9.0, 12.0, 14.0, 18.0, 20.0];

  Widget _timeRow() {
    return _PropertyRow(
      icon: Icons.schedule,
      label: 'Saat',
      value: _start == null ? 'Saatsiz' : Task.formatTime(_start!),
      valueColor: _start == null ? AppColors.inkFaint : null,
      open: _open == 'time',
      onTap: () => _toggle('time'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Saatsiz', _start == null,
                  () => setState(() => _start = null)),
              for (final h in _hourPresets)
                _chip(Task.formatTime(h), _start == h,
                    () => setState(() => _start = h)),
              _chip(
                'Seç…',
                _start != null && !_hourPresets.contains(_start),
                () async {
                  final s = _start;
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: s == null
                        ? const TimeOfDay(hour: 9, minute: 0)
                        : TimeOfDay(
                            hour: s.floor() % 24,
                            minute: ((s % 1) * 60).round() % 60,
                          ),
                    builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(ctx)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() => _start = picked.hour + picked.minute / 60);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _start == null
                ? 'Saatsiz işler günün listesinde en altta durur.'
                : 'Bitiş: ${Task.formatTime((_start! + _duration).clamp(0.0, 24.0))}  ·  süre ${Task.formatDuration(_duration)}',
            style: const TextStyle(color: AppColors.inkFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _durationRow() {
    const presets = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0];
    return _PropertyRow(
      icon: Icons.timelapse_outlined,
      label: 'Süre',
      value: Task.formatDuration(_duration),
      open: _open == 'duration',
      onTap: () => _toggle('duration'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in presets)
                _chip(Task.formatDuration(d), _duration == d,
                    () => setState(() => _duration = d)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('İnce ayar',
                  style: TextStyle(color: AppColors.inkFaint, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _duration.clamp(0.25, 12.0),
                  min: 0.25,
                  max: 12,
                  divisions: 47, // 15 dakikalık adımlar
                  label: Task.formatDuration(_duration),
                  onChanged: (v) => setState(() => _duration = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categoryRow() {
    return _PropertyRow(
      icon: Icons.sell_outlined,
      label: 'Kategori',
      valueWidget: _Tag(text: _categoryName, color: _color),
      open: _open == 'category',
      onTap: () => _toggle('category'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...AppData.categories.map((cat) {
            final sel = _categoryName == cat.name;
            return GestureDetector(
              onTap: () => setState(() {
                _color = cat.color;
                _categoryName = cat.name;
              }),
              child: _Tag(text: cat.name, color: cat.color, selected: sel),
            );
          }),
          GestureDetector(
            onTap: _addCustomCategory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: AppColors.inkDim),
                  SizedBox(width: 4),
                  Text('Özel',
                      style: TextStyle(color: AppColors.inkDim, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeRow() {
    return _PropertyRow(
      icon: Icons.place_outlined,
      label: 'Yer',
      value: _place.text.trim().isEmpty ? 'Boş' : _place.text.trim(),
      open: _open == 'place',
      onTap: () => _toggle('place'),
      child: TextField(
        controller: _place,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: AppColors.ink, fontSize: 15),
        onChanged: (_) => setState(() {}),
        decoration: _inputDecoration('Ev, ofis, spor salonu…'),
      ),
    );
  }

  Widget _noteRow() {
    final hasNote = _drawMode ? !_sketch.isEmpty : _note.text.trim().isNotEmpty;
    return _PropertyRow(
      icon: Icons.notes,
      label: 'Açıklama',
      value: hasNote ? (_drawMode ? 'Çizim' : _note.text.trim()) : 'Boş',
      open: _open == 'note',
      onTap: () => _toggle('note'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SegToggle(
            drawMode: _drawMode,
            onChanged: (v) => setState(() => _drawMode = v),
          ),
          const SizedBox(height: 10),
          if (_drawMode)
            DrawingCanvas(controller: _sketch, color: _color)
          else
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: AppColors.ink, fontSize: 15),
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration('Bir şeyler yaz…'),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _summary(),
              style: const TextStyle(color: AppColors.inkFaint, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            ),
            child: Text(widget.existing == null ? 'Ekle' : 'Kaydet'),
          ),
        ],
      ),
    );
  }

  String _summary() {
    final parts = <String>[
      _isRoutine
          ? Repeat(_repeatType, weekdays: _weekdays).describe(_date)
          : _fmtDate(_date),
      if (_start != null)
        '${Task.formatTime(_start!)} · ${Task.formatDuration(_duration)}',
      if (_place.text.trim().isNotEmpty) _place.text.trim(),
    ];
    return parts.join('  ·  ');
  }

  Future<void> _addCustomCategory() async {
    String name = '';
    Color picked = kTaskColors.first;
    final added = await showDialog<TaskCategory>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Özel kategori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                style: const TextStyle(color: AppColors.ink),
                decoration: _inputDecoration('Kategori adı'),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: kTaskColors.map((c) {
                  final sel = c == picked;
                  return GestureDetector(
                    onTap: () => setDlg(() => picked = c),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: sel
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.black87)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal')),
            ElevatedButton(
              onPressed: () {
                final t = name.trim();
                if (t.isEmpty) return;
                Navigator.pop(ctx, TaskCategory(t, picked));
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    if (added == null) return;
    // Store üzerinden ekle: özel kategori artık kalıcı (eskiden uygulama
    // kapanınca kayboluyordu).
    ref.read(appStoreProvider).addCategory(added);
    setState(() {
      _color = added.color;
      _categoryName = added.name;
    });
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) =>
      _ChoiceChipTile(text: text, selected: selected, onTap: onTap);

  static const List<String> _months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
  ];

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      );
}

/// Notion'daki özellik satırı: ikon + etiket + değer; dokununca altı açılır.
class _PropertyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color? valueColor;
  final bool open;
  final VoidCallback onTap;
  final Widget child;

  const _PropertyRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
    this.valueColor,
    required this.open,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            color: open ? AppColors.hover : null,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 17, color: AppColors.inkDim),
                const SizedBox(width: 10),
                SizedBox(
                  width: 78,
                  child: Text(label,
                      style: const TextStyle(
                          color: AppColors.inkDim, fontSize: 14)),
                ),
                Expanded(
                  child: valueWidget != null
                      ? Align(
                          alignment: Alignment.centerLeft, child: valueWidget!)
                      : Text(
                          value ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: (value == 'Boş')
                                ? AppColors.inkFaint
                                : (valueColor ?? AppColors.ink),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? Container(
                  width: double.infinity,
                  color: AppColors.hover,
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Tür seçimindeki büyük kart (Tek günlük / Rutin).
class _BigChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _BigChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: 0.14)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 18, color: selected ? AppColors.blue : AppColors.inkDim),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                  color: selected ? AppColors.blue : AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    color: AppColors.inkFaint, fontSize: 11.5, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChipTile extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChipTile(
      {required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue.withValues(alpha: 0.20)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: selected ? AppColors.blue : AppColors.line),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? AppColors.blue : AppColors.inkDim,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Notion etiketi.
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool selected;

  const _Tag({required this.text, required this.color, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final style = tagStyleFor(color, selected: selected);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? color : Colors.transparent,
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: style.text, fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Yaz / Çiz geçiş düğmesi.
class _SegToggle extends StatelessWidget {
  final bool drawMode;
  final ValueChanged<bool> onChanged;

  const _SegToggle({required this.drawMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, bool active, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.surface : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? AppColors.line : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? AppColors.ink : AppColors.inkFaint),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: active ? AppColors.ink : AppColors.inkFaint,
                      fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Yaz', Icons.keyboard, !drawMode, () => onChanged(false)),
          seg('Çiz', Icons.gesture, drawMode, () => onChanged(true)),
        ],
      ),
    );
  }
}
