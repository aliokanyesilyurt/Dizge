import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connectivity.dart';
import '../core/telemetry.dart';
import '../theme.dart';
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

/// Kenar çubuğunun açtığı bölümler.
enum AppSection {
  year,
  month,
  week,
  hour,
  routines,
  todos,
  notes,
  habits,
  reports,
  account,
}

class _NavItem {
  final AppSection section;
  final IconData icon;
  final String label;
  const _NavItem(this.section, this.icon, this.label);
}

const _calendarItems = [
  _NavItem(AppSection.year, Icons.grid_view_outlined, 'Yıllık'),
  _NavItem(AppSection.month, Icons.calendar_month_outlined, 'Aylık'),
  _NavItem(AppSection.week, Icons.view_week_outlined, 'Haftalık'),
  _NavItem(AppSection.hour, Icons.schedule_outlined, 'Saatlik'),
];

const _listItems = [
  _NavItem(AppSection.routines, Icons.repeat_rounded, 'Rutinler'),
  _NavItem(AppSection.todos, Icons.checklist_rounded, 'Yapılacaklar'),
];

const _knowledgeItems = [
  _NavItem(AppSection.notes, Icons.description_outlined, 'Notlar'),
  _NavItem(AppSection.habits, Icons.local_fire_department_outlined, 'Alışkanlıklar'),
  _NavItem(AppSection.reports, Icons.insights_outlined, 'Raporlar'),
];

/// Kalıcı kenar çubuğu + içerik alanı. Dar ekranda çubuk Drawer'a düşer.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Açılış bölümü: haftalık görünüm. Uygulamanın ana ekranı budur — kullanıcı
  /// açtığında "bu hafta ne var" sorusunun cevabıyla karşılaşır.
  AppSection _section = AppSection.week;
  bool _collapsed = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _breakpoint = 900.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _trackScreen(_section);
    });
  }

  void _trackScreen(AppSection s) =>
      ref.read(telemetryProvider).screen(s.name);

  void _select(AppSection s) {
    if (s != _section) _trackScreen(s);
    setState(() => _section = s);
    // Drawer açıksa (dar ekran) seçimden sonra kapansın.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Widget _contentFor(AppSection s) {
    switch (s) {
      case AppSection.year:
        return const YearViewScreen();
      case AppSection.month:
        return const MonthlyViewScreen();
      case AppSection.week:
        return const WeekViewScreen();
      case AppSection.hour:
        return DayViewScreen(date: DateTime.now());
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
    final wide = MediaQuery.sizeOf(context).width >= _breakpoint;

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_section),
        child: _contentFor(_section),
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: AppColors.sidebar,
              child: _Sidebar(selected: _section, onSelect: _select),
            ),
      appBar: wide
          ? null
          : AppBar(
              backgroundColor: AppColors.sidebar,
              title: const Text('Program & Takvim'),
            ),
      body: Row(
        children: [
          if (wide)
            _Sidebar(
              selected: _section,
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
    final status = ref.watch(networkStatusProvider).valueOrNull;
    final offline = status == NetworkStatus.offline;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: offline
          ? Container(
              width: double.infinity,
              color: AppColors.surfaceAlt,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 13, color: AppColors.inkFaint),
                  SizedBox(width: 7),
                  Text(
                    'Çevrimdışı — değişiklikler cihazda saklanıyor',
                    style: TextStyle(
                      color: AppColors.inkFaint,
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

  static const _expandedWidth = 248.0;
  static const _collapsedWidth = 68.0;

  @override
  Widget build(BuildContext context) {
    final targetWidth = collapsed ? _collapsedWidth : _expandedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: targetWidth,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.lineSoft)),
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      if (!collapsed) const _SectionLabel('Takvim'),
                      for (final item in _calendarItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: 14),
                      if (!collapsed) const _SectionLabel('Listeler'),
                      for (final item in _listItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                      const SizedBox(height: 14),
                      if (!collapsed) const _SectionLabel('Bilgi & Analiz'),
                      for (final item in _knowledgeItems)
                        _NavTile(
                          item: item,
                          selected: selected == item.section,
                          collapsed: collapsed,
                          onTap: () => onSelect(item.section),
                        ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.lineSoft, height: 1),
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
    final logo = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.blue, AppColors.pink],
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
    );

    final toggle = onToggle == null
        ? null
        : IconButton(
            onPressed: onToggle,
            tooltip: collapsed ? 'Menüyü genişlet' : 'Menüyü daralt',
            iconSize: 18,
            splashRadius: 18,
            icon: Icon(
              collapsed ? Icons.chevron_right : Icons.chevron_left,
              color: AppColors.inkDim,
            ),
          );

    // Daraltılmışken logo yerine doğrudan genişletme düğmesi dursun.
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
        child: Column(
          children: [
            logo,
            if (toggle != null) ...[const SizedBox(height: 6), toggle],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Program',
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.inkFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
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
    final selected = widget.selected;
    final collapsed = widget.collapsed;

    final icon = Icon(
      widget.item.icon,
      size: 18,
      color: selected ? AppColors.ink : AppColors.inkDim,
    );

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            gradient: selected ? kActiveGradient : null,
            color: selected
                ? null
                : (_hovered ? AppColors.sidebarHover : Colors.transparent),
            borderRadius: BorderRadius.circular(999),
          ),
          child: collapsed
              ? Center(child: icon)
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: selected ? AppColors.ink : AppColors.inkDim,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    // Daraltılmışken etiket görünmediği için adı ipucu olarak ver.
    return collapsed
        ? Tooltip(message: widget.item.label, child: tile)
        : tile;
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
    const avatar = CircleAvatar(
      radius: 15,
      backgroundColor: AppColors.hover,
      child: Icon(Icons.person_outline, size: 17, color: AppColors.inkDim),
    );

    final tile = InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.sidebarActive : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 14,
          vertical: 12,
        ),
        child: collapsed
            ? const Center(child: avatar)
            : const Row(
                children: [
                  avatar,
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Misafir',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Hesap ayarları',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: AppColors.inkFaint,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.settings_outlined,
                      size: 16, color: AppColors.inkFaint),
                ],
              ),
      ),
    );

    return collapsed
        ? Tooltip(message: 'Hesap ayarları', child: tile)
        : tile;
  }
}
