import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connectivity.dart';
import '../core/group_context.dart';
import '../core/navigation_controller.dart';
import '../core/telemetry.dart';
import '../core/theme_mode_controller.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/group_switcher.dart';
import 'account_screen.dart';
import 'day_view_screen.dart';
import 'habits_screen.dart';
import 'monthly_view_screen.dart';
import 'notes_screen.dart';
import 'reports_screen.dart';
import 'routines_screen.dart';
import 'todos_screen.dart';
import 'week_view_screen.dart';
import 'year_view_screen.dart';

class _NavItem {
  final AppSection section;
  final IconData icon;
  final String label;
  const _NavItem(this.section, this.icon, this.label);
}

const _calendarItems = [
  _NavItem(AppSection.year, Icons.grid_view_rounded, 'Yıllık'),
  _NavItem(AppSection.month, Icons.calendar_month_rounded, 'Aylık'),
  _NavItem(AppSection.week, Icons.view_week_rounded, 'Haftalık'),
  _NavItem(AppSection.hour, Icons.schedule_rounded, 'Saatlik'),
];

const _listItems = [
  _NavItem(AppSection.routines, Icons.repeat_rounded, 'Rutinler'),
  _NavItem(AppSection.todos, Icons.checklist_rounded, 'Yapılacaklar'),
];

const _knowledgeItems = [
  _NavItem(AppSection.notes, Icons.description_rounded, 'Notlar'),
  _NavItem(
    AppSection.habits,
    Icons.local_fire_department_rounded,
    'Alışkanlıklar',
  ),
  _NavItem(AppSection.reports, Icons.insights_rounded, 'Raporlar'),
];

/// Kalıcı kenar çubuğu + içerik alanı. Dar ekranda çubuk Drawer'a düşer.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _collapsed = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _breakpoint = 900.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackScreen(ref.read(navigationProvider).section);
      // Grup listesi burada tazeleniyor çünkü kabuk yalnız oturum açıkken
      // kuruluyor: hem yeni girişi hem geri yüklenen oturumu tek yer karşılar.
      // Başarısız olursa sessiz — seçicide son bilinen liste kalır (Y4.2).
      unawaited(ref.read(groupContextProvider.notifier).refresh());
    });
  }

  void _trackScreen(AppSection s) => ref.read(telemetryProvider).screen(s.name);

  void _select(AppSection s) {
    if (s != ref.read(navigationProvider).section) _trackScreen(s);
    ref.read(navigationProvider.notifier).go(s);
    // Drawer açıksa (dar ekran) seçimden sonra kapansın.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Widget _contentFor(NavState nav) {
    switch (nav.section) {
      case AppSection.year:
        return const YearViewScreen();
      case AppSection.month:
        return MonthlyViewScreen(initialMonth: nav.month);
      case AppSection.week:
        return const WeekViewScreen();
      case AppSection.hour:
        return DayViewScreen(date: nav.day ?? DateTime.now());
      case AppSection.routines:
        return const RoutinesScreen();
      case AppSection.todos:
        return const TodosScreen();
      case AppSection.notes:
        return const NotesScreen();
      case AppSection.habits:
        return const HabitsScreen();
      case AppSection.reports:
        return const ReportsScreen();
      case AppSection.account:
        return const AccountScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= _breakpoint;
    final nav = ref.watch(navigationProvider);

    final content = AnimatedSwitcher(
      duration: Motion.slow,
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.012),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        // Anahtar bölümü *ve* hedefi taşıyor: yıl görünümünden başka bir aya
        // geçmek aynı bölümde kalır, anahtar yalnız bölüm olsaydı ay ekranı
        // eski ayıyla ayakta kalırdı.
        key: ValueKey(nav),
        child: _contentFor(nav),
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.bg,
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: c.sidebar,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(R.lg),
                ),
              ),
              child: _Sidebar(selected: nav.section, onSelect: _select),
            ),
      appBar: wide
          ? null
          : AppBar(
              backgroundColor: c.bg,
              title: const Text('Program & Takvim'),
              actions: const [_ThemeToggleButton(), SizedBox(width: 6)],
            ),
      body: Row(
        children: [
          if (wide)
            _Sidebar(
              selected: nav.section,
              onSelect: _select,
              collapsed: _collapsed,
              onToggleCollapse: () => setState(() => _collapsed = !_collapsed),
            ),
          Expanded(
            child: Column(
              children: [
                const _OfflineBanner(),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cihaz çevrimdışıyken görünen ince şerit.
///
/// Amacı korkutmak değil güven vermek: offline-first bir uygulamada bağlantı
/// yokluğu bir hata değil, normal bir durumdur. Bu yüzden kırmızı uyarı değil,
/// nötr tonda "kaydediliyor, sonra eşitlenecek" mesajı.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = ref.watch(networkStatusProvider).valueOrNull;
    final offline = status == NetworkStatus.offline;

    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.curve,
      child: offline
          ? Container(
              width: double.infinity,
              color: c.surface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 13, color: c.inkFaint),
                  const SizedBox(width: 8),
                  Text(
                    'Çevrimdışı — değişiklikler cihazda saklanıyor',
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  /// Daraltılmış halde yalnızca ikonlar görünür.
  final bool collapsed;

  /// Drawer'da (dar ekran) daraltma anlamsız olduğu için null geçilir.
  final VoidCallback? onToggleCollapse;

  const _Sidebar({
    required this.selected,
    required this.onSelect,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  static const _expandedWidth = 258.0;
  static const _collapsedWidth = 74.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final targetWidth = collapsed ? _collapsedWidth : _expandedWidth;

    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.curve,
      width: targetWidth,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.lineSoft)),
      ),
      // Genişlik animasyon boyunca ara değerler alır; içerik ise anında son
      // haline geçer. İçeriği hedef genişlikte ölçüp taşanı kırpmazsak ara
      // karelerde RenderFlex taşması olur.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: targetWidth,
          maxWidth: targetWidth,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(collapsed: collapsed, onToggle: onToggleCollapse),
                GroupSwitcher(collapsed: collapsed),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      if (!collapsed) const _SectionLabel('Takvim'),
                      for (final item in _calendarItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: 18),
                      if (!collapsed) const _SectionLabel('Listeler'),
                      for (final item in _listItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: 18),
                      if (!collapsed) const _SectionLabel('Bilgi & Analiz'),
                      for (final item in _knowledgeItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                _ThemeRow(collapsed: collapsed),
                Divider(color: c.lineSoft, height: 1),
                _ProfileTile(
                  selected: selected == AppSection.account,
                  collapsed: collapsed,
                  onTap: () => onSelect(AppSection.account),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool collapsed;
  final VoidCallback? onToggle;

  const _Brand({required this.collapsed, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Karşılama ekranıyla ortak (bkz. widgets/brand_mark.dart).
    const logo = BrandMark();

    final toggle = onToggle == null
        ? null
        : IconButton(
            onPressed: onToggle,
            tooltip: collapsed ? 'Menüyü genişlet' : 'Menüyü daralt',
            iconSize: 18,
            icon: Icon(
              collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              color: c.inkFaint,
            ),
          );

    // Daraltılmışken logo yerine doğrudan genişletme düğmesi dursun.
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
        child: Column(
          children: [
            logo,
            if (toggle != null) ...[const SizedBox(height: 6), toggle],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 10, 14),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Program',
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                color: c.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          ?toggle,
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _NavTile extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;
    final collapsed = widget.collapsed;
    final ink = selected ? c.navActiveInk : c.inkDim;

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 14,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? c.navActiveFill
                : (_hovered ? c.sidebarHover : Colors.transparent),
            borderRadius: R.radiusPill,
            // Kenar çubuğu zemini tam siyah; seçili hapın koyu camgöbeği
            // dolgusu tek başına yeterince öne çıkmıyordu. Hale onu kaldırıyor.
            boxShadow: selected ? c.glow : null,
          ),
          child: collapsed
              ? Center(child: Icon(widget.item.icon, size: 19, color: ink))
              : Row(
                  children: [
                    Icon(widget.item.icon, size: 19, color: ink),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: ink,
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    // Daraltılmışken etiket görünmediği için adı ipucu olarak ver.
    return collapsed ? Tooltip(message: widget.item.label, child: tile) : tile;
  }
}

// --- Tema anahtarı -----------------------------------------------------------

/// Kenar çubuğunun altındaki görünüm seçici.
///
/// Geniş halde üç seçenekli bir segment (Açık / Koyu / Sistem), daraltılmış
/// halde tek dokunuşluk anahtar.
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: _ThemeToggleButton()),
      );
    }

    final c = context.colors;
    final mode = ref.watch(themeModeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.isDark ? c.sidebarHover : c.hover,
          borderRadius: R.radiusPill,
        ),
        child: Row(
          children: [
            for (final option in _themeOptions)
              Expanded(
                child: _ThemeSegment(
                  icon: option.$1,
                  label: option.$2,
                  selected: mode == option.$3,
                  onTap: () =>
                      ref.read(themeModeProvider.notifier).set(option.$3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _themeOptions = <(IconData, String, ThemeMode)>[
  (Icons.light_mode_rounded, 'Açık', ThemeMode.light),
  (Icons.dark_mode_rounded, 'Koyu', ThemeMode.dark),
  (Icons.brightness_auto_rounded, 'Sistem', ThemeMode.system),
];

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.surfaceAlt : Colors.transparent,
              borderRadius: R.radiusPill,
              boxShadow: selected ? c.shadowSm : null,
            ),
            child: Icon(
              icon,
              size: 15,
              color: selected ? c.navActiveInk : c.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tek dokunuşla açık ↔ koyu. Dar ekranın başlık çubuğunda ve daraltılmış
/// kenar çubuğunda kullanılır.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final platform = MediaQuery.platformBrightnessOf(context);

    return IconButton(
      tooltip: c.isDark ? 'Açık temaya geç' : 'Koyu temaya geç',
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(platform),
      icon: AnimatedSwitcher(
        duration: Motion.base,
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween(begin: 0.6, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          c.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(c.isDark),
          size: 19,
          color: c.inkDim,
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final avatar = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
      child: Icon(Icons.person_rounded, size: 17, color: c.navActiveInk),
    );

    final tile = InkWell(
      onTap: onTap,
      hoverColor: c.sidebarHover,
      child: AnimatedContainer(
        duration: Motion.fast,
        color: selected ? c.navActiveFill : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 16,
          vertical: 13,
        ),
        child: collapsed
            ? Center(child: avatar)
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Misafir',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Hesap ayarları',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.tune_rounded, size: 16, color: c.inkFaint),
                ],
              ),
      ),
    );

    return collapsed ? Tooltip(message: 'Hesap ayarları', child: tile) : tile;
  }
}
