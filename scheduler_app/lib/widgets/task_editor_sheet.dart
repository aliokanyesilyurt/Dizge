import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import 'drawing_canvas.dart';

/// İş editörü. Kaydedildiyse/silindiyse true döner.
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
    barrierColor: Colors.black.withValues(alpha: 0.32),
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
  late Energy? _energy;
  late bool _isFixed;
  late bool _drawMode;

  /// Aynı anda tek bir özellik satırı açık kalır (sade tutmak için).
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
    _start =
        e?.startHour ??
        (widget.presetStart == null
            ? null
            : widget.presetStart!.hour + widget.presetStart!.minute / 60.0);
    _duration = e?.durationHours ?? 1.0;
    final cat = AppData.categories.first;
    _color = e?.color ?? cat.color;
    _categoryName = e?.categoryName ?? cat.name;
    // Varsayılan yok: efor belirtmek isteğe bağlı kalmalı.
    _energy = e?.energy;
    // Varsayılanı esnek: kullanıcı hiçbir şey işaretlemezse "Günü kurtar"
    // çalışsın (bkz. plan K3).
    _isFixed = e?.isFixed ?? false;
    _drawMode = e?.sketch != null && !e!.sketch!.isEmpty;

    ref
        .read(telemetryProvider)
        .capture(
          Ev.editorOpened,
          props: {
            'mode': widget.existing == null ? 'create' : 'edit',
            'from_draft': widget.draft != null,
          },
        );
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _place.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() => _open = _open == key ? null : key);

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _open = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşin bir başlığı olmalı.')));
      return;
    }
    final repeat = _repeatType == RepeatType.once
        ? const Repeat.once()
        : Repeat(
            _repeatType,
            weekdays: _repeatType == RepeatType.weekly
                ? (_weekdays.isEmpty ? {_date.weekday} : _weekdays)
                : const {},
            until: _until,
          );

    final isNew = widget.existing == null;
    final task =
        widget.existing ?? Task(title: title, color: _color, date: _date);
    task
      ..title = title
      ..note = _drawMode ? '' : _note.text.trim()
      ..place = _place.text.trim()
      ..sketch = (_drawMode && !_sketch.isEmpty)
          ? _sketch.toSketch(_color)
          : null
      ..startHour = _start
      ..durationHours = _duration
      ..color = _color
      ..categoryName = _categoryName
      ..energy = _energy
      ..isFixed = _isFixed
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
            'Bu bir rutin. Sadece bu günü mü, yoksa rutinin tamamını mı kaldıralım?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'day'),
              child: const Text('Bu günden itibaren'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: Text('Tamamı', style: TextStyle(color: ctx.colors.danger)),
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
    final c = context.colors;
    final maxHeight = MediaQuery.of(context).size.height * 0.92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabber(c),
            _titleField(c),
            Divider(height: 1, color: c.lineSoft),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _kindRow(c),
                  if (_isRoutine) _repeatRow(c),
                  _dateRow(),
                  _timeRow(c),
                  if (_start != null) _durationRow(c),
                  _categoryRow(c),
                  _energyRow(c),
                  _fixedRow(c),
                  _placeRow(c),
                  _noteRow(c),
                ],
              ),
            ),
            _footer(c),
          ],
        ),
      ),
    );
  }

  Widget _grabber(AppPalette c) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(top: 12, bottom: 8),
    decoration: BoxDecoration(
      color: c.line,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _titleField(AppPalette c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 14, 16),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 28,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: TextField(
            controller: _title,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              color: c.ink,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'Başlıksız',
              hintStyle: TextStyle(
                color: c.inkFaint,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        if (widget.existing != null)
          IconButton(
            tooltip: 'Sil',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.inkDim),
            onPressed: _delete,
          ),
      ],
    ),
  );

  // ---- Özellik satırları ---------------------------------------------------

  Widget _kindRow(AppPalette c) {
    return _PropertyRow(
      icon: _isRoutine ? Icons.repeat_rounded : Icons.today_rounded,
      label: 'Tür',
      value: _isRoutine ? 'Rutin' : 'Tek günlük',
      valueColor: _isRoutine ? c.accent : c.ink,
      open: _open == 'kind',
      onTap: () => _toggle('kind'),
      child: Row(
        children: [
          Expanded(
            child: _BigChoice(
              icon: Icons.today_rounded,
              title: 'Tek günlük',
              subtitle: 'Sadece seçilen günde',
              selected: !_isRoutine,
              onTap: () => setState(() => _repeatType = RepeatType.once),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigChoice(
              icon: Icons.repeat_rounded,
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

  Widget _repeatRow(AppPalette c) {
    final repeat = Repeat(_repeatType, weekdays: _weekdays, until: _until);
    return _PropertyRow(
      icon: Icons.autorenew_rounded,
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
              _chip(
                'Her gün',
                _repeatType == RepeatType.daily,
                () => setState(() => _repeatType = RepeatType.daily),
              ),
              _chip('Haftanın günleri', _repeatType == RepeatType.weekly, () {
                setState(() {
                  _repeatType = RepeatType.weekly;
                  if (_weekdays.isEmpty) _weekdays = {_date.weekday};
                });
              }),
              _chip(
                'Her ay',
                _repeatType == RepeatType.monthly,
                () => setState(() => _repeatType = RepeatType.monthly),
              ),
            ],
          ),
          if (_repeatType == RepeatType.weekly) ...[
            const SizedBox(height: 14),
            Row(
              spacing: 6,
              children: List.generate(7, (i) {
                final day = i + 1;
                final sel = _weekdays.contains(day);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      sel ? _weekdays.remove(day) : _weekdays.add(day);
                    }),
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? c.accentSoft : c.surface,
                        borderRadius: R.radiusSm,
                        border: Border.all(color: sel ? c.accent : c.line),
                      ),
                      child: Text(
                        Repeat.weekdayShort[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? c.navActiveInk : c.inkDim,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.event_busy_rounded, size: 15, color: c.inkFaint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _until == null
                      ? 'Bitiş yok — süresiz tekrar eder'
                      : 'Bitiş: ${_fmtDate(_until!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.inkDim, fontSize: 13),
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
      icon: Icons.calendar_today_rounded,
      label: _isRoutine ? 'Başlangıç' : 'Tarih',
      value: _fmtDate(_date),
      open: _open == 'date',
      onTap: () => _toggle('date'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip('Bugün', _date == today, () => setState(() => _date = today)),
          _chip(
            'Yarın',
            _date == tomorrow,
            () => setState(() => _date = tomorrow),
          ),
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

  Widget _timeRow(AppPalette c) {
    return _PropertyRow(
      icon: Icons.schedule_rounded,
      label: 'Saat',
      value: _start == null ? 'Saatsiz' : Task.formatTime(_start!),
      valueColor: _start == null ? c.inkFaint : null,
      open: _open == 'time',
      onTap: () => _toggle('time'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                'Saatsiz',
                _start == null,
                () => setState(() => _start = null),
              ),
              for (final h in _hourPresets)
                _chip(
                  Task.formatTime(h),
                  _start == h,
                  () => setState(() => _start = h),
                ),
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
                      data: MediaQuery.of(
                        ctx,
                      ).copyWith(alwaysUse24HourFormat: true),
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
          const SizedBox(height: 12),
          Text(
            _start == null
                ? 'Saatsiz işler günün listesinde en altta durur.'
                : 'Bitiş: ${Task.formatTime((_start! + _duration).clamp(0.0, 24.0))}  ·  süre ${Task.formatDuration(_duration)}',
            style: TextStyle(color: c.inkFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _durationRow(AppPalette c) {
    const presets = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0];
    return _PropertyRow(
      icon: Icons.timelapse_rounded,
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
                _chip(
                  Task.formatDuration(d),
                  _duration == d,
                  () => setState(() => _duration = d),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'İnce ayar',
                style: TextStyle(color: c.inkFaint, fontSize: 12),
              ),
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

  Widget _categoryRow(AppPalette c) {
    return _PropertyRow(
      icon: Icons.sell_rounded,
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
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: R.radiusXs,
                border: Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 14, color: c.inkDim),
                  const SizedBox(width: 5),
                  Text('Özel', style: TextStyle(color: c.inkDim, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Efor seçici.
  ///
  /// Kategori satırının hemen altında: ikisi de "bu iş ne türden bir iş"
  /// sorusunun parçası. Saat/süre satırlarının arasına girseydi zaman kararıyla
  /// karışırdı.
  Widget _energyRow(AppPalette c) {
    return _PropertyRow(
      icon: Icons.bolt_rounded,
      label: 'Efor',
      value: _energy?.label ?? 'Belirtilmemiş',
      // Boş hâl sessiz kalmalı: efor isteğe bağlı, seçilmemiş olması bir eksik
      // değil.
      valueColor: _energy == null ? c.inkFaint : c.ink,
      open: _open == 'energy',
      onTap: () => _toggle('energy'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final level in Energy.values)
            _chip(
              level.label,
              _energy == level,
              // Seçili kademeye tekrar dokunmak seçimi kaldırır: aksi hâlde
              // yanlışlıkla işaretlenen bir iş bir daha "belirtilmemiş"e
              // dönemezdi.
              () => setState(() => _energy = _energy == level ? null : level),
            ),
        ],
      ),
    );
  }

  /// "Sabit" anahtarı — "Günü kurtar" bu işe dokunmasın.
  ///
  /// Eforun hemen altında, çünkü ikisi de aynı soruyu ayrı eksenlerden
  /// soruyor: efor "ne kadar yorar", sabitlik "kımıldatılabilir mi". Öncelikle
  /// karıştırılmaması için bilerek ayrı bir satır (bkz. plan K3).
  Widget _fixedRow(AppPalette c) {
    return _PropertyRow(
      icon: _isFixed ? Icons.push_pin_rounded : Icons.push_pin_outlined,
      label: 'Sabit',
      value: _isFixed ? 'Kımıldatılamaz' : 'Esnek',
      // Varsayılan olan "Esnek" sessiz kalıyor: işaretlenen şey istisna.
      valueColor: _isFixed ? c.ink : c.inkFaint,
      open: _open == 'fixed',
      onTap: () => _toggle('fixed'),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Randevu, ders, uçuş gibi kımıldatılamayan işler. '
              '"Günü kurtar" bunlara dokunmaz.',
              style: TextStyle(color: c.inkDim, fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: _isFixed,
            onChanged: (v) => setState(() => _isFixed = v),
          ),
        ],
      ),
    );
  }

  Widget _placeRow(AppPalette c) {
    return _PropertyRow(
      icon: Icons.place_rounded,
      label: 'Yer',
      value: _place.text.trim().isEmpty ? 'Boş' : _place.text.trim(),
      open: _open == 'place',
      onTap: () => _toggle('place'),
      child: TextField(
        controller: _place,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: c.ink, fontSize: 15),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: 'Ev, ofis, spor salonu…'),
      ),
    );
  }

  Widget _noteRow(AppPalette c) {
    final hasNote = _drawMode ? !_sketch.isEmpty : _note.text.trim().isNotEmpty;
    return _PropertyRow(
      icon: Icons.notes_rounded,
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
          const SizedBox(height: 12),
          if (_drawMode)
            DrawingCanvas(controller: _sketch, color: _color)
          else
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: c.ink, fontSize: 15),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Bir şeyler yaz…'),
            ),
        ],
      ),
    );
  }

  Widget _footer(AppPalette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 18),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        border: Border(top: BorderSide(color: c.lineSoft)),
        boxShadow: c.shadowSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _summary(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.inkFaint, fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(width: 14),
          ElevatedButton(
            onPressed: _save,
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
      builder: (ctx) {
        final c = ctx.colors;
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: const Text('Özel kategori'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  style: TextStyle(color: c.ink),
                  decoration: const InputDecoration(hintText: 'Kategori adı'),
                  onChanged: (v) => name = v,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kTaskColors.map((color) {
                    final sel = color == picked;
                    return GestureDetector(
                      onTap: () => setDlg(() => picked = color),
                      child: AnimatedContainer(
                        duration: Motion.fast,
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel ? c.ink : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: sel
                            ? Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: inkOn(color),
                              )
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
                child: const Text('İptal'),
              ),
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
        );
      },
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
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Özellik satırı: ikon + etiket + değer; dokununca altı açılır.
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
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.curve,
        decoration: BoxDecoration(
          color: open ? c.hover : Colors.transparent,
          borderRadius: R.radiusMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: R.radiusMd,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 17, color: c.inkDim),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 76,
                      child: Text(
                        label,
                        style: TextStyle(color: c.inkDim, fontSize: 13.5),
                      ),
                    ),
                    Expanded(
                      child: valueWidget != null
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: valueWidget!,
                            )
                          : Text(
                              value ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: (value == 'Boş')
                                    ? c.inkFaint
                                    : (valueColor ?? c.ink),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: Motion.base,
                      curve: Motion.curve,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
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
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface,
            borderRadius: R.radiusSm,
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: selected ? c.navActiveInk : c.inkDim),
              const SizedBox(height: 9),
              Text(
                title,
                style: TextStyle(
                  color: selected ? c.navActiveInk : c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceChipTile extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChipTile({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface,
            borderRadius: R.radiusPill,
            border: Border.all(color: selected ? c.accent : c.line),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? c.navActiveInk : c.inkDim,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kategori etiketi.
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool selected;

  const _Tag({required this.text, required this.color, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final style = context.colors.tag(color, selected: selected);
    return AnimatedContainer(
      duration: Motion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: R.radiusPill,
        border: Border.all(
          color: selected ? color : Colors.transparent,
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: style.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
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
    final c = context.colors;

    Widget seg(String label, IconData icon, bool active, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? c.surfaceAlt : Colors.transparent,
              borderRadius: R.radiusPill,
              boxShadow: active ? c.shadowSm : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: active ? c.ink : c.inkFaint),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? c.ink : c.inkFaint,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.isDark ? c.bg : c.hover,
        borderRadius: R.radiusPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Yaz', Icons.keyboard_rounded, !drawMode, () => onChanged(false)),
          seg('Çiz', Icons.gesture_rounded, drawMode, () => onChanged(true)),
        ],
      ),
    );
  }
}
