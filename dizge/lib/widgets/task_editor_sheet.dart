import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/telemetry.dart';
import '../data/app_store.dart';
import '../models/task.dart';
import '../theme.dart';
import 'drawing_canvas.dart';
import 'editor/editor_controls.dart';
import 'editor/place_field.dart';
import 'editor/property_row.dart';
import 'editor/repeat_row.dart';
import 'editor/time_rows.dart';
import 'owner_avatar.dart';

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
  late double? _windowStart;
  late double? _windowEnd;
  late List<double> _times;
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
    _windowStart = e?.windowStart;
    _windowEnd = e?.windowEnd;
    _times = [...?e?.timesOfDay];
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
      // Kımıldatılamaz işaretlenmişse pencere temizleniyor: satır gizliyken
      // arkada duran bir aralık, kullanıcının göremediği bir kısıt olurdu.
      ..windowStart = _isFixed ? null : _windowStart
      ..windowEnd = _isFixed ? null : _windowEnd
      ..setTimes(_start == null ? const [] : _times)
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
          content: const Text('Bu bir rutin. Nasıl silelim?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: const Text('Sadece bu gün'),
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

      if (choice == 'all') {
        store.removeTask(e);
      } else if (choice == 'day') {
        store.endRoutineBefore(e, widget.date);
      } else if (choice == 'skip') {
        store.skipRoutineOn(e, widget.date, true);
      }
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
                padding: const EdgeInsets.symmetric(vertical: S.xs),
                children: [
                  _ownerRow(c),
                  _kindRow(c),
                  if (_isRoutine)
                    RepeatRow(
                      date: _date,
                      repeat: Repeat(
                        _repeatType,
                        weekdays: _weekdays,
                        until: _until,
                      ),
                      open: _open == 'repeat',
                      onTap: () => _toggle('repeat'),
                      onChanged: (r) => setState(() {
                        _repeatType = r.type;
                        _weekdays = {...r.weekdays};
                        _until = r.until;
                      }),
                    ),
                  _dateRow(),
                  TimeRow(
                    start: _start,
                    duration: _duration,
                    open: _open == 'time',
                    onTap: () => _toggle('time'),
                    onChanged: (v) => setState(() {
                      _start = v;
                      if (_start != null &&
                          _windowStart != null &&
                          _windowEnd != null) {
                        if (_start! < _windowStart!) {
                          _windowStart = _start;
                        }
                        if (_start! + _duration > _windowEnd!) {
                          _windowEnd = _start! + _duration;
                        }
                      }
                    }),
                    onDurationChanged: (v) => setState(() {
                      _duration = v;
                      if (_start != null &&
                          _windowStart != null &&
                          _windowEnd != null) {
                        if (_start! + _duration > _windowEnd!) {
                          _windowEnd = _start! + _duration;
                        }
                      }
                    }),
                  ),
                  // Çoklu saat yalnız saatli işte anlamlı: saatsiz bir işin
                  // "birkaç kez"i tutunacak bir yer bulamaz.
                  if (_start != null)
                    TimesRow(
                      times: _times,
                      start: _start,
                      open: _open == 'times',
                      onTap: () => _toggle('times'),
                      onChanged: (v) => setState(() => _times = [...v]),
                    ),
                  _categoryRow(c),
                  _energyRow(c),
                  _fixedRow(c),
                  // Pencere yalnız esnek işte var: kımıldatılamaz işin zaten
                  // çivili bir saati vardır, orada aralık sormak anlamsız
                  // (plan §Zb).
                  if (!_isFixed)
                    WindowRow(
                      window: _windowStart != null && _windowEnd != null
                          ? (_windowStart!, _windowEnd!)
                          : null,
                      duration: _duration,
                      open: _open == 'window',
                      onTap: () => _toggle('window'),
                      onChanged: (w) => setState(() {
                        _windowStart = w?.$1;
                        _windowEnd = w?.$2;
                        if (_start != null &&
                            _windowStart != null &&
                            _windowEnd != null) {
                          if (_start! < _windowStart!) {
                            _start = _windowStart;
                          } else if (_start! + _duration > _windowEnd!) {
                            _start = (_windowEnd! - _duration).clamp(0.0, 24.0);
                          }
                        }
                      }),
                    ),
                  _placeRow(),
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

  /// "Bu işi kim yazdı" satırı (Y4.4f).
  ///
  /// Salt okunur ve öyle kalmalı: sahiplik bir tercih değil, satırın sunucuda
  /// yazılı geçmişi. Buraya bir seçici koymak, başkasının işini üstlenmeyi
  /// (ya da kendi işini başkasına yazmayı) mümkün kılardı.
  ///
  /// Kişisel bağlamda [OwnerLine] kendini gizliyor; o zaman bu satır sıfır
  /// yükseklikte bir boşluğa iniyor.
  Widget _ownerRow(AppPalette c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: S.xl),
    child: OwnerLine(
      ownerId: widget.existing?.ownerId,
      style: TextStyle(
        color: c.inkFaint,
        fontSize: T.caption,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _grabber(AppPalette c) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(top: S.md, bottom: S.sm),
    decoration: BoxDecoration(
      color: c.line,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _titleField(AppPalette c) => Padding(
    padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.md, S.lg),
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
        const SizedBox(width: S.md),
        Expanded(
          child: TextField(
            controller: _title,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              color: c.ink,
              fontSize: T.headline,
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
                fontSize: T.headline,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        if (widget.existing != null)
          IconButton(
            tooltip: 'Sil',
            icon: Icon(
              Icons.delete_outline_rounded,
              size: I.md,
              color: c.inkDim,
            ),
            onPressed: _delete,
          ),
      ],
    ),
  );

  // ---- Özellik satırları ---------------------------------------------------

  Widget _kindRow(AppPalette c) {
    return PropertyRow(
      icon: _isRoutine ? Icons.repeat_rounded : Icons.today_rounded,
      label: 'Tür',
      value: _isRoutine ? 'Rutin' : 'Tek Günlük',
      valueColor: _isRoutine ? c.accent : c.ink,
      open: _open == 'kind',
      onTap: () => _toggle('kind'),
      child: Row(
        children: [
          Expanded(
            child: BigChoice(
              icon: Icons.today_rounded,
              title: 'Tek Günlük',
              subtitle: 'Sadece seçilen günde',
              selected: !_isRoutine,
              onTap: () => setState(() => _repeatType = RepeatType.once),
            ),
          ),
          const SizedBox(width: S.sm),
          Expanded(
            child: BigChoice(
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

  Widget _dateRow() {
    final today = Task.dayKey(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    return PropertyRow(
      icon: Icons.calendar_today_rounded,
      label: _isRoutine ? 'Başlangıç' : 'Tarih',
      value: fmtDate(_date),
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

  Widget _categoryRow(AppPalette c) {
    return PropertyRow(
      icon: Icons.sell_rounded,
      label: 'Kategori',
      valueWidget: Tag(text: categoryLabel(_categoryName), color: _color),
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
              child: Tag(text: cat.label, color: cat.color, selected: sel),
            );
          }),
          GestureDetector(
            onTap: _addCustomCategory,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: R.radiusXs,
                border: Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: I.xs, color: c.inkDim),
                  const SizedBox(width: S.xs),
                  Text(
                    'Özel',
                    style: TextStyle(color: c.inkDim, fontSize: T.body),
                  ),
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
    return PropertyRow(
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
  Widget _fixedRow(AppPalette c) {
    return PropertyRow(
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
              style: TextStyle(
                color: c.inkDim,
                fontSize: T.caption,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: S.md),
          Switch(
            value: _isFixed,
            onChanged: (v) => setState(() => _isFixed = v),
          ),
        ],
      ),
    );
  }

  Widget _placeRow() {
    return PropertyRow(
      icon: Icons.place_rounded,
      label: 'Yer',
      value: _place.text.trim().isEmpty ? 'Boş' : _place.text.trim(),
      open: _open == 'place',
      onTap: () => _toggle('place'),
      // Öneriler var olan işlerin yer alanlarından geliyor (plan K7′);
      // dışarıya sorulan bir yer servisi yok.
      child: PlaceField(
        controller: _place,
        history: [for (final t in ref.read(appStoreProvider).tasks) t.place],
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _noteRow(AppPalette c) {
    final hasNote = _drawMode ? !_sketch.isEmpty : _note.text.trim().isNotEmpty;
    return PropertyRow(
      icon: Icons.notes_rounded,
      label: 'Açıklama',
      value: hasNote ? (_drawMode ? 'Çizim' : _note.text.trim()) : 'Boş',
      open: _open == 'note',
      onTap: () => _toggle('note'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegToggle(
            drawMode: _drawMode,
            onChanged: (v) => setState(() => _drawMode = v),
          ),
          const SizedBox(height: S.md),
          if (_drawMode)
            DrawingCanvas(controller: _sketch, color: _color)
          else
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: c.ink, fontSize: T.strong),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Bir şeyler yaz…'),
            ),
        ],
      ),
    );
  }

  Widget _footer(AppPalette c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.lg),
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
              style: TextStyle(
                color: c.inkFaint,
                fontSize: T.caption,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: S.md),
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
          : fmtDate(_date),
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
                const SizedBox(height: S.lg),
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
                                size: I.sm,
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
      ChoiceChipTile(text: text, selected: selected, onTap: onTap);
}
