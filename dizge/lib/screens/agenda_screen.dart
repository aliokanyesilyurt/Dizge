import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/agenda_page.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/agenda_review_sheet.dart';
import '../widgets/ink_canvas.dart';
import 'section_header.dart';

/// Ajanda: bir güne bir yaprak, üstüne elle yazılır (A4).
///
/// Ekranın sözü basit ve bu plandaki her kararın dayanağı: **yazdığın
/// kaybolmaz.** Sayfa, görev oluşsun ya da oluşmasın olduğu gibi durur; tanıma
/// bir sonraki adımda gelir ve yanılsa bile buradaki yazıya dokunamaz.
///
/// Takvim ekranları gibi kenardan kenara uzanır — `ContentColumn` ile
/// sınırlanmaz. Bir defter yaprağı dar bir sütuna sıkıştırılmaz; yazacak yer
/// ne kadar genişse o kadar iyidir.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late DateTime _day = Task.dayKey(widget.initialDay ?? DateTime.now());

  /// Kalem paleti: mürekkep rengi + üç vurgu. Kategori paletinin tamamını
  /// buraya dökmedik — defterde kalem seçmek bir renk kataloğu açmak değil,
  /// elini uzatıp başka bir kalem almaktır.
  static const _inkChoices = 4;

  int _pen = 0;
  bool _erasing = false;

  static const _weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static const _months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  List<Color> _pens(AppPalette c) => [c.ink, c.accent, c.secondary, c.warning];

  void _go(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
  }

  Timer? _saveTimer;
  bool _saving = false;

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _write(List<InkStroke> strokes, Size canvas) {
    setState(() => _saving = true);
    ref
        .read(appStoreProvider)
        .saveAgendaPage(
          ref
              .read(appStoreProvider)
              .agendaPage(_day)
              .copyWith(strokes: strokes, canvasSize: canvas),
        );
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _saving = false);
    });
  }

  void _undo(AgendaPage page) {
    if (page.strokes.isEmpty) return;
    ref
        .read(appStoreProvider)
        .saveAgendaPage(
          page.copyWith(
            strokes: page.strokes.sublist(0, page.strokes.length - 1),
          ),
        );
  }

  Future<void> _clear(AgendaPage page) async {
    if (page.strokes.isEmpty) return;

    // Sayfayı boşaltmak geri alınamayan tek işlem; sormadan yapılmaz.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayfayı temizle'),
        content: const Text('Bu güne yazdığın her şey silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Temizle', style: TextStyle(color: ctx.colors.danger)),
          ),
        ],
      ),
    );

    if (ok == true) {
      ref
          .read(appStoreProvider)
          .saveAgendaPage(page.copyWith(strokes: const []));
    }
  }

  Future<void> _review(AgendaPage page) async {
    final created = await showAgendaReview(context, page: page);
    if (!mounted || created == null || created == 0) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created == 1 ? '1 görev oluşturuldu' : '$created görev oluşturuldu',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final page = ref.watch(agendaPageProvider(_day));
    final today = Task.dayKey(DateTime.now());
    final isToday = _day == today;

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: page.strokes.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _review(page),
              icon: const Icon(Icons.playlist_add_check_rounded, size: I.lg),
              label: const Text('Görevlere çevir'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            SectionHeader(
              title: '${_day.day} ${_months[_day.month - 1]}',
              subtitle: isToday
                  ? 'Bugün · ${_weekdays[_day.weekday - 1]}'
                  : _weekdays[_day.weekday - 1],
              trailing: _DayNav(
                onPrev: () => _go(-1),
                onNext: () => _go(1),
                onToday: isToday ? null : () => setState(() => _day = today),
              ),
            ),
            _Toolbar(
              pens: _pens(c),
              selectedPen: _pen,
              erasing: _erasing,
              canUndo: page.strokes.isNotEmpty,
              isSaving: _saving,
              onPen: (i) => setState(() {
                _pen = i;
                _erasing = false;
              }),
              onErase: () => setState(() => _erasing = !_erasing),
              onUndo: () => _undo(page),
              onClear: () => _clear(page),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  S.gutter,
                  S.sm,
                  S.gutter,
                  S.gutter,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final canvas = Size(box.maxWidth, box.maxHeight);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: R.radiusMd,
                        border: Border.all(color: c.lineSoft),
                        boxShadow: c.shadowSm,
                      ),
                      child: ClipRRect(
                        borderRadius: R.radiusMd,
                        child: InkCanvas(
                          // Sayfa değişince tuval sıfırdan kurulmalı: aynı
                          // durumu taşırsa yarım kalmış bir vuruş öbür güne
                          // geçerdi.
                          key: ValueKey(page.key),
                          strokes: page.strokes,
                          color: _pens(c)[_pen % _inkChoices],
                          erasing: _erasing,
                          onChanged: (strokes) => _write(strokes, canvas),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gün ileri/geri ve "bugüne dön".
class _DayNav extends StatelessWidget {
  const _DayNav({
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final VoidCallback onPrev;
  final VoidCallback onNext;

  /// Zaten bugündeysek `null` — pasif düğme, "buradasın" demenin en sessiz yolu.
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrev,
          tooltip: 'Önceki gün',
          icon: Icon(Icons.chevron_left_rounded, size: I.lg, color: c.inkDim),
        ),
        TextButton(
          onPressed: onToday,
          child: Text(
            'Bugün',
            style: TextStyle(
              color: onToday == null ? c.inkFaint : c.accent,
              fontSize: T.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Sonraki gün',
          icon: Icon(Icons.chevron_right_rounded, size: I.lg, color: c.inkDim),
        ),
      ],
    );
  }
}

/// Kalemler, silgi, geri al, temizle.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.pens,
    required this.selectedPen,
    required this.erasing,
    required this.canUndo,
    required this.isSaving,
    required this.onPen,
    required this.onErase,
    required this.onUndo,
    required this.onClear,
  });

  final List<Color> pens;
  final int selectedPen;
  final bool erasing;
  final bool canUndo;
  final bool isSaving;
  final ValueChanged<int> onPen;
  final VoidCallback onErase;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.gutter),
      child: Row(
        children: [
          for (var i = 0; i < pens.length; i++) ...[
            _PenDot(
              color: pens[i],
              selected: !erasing && i == selectedPen,
              onTap: () => onPen(i),
            ),
            const SizedBox(width: S.sm),
          ],
          const SizedBox(width: S.sm),
          _ToolButton(
            icon: Icons.auto_fix_normal_rounded,
            label: 'Silgi',
            active: erasing,
            onTap: onErase,
          ),
          const SizedBox(width: S.sm),
          // Saving Indicator
          AnimatedOpacity(
            opacity: isSaving ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.cloud_done_rounded,
              color: context.colors.inkFaint,
              size: I.sm,
            ),
          ),
          const Spacer(),
          _ToolButton(
            icon: Icons.undo_rounded,
            label: 'Geri al',
            onTap: canUndo ? onUndo : null,
          ),
          const SizedBox(width: S.sm),
          _ToolButton(
            icon: Icons.delete_outline_rounded,
            label: 'Temizle',
            onTap: canUndo ? onClear : null,
            danger: true,
          ),
        ],
      ),
    );
  }
}

class _PenDot extends StatelessWidget {
  const _PenDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          width: I.lg,
          height: I.lg,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            // Seçili kalem, kendi rengiyle parlar — parıltının üç yerinden
            // biri değil, o yüzden halka ile anlatılıyor.
            border: Border.all(
              color: selected ? c.ink : c.lineSoft,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;

  /// `null` ise düğme pasif — yapılacak bir şey yokken tıklanabilir durmasın.
  final VoidCallback? onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onTap == null;

    final tint = disabled
        ? c.inkFaint
        : danger
        ? c.danger
        : active
        ? c.onAccent
        : c.inkDim;

    return Tooltip(
      message: label,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.sm,
            ),
            decoration: BoxDecoration(
              color: active ? c.accent : c.surface,
              borderRadius: R.radiusPill,
              border: Border.all(color: active ? c.accent : c.lineSoft),
            ),
            child: Icon(icon, size: I.md, color: tint),
          ),
        ),
      ),
    );
  }
}
