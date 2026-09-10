import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_service.dart';
import '../core/connectivity.dart';
import '../core/group_context.dart';
import '../core/navigation_controller.dart';
import '../core/pool_labels.dart';
import '../core/profile_directory.dart';
import '../core/telemetry.dart';
import '../core/theme_mode_controller.dart';
import '../core/usage_mode_controller.dart';
import '../data/app_store.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/group_switcher.dart';
import '../widgets/user_avatar.dart';
import 'account_screen.dart';
import 'agenda_screen.dart';
import 'day_view_screen.dart';
import 'habits_screen.dart';
import 'monthly_view_screen.dart';
import 'notes_screen.dart';
import 'pool_screen.dart';
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

/// Ajanda, takvimin başında duruyor: gün yaprağı en dar zaman birimi ve
/// kalemle yazan biri oraya en sık gidiyor. Kenar çubuğunda görünmesi
/// kullanım moduna bağlı ([UsageMode.showsAgenda]).
const _agendaItem = _NavItem(AppSection.agenda, Icons.draw_rounded, 'Ajanda');

const _calendarItems = [
  _NavItem(AppSection.year, Icons.grid_view_rounded, 'Yıllık'),
  _NavItem(AppSection.month, Icons.calendar_month_rounded, 'Aylık'),
  _NavItem(AppSection.week, Icons.view_week_rounded, 'Haftalık'),
  _NavItem(AppSection.hour, Icons.schedule_rounded, 'Saatlik'),
];

const _listItems = [
  _NavItem(AppSection.routines, Icons.repeat_rounded, 'Rutinler'),
  _NavItem(AppSection.todos, Icons.checklist_rounded, 'Yapılacaklar'),
  // Havuzun ikinci kapısı. Haftalık şerit boşken hiç görünmüyor; burası
  // her zaman duruyor ki özellik keşfedilebilsin (plan K4).
  _NavItem(AppSection.pool, Icons.inbox_rounded, kPoolName),
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
      // Adlar da aynı anda (Y4.4d): profiller yalnız grup bağlamında görünüyor,
      // onlara ayrı bir tazeleme takvimi icat etmeye değmez.
      unawaited(ref.read(profileDirectoryProvider.notifier).refresh());
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
      case AppSection.agenda:
        return AgendaScreen(initialDay: nav.day);
      case AppSection.year:
        return YearViewScreen(year: nav.anchor?.year);
      case AppSection.month:
        return MonthlyViewScreen(initialMonth: nav.anchor);
      case AppSection.week:
        return const WeekViewScreen();
      case AppSection.hour:
        return DayViewScreen(date: nav.day ?? DateTime.now());
      case AppSection.routines:
        return const RoutinesScreen();
      case AppSection.todos:
        return const TodosScreen();
      case AppSection.pool:
        return const PoolScreen();
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

  int _bottomNavIndex(AppSection s) {
    if (s == AppSection.week ||
        s == AppSection.month ||
        s == AppSection.year ||
        s == AppSection.hour) {
      return 0;
    }
    if (s == AppSection.agenda) return 1;
    if (s == AppSection.todos || s == AppSection.routines) return 2;
    if (s == AppSection.pool) return 3;
    return 4;
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
              actions: const [
                _ThemeToggleButton(),
                SizedBox(width: S.xs),
              ],
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
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _bottomNavIndex(nav.section),
              onDestinationSelected: (index) {
                if (index == 0) _select(AppSection.month);
                if (index == 1) _select(AppSection.agenda);
                if (index == 2) _select(AppSection.todos);
                if (index == 3) _select(AppSection.pool);
                if (index == 4) _scaffoldKey.currentState?.openDrawer();
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.view_week_rounded),
                  label: 'Takvim',
                ),
                NavigationDestination(
                  icon: Icon(Icons.draw_rounded),
                  label: 'Ajanda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.checklist_rounded),
                  label: 'İşler',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inbox_rounded),
                  label: 'Havuz',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_rounded),
                  label: 'Menü',
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
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_rounded, size: I.xs, color: c.inkFaint),
                  const SizedBox(width: S.sm),
                  Text(
                    'Çevrimdışı — değişiklikler cihazda saklanıyor',
                    style: TextStyle(
                      color: c.inkFaint,
                      fontSize: T.micro,
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

class _Sidebar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final targetWidth = collapsed ? _collapsedWidth : _expandedWidth;
    // Ajanda sekmesi klasik modda hiç çizilmez: klavyeyle çalışan biri için
    // orada bir defter durması gürültüdür.
    final showAgenda = ref.watch(usageModeProvider).showsAgenda;
    // Havuz rozeti: sayı canlı, çünkü iş haftalık ızgaradan sürüklenerek de
    // havuza düşebiliyor.
    final pooled = ref.watch(poolProvider).length;

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
                    padding: const EdgeInsets.symmetric(horizontal: S.md),
                    children: [
                      if (!collapsed) const _SectionLabel('Takvim'),
                      if (showAgenda)
                        _NavTile(
                          item: _agendaItem,
                          selected: selected == AppSection.agenda,
                          collapsed: collapsed,
                          onTap: () => onSelect(AppSection.agenda),
                        ),
                      for (final item in _calendarItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: S.lg),
                      if (!collapsed) const _SectionLabel('Listeler'),
                      for (final item in _listItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                          // Rozet yalnız havuzda: orada bekleyen iş sayısı,
                          // ekrana girmeden bilinmesi gereken tek sayı.
                          // Ötekiler "kaç işim var" sorusunu zaten başlıkta
                          // cevaplıyor.
                          badge: item.section == AppSection.pool ? pooled : 0,
                        ),
                      const SizedBox(height: S.lg),
                      if (!collapsed) const _SectionLabel('Bilgi & Analiz'),
                      for (final item in _knowledgeItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: S.md),
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
        padding: const EdgeInsets.fromLTRB(0, S.lg, 0, S.md),
        child: Column(
          children: [
            logo,
            if (toggle != null) ...[const SizedBox(height: S.xs), toggle],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.sm, S.md),
      child: Row(
        children: [
          logo,
          const SizedBox(width: S.md),
          Expanded(
            child: Text(
              'Program',
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                color: c.ink,
                fontSize: T.title,
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
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _NavTile extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// Satırın sonundaki sayı. 0 ise çizilmez — "0 iş bekliyor" bilgisi
  /// kimsenin aradığı bir şey değil, yalnız yer kaplar.
  final int badge;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge = 0,
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
          margin: const EdgeInsets.symmetric(vertical: S.hair),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : S.md,
            vertical: S.md,
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
              ? Center(
                  // Daraltılmışken sayı sığmaz; rozet ikonun köşesine
                  // iliştirilmiş bir noktaya iner. Bilgi kaybolmuyor: kaç
                  // olduğu ipucunda yazıyor.
                  child: _BadgedIcon(
                    icon: widget.item.icon,
                    color: ink,
                    badge: widget.badge,
                  ),
                )
              : Row(
                  children: [
                    Icon(widget.item.icon, size: I.md, color: ink),
                    const SizedBox(width: S.md),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: ink,
                          fontSize: T.body,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (widget.badge > 0) _CountBadge(count: widget.badge),
                  ],
                ),
        ),
      ),
    );

    // Daraltılmışken etiket görünmediği için adı ipucu olarak ver. Rozet
    // varsa sayı da ipucuna giriyor: nokta "bir şey var" der, kaç olduğunu
    // demez.
    if (!collapsed) return tile;
    final message = widget.badge > 0
        ? '${widget.item.label} · ${widget.badge}'
        : widget.item.label;
    return Tooltip(message: message, child: tile);
  }
}

/// Kenar çubuğu satırının sonundaki sayı hapı.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      // Çıplak bir sayı ekran okuyucuda "iki" diye okunur ve neyin ikisi
      // olduğunu söylemez.
      label: '$count iş bekliyor',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.hair),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: R.radiusPill,
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: c.accent,
            fontSize: T.micro,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Daraltılmış satırın ikonu; rozet varsa sağ üst köşesinde bir nokta.
class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    required this.icon,
    required this.color,
    required this.badge,
  });

  final IconData icon;
  final Color color;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = Icon(icon, size: I.md, color: color);
    if (badge == 0) return dot;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        dot,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: S.sm,
            height: S.sm,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
        ),
      ],
    );
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
        padding: EdgeInsets.symmetric(vertical: S.sm),
        child: Center(child: _ThemeToggleButton()),
      );
    }

    final c = context.colors;
    final mode = ref.watch(themeModeProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.xs, S.md, S.md),
      child: Container(
        padding: const EdgeInsets.all(S.xs),
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
              size: I.sm,
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
          size: I.md,
          color: c.inkDim,
        ),
      ),
    );
  }
}

class _ProfileTile extends ConsumerWidget {
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final userId = ref.watch(authUserProvider).valueOrNull?.id;
    final me = ref.watch(profileProvider(userId));

    // Kendi avatarın (Y4.4d). Jenerik kişi ikonunun yerine geçiyor: o ikon
    // "bir hesap" diyordu, bu "senin hesabın" diyor.
    //
    // İpucu kapalı: adın zaten iki santim yanında yazıyor.
    final avatar = UserAvatar(
      profile: me,
      userId: userId,
      size: I.xl,
      showTooltip: false,
    );

    final tile = InkWell(
      onTap: onTap,
      hoverColor: c.sidebarHover,
      child: AnimatedContainer(
        duration: Motion.fast,
        color: selected ? c.navActiveFill : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : S.lg,
          vertical: S.md,
        ),
        child: collapsed
            ? Center(child: avatar)
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Profil gelene kadar "Misafir": bir kare boyunca
                          // "Adsız" yazmak, adı gerçekten boş olan biriyle
                          // henüz yüklenmemiş olanı aynı gösterirdi.
                          me?.label ?? 'Misafir',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: T.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Hesap ayarları',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: c.inkFaint,
                            fontSize: T.micro,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.tune_rounded, size: I.sm, color: c.inkFaint),
                ],
              ),
      ),
    );

    return collapsed ? Tooltip(message: 'Hesap ayarları', child: tile) : tile;
  }
}
