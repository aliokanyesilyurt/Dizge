import 'package:flutter/material.dart';

import '../theme.dart';

/// "Yaptım" işareti — uygulamanın tek onay kutusu.
///
/// ## Neden ayrı bir widget
///
/// Tamamlama, uygulamada en sık yapılan hareket ve dört ayrı yüzeyde
/// bulunuyor: Yapılacaklar listesi, Rutinler listesi, haftalık ızgaranın blok
/// önizlemesi ve aylık takvim hücresi. Her biri kendi onay kutusunu çizseydi
/// dördü de biraz farklı olurdu — ve "bu ikisi aynı şey mi" sorusu, en sık
/// yapılan hareketin üstünde asılı kalırdı.
///
/// Görsel dil tek: boşken ince halka, doluyken vurgu renginde dolu daire ve
/// içinde ✓. Renk tek başına taşımıyor (WCAG 1.4.1) — işaretin kendisi de
/// değişiyor.
///
/// ## Hangi gün
///
/// Kutu bir işi değil, bir işin **bir gününü** işaretler. Rutinlerde bu ayrım
/// görünür olmak zorunda: onu söylemek çağıranın işi (bkz.
/// `TaskListScaffold.checkScopeLabel`), çünkü "hangi gün" bilgisi kutunun
/// kendisinde değil, kutunun durduğu ekranda.
class TaskCheck extends StatefulWidget {
  const TaskCheck({
    super.key,
    required this.done,
    required this.onToggle,
    this.label,
    this.compact = false,
  });

  final bool done;
  final VoidCallback onToggle;

  /// Ekran okuyucunun okuyacağı ad. Verilmezse yalnız "Tamamlandı" durumu
  /// duyulur — listede satırın kendisi zaten adı söylüyorsa bu yeterli.
  final String? label;

  /// Yoğun yüzeylerde (takvim hücresi) daha küçük çizilir.
  final bool compact;

  @override
  State<TaskCheck> createState() => _TaskCheckState();
}

class _TaskCheckState extends State<TaskCheck> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = widget.done;
    final box = widget.compact ? I.xs : I.md;
    final mark = widget.compact ? I.xs : I.sm;

    return Semantics(
      checked: done,
      label: widget.label,
      // Onay kutusu, düğme değil: ekran okuyucu "işaretli/işaretsiz" diye
      // okusun ki durumu duyulsun.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onToggle,
          // Görünen halka küçük, dokunulan alan değil: çevresindeki boşluk
          // hedefin parçası.
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.all(widget.compact ? S.hair : S.sm),
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.curve,
              width: box,
              height: box,
              decoration: BoxDecoration(
                color: done ? c.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done ? c.accent : (_hovered ? c.accent : c.line),
                  width: 1.5,
                ),
              ),
              child: done
                  ? Icon(Icons.check_rounded, size: mark, color: c.onAccent)
                  // Boşken de üstüne gelince soluk bir ✓ beliriyor: kutunun
                  // tıklanabilir olduğunu söyleyen tek işaret bu.
                  : (_hovered
                        ? Icon(Icons.check_rounded, size: mark, color: c.accent)
                        : null),
            ),
          ),
        ),
      ),
    );
  }
}
