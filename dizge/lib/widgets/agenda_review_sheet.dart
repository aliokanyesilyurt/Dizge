import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/handwriting_recognizer.dart';
import '../core/ink_lines.dart';
import '../data/app_store.dart';
import '../models/agenda_page.dart';
import '../models/task.dart';
import '../theme.dart';

/// Ajanda sayfasını görevlere çeviren onay şeridi (A8).
///
/// ## Tanıma asla sessizce görev oluşturmaz
///
/// Plan §Ab'nin tamamı burada yaşıyor. El yazısı tanıma en iyi hâlinde bile
/// yanılır; "Salı toplantı" yerine "Sali toplant" üreten bir motor sessizce
/// görev yaratırsa kullanıcı ajandasına güvenmeyi bırakır. Bu yüzden akış
/// şöyle: **yazı → satırlar → düzenlenebilir öneri → kullanıcı onayı → görev.**
///
/// ## Mürekkep her hâlükârda kalır
///
/// Bu şerit sayfaya dokunmaz. Görev oluşsa da oluşmasa da yazı yerinde durur;
/// ajanda önce bir defterdir, sonra bir girdi yöntemi.
///
/// ## Tanıma yokken de çalışır
///
/// [UnavailableRecognizer] ile satırlar yine ayrılır ve her satır için boş bir
/// başlık alanı açılır. Kullanıcı "üç satır yazdım" bilgisini kaybetmez;
/// yalnız başlıkları kendisi yazar.
Future<int?> showAgendaReview(
  BuildContext context, {
  required AgendaPage page,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AgendaReviewSheet(page: page),
  );
}

class _AgendaReviewSheet extends ConsumerStatefulWidget {
  const _AgendaReviewSheet({required this.page});

  final AgendaPage page;

  @override
  ConsumerState<_AgendaReviewSheet> createState() => _AgendaReviewSheetState();
}

class _AgendaReviewSheetState extends ConsumerState<_AgendaReviewSheet> {
  late final List<InkLine> _lines = splitIntoLines([
    for (final s in widget.page.strokes) s.points,
  ]);

  /// Satır başına bir başlık alanı — **daha ilk karede**. Tanımayı bekleyip
  /// sonra açmak, model inerken kullanıcıyı boş bir ekranla baş başa
  /// bırakıyordu; oysa kaç satır yazdığını motor olmadan da biliyoruz.
  late final List<TextEditingController> _titles = [
    for (var i = 0; i < _lines.length; i++) TextEditingController(),
  ];

  /// Hangi satırların göreve çevrileceği. Varsayılan **hepsi seçili**:
  /// kullanıcı zaten yazdığı şeyi göreve çevirmek için bu şeridi açtı.
  late final List<bool> _selected = List.filled(_lines.length, true);

  /// Tanıma hâlâ sürüyor mu — yalnız altyazının cümlesini değiştirir.
  /// Listeyi **bekletmez**: kullanıcı okuma bitmeden de yazmaya başlayabilir.
  bool _recognizing = true;

  /// Motorun hâli **şeridin açıldığı andaki** hâli, sonra tanıma bitince
  /// güncelleniyor. Provider'ı izlemek işe yaramazdı: değişen şey motorun
  /// içindeki bir alan, provider'ın değeri değil.
  late RecognizerState _state = ref.read(handwritingRecognizerProvider).state;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    final recognizer = ref.read(handwritingRecognizerProvider);

    // Android'de model ilk kullanımda iniyor. `warmUp` idempotent — açılışta
    // bootstrap da çağırdı; buradaki çağrı aynı işe biniyor, ikinci indirme
    // başlatmıyor.
    await recognizer.warmUp();
    if (!mounted) return;
    // İndirme bitti: altyazı "indiriliyor"dan "okunuyor"a geçsin.
    setState(() => _state = recognizer.state);

    final texts = await recognizer.recognizeLines(_lines);

    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _titles.length && i < texts.length; i++) {
        // Beklerken yazmaya başlamış olabilir. Tanımanın kullanıcının yazdığı
        // başlığın üstüne geçmesi, §Ab'nin "sessizce" yasağının bir başka
        // biçimi olurdu.
        if (_titles[i].text.isEmpty) _titles[i].text = texts[i];
      }
      _state = recognizer.state;
      _recognizing = false;
    });
  }

  @override
  void dispose() {
    for (final controller in _titles) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Oluşturulacak görev sayısı — düğmenin yazdığı sayı ile [_create]'in
  /// gerçekte ürettiği sayı aynı kuraldan okunuyor ki ikisi ayrışmasın.
  int get _readyCount {
    var n = 0;
    for (var i = 0; i < _titles.length; i++) {
      if (_selected[i] && _titles[i].text.trim().isNotEmpty) n++;
    }
    return n;
  }

  void _create() {
    final store = ref.read(appStoreProvider);
    final category = AppData.categories.first;

    var created = 0;
    for (var i = 0; i < _titles.length; i++) {
      if (!_selected[i]) continue;

      final title = _titles[i].text.trim();
      // Başlıksız satır göreve çevrilmez. Tanıma okuyamamış ve kullanıcı da
      // yazmamışsa ortada bir iş yok — boş başlıklı bir görev üretmek,
      // sessizce yanlış görev üretmenin başka bir biçimi olurdu.
      if (title.isEmpty) continue;

      store.addTask(
        Task(
          title: title,
          color: category.color,
          categoryName: category.name,
          date: widget.page.day,
        ),
      );
      created++;
    }

    Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Kaç görev oluşacağı: **seçili ve başlığı dolu** satırlar. Yalnız dolu
    // başlıkları saymak, kapatılan satırı düğmenin sayısında bırakıyordu.
    final ready = _readyCount;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
          boxShadow: c.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: S.md),
            Container(
              width: I.xl,
              height: S.xs,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: R.radiusPill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sayfadan görevler',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: S.xs),
                  Text(
                    _subtitle(),
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: T.caption,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        S.xl,
                        S.sm,
                        S.xl,
                        S.xl,
                      ),
                      child: Text(
                        'Bu sayfada henüz yazı yok.',
                        style: TextStyle(
                          color: c.inkFaint,
                          fontSize: T.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(S.xl, 0, S.xl, S.md),
                      itemCount: _lines.length,
                      itemBuilder: (_, i) => _LineRow(
                        index: i,
                        controller: _titles[i],
                        selected: _selected[i],
                        onToggle: (v) => setState(() => _selected[i] = v),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.xl, S.sm, S.xl, S.xl),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // Mürekkebin kalacağını burada, karar anında söylüyoruz.
                      'Yazı sayfada kalır.',
                      style: TextStyle(
                        color: c.inkFaint,
                        fontSize: T.micro,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: S.sm),
                  FilledButton(
                    onPressed: ready == 0 ? null : _create,
                    child: Text(
                      ready == 0 ? 'Görev oluştur' : '$ready görev oluştur',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Üç hâl, üç cümle. "Hazırlanıyor"u "kapalı"ya katmak yalan olurdu:
  /// kullanıcı tanımanın hiç gelmeyeceğini sanıp bir daha denemezdi.
  String _subtitle() {
    if (_lines.isEmpty) return 'Önce sayfaya bir şeyler yaz.';

    final count = '${_lines.length} satır bulundu.';

    return switch (_state) {
      RecognizerState.unavailable =>
        '$count Tanıma bu cihazda kapalı — başlıkları yazarak ekleyebilirsin.',
      RecognizerState.preparing =>
        '$count Tanıma modeli indiriliyor — bu bir kereliğine. '
            'Beklemeden başlıkları yazabilirsin.',
      RecognizerState.ready when _recognizing => '$count Yazı okunuyor…',
      RecognizerState.ready =>
        '$count Okunanı düzeltebilir, istemediğini kapatabilirsin.',
    };
  }
}

/// Tek bir satırın önerisi: seçim kutusu + düzenlenebilir başlık.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.index,
    required this.controller,
    required this.selected,
    required this.onToggle,
    required this.onChanged,
  });

  final int index;
  final TextEditingController controller;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: (v) => onToggle(v ?? false)),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              enabled: selected,
              style: TextStyle(
                color: c.ink,
                fontSize: T.body,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: '${index + 1}. satır',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
