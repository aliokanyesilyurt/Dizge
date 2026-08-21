import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../services/productivity_report.dart';
import '../theme.dart';
import '../widgets/content_column.dart';
import '../widgets/report_charts.dart';
import 'section_header.dart';
import 'task_list_scaffold.dart' show EmptyState;

/// Kullanıcı-yüzü performans raporları: tamamlanma oranı, hangi kategoriye/etikete
/// ne kadar zaman harcandığı ve haftanın hangi gününde erteleme arttığı.
/// Tümü mevcut görev verisinden türetilir.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tasks = ref.watch(appStoreProvider).tasks;
    final report = ProductivityReport.build(tasks, days: _days);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ContentColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Raporlar',
                subtitle: 'Son $_days günün üretkenlik özeti',
                trailing: _RangePicker(
                  days: _days,
                  onChanged: (d) => setState(() => _days = d),
                ),
              ),
              Expanded(
                child: report.planned == 0
                    // Boş rapor iki ayrı şeyi anlatabilir: hiç iş yok, ya da
                    // *bu aralıkta* iş yok. İkincisinin çözümü görev eklemek
                    // değil aralığı genişletmek — metin hangisi olduğunu
                    // söylemezse kullanıcı 7g'de takılı kalıp raporu bozuk
                    // sanır.
                    ? EmptyState(
                        icon: Icons.insights_rounded,
                        title: tasks.isEmpty
                            ? 'Rapor için yeterli veri yok.'
                            : 'Son $_days günde iş yok.',
                        text: tasks.isEmpty
                            ? 'Birkaç görev ekleyip tamamlayınca grafikler '
                                  'dolar.'
                            : _days == 90
                            ? 'Bu aralığa düşen planlanmış iş bulunmuyor.'
                            : 'Daha geniş bir aralık seçince eski işler '
                                  'görünebilir.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          S.gutter,
                          S.xs,
                          S.gutter,
                          S.xxl,
                        ),
                        children: [
                          _OverviewCard(report: report),
                          const SizedBox(height: S.md),
                          // Aralığın **görsel** karşılığı bu kart: 7g'de yedi
                          // nokta, 90g'de doksan. Öteki grafikler kendi
                          // maksimumlarına göre ölçeklendiği için aralık
                          // değişince şekilleri değişmiyor; bu değişiyor.
                          _Card(
                            title: 'Günlük gidişat',
                            subtitle:
                                'Boş günlerde çizgi kopuyor — o gün hiç iş '
                                'yoktu, sıfır yapılmadı.',
                            child: TrendChart(
                              values: report.dailyCompletion,
                              color: c.accent,
                            ),
                          ),
                          const SizedBox(height: S.md),
                          _Card(
                            title: 'Kategoriye göre günlük ortalama',
                            subtitle: 'Son $_days günün ortalaması',
                            child: HBarChart(
                              rows: [
                                for (final b in report.byCategory.take(6))
                                  HBarRow(
                                    // Kova anahtarı depolanan ad; ekranda
                                    // görünen adıyla yazılıyor (§Zd).
                                    categoryLabel(b.label),
                                    b.color,
                                    b.perDay,
                                    Task.formatDuration(b.perDay),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: S.md),
                          _Card(
                            title: 'Etikete göre günlük ortalama',
                            subtitle: 'Son $_days günün ortalaması',
                            child: HBarChart(
                              rows: [
                                for (final b in report.byTag.take(6))
                                  HBarRow(
                                    '#${b.label}',
                                    c.accent,
                                    b.perDay,
                                    Task.formatDuration(b.perDay),
                                  ),
                              ],
                              emptyText:
                                  'Görevlere etiket ekleyince burada dağılım çıkar.',
                            ),
                          ),
                          const SizedBox(height: S.md),
                          _WeekdayCard(report: report),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final ProductivityReport report;
  const _OverviewCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return _Card(
      title: 'Tamamlanma',
      child: Row(
        children: [
          CompletionRing(value: report.completionRate, caption: 'zamanında'),
          const SizedBox(width: S.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Metric(
                  value: '${report.completed}',
                  label: 'tamamlanan görev',
                  color: c.accent,
                ),
                const SizedBox(height: S.md),
                _Metric(
                  value: '${report.planned - report.completed}',
                  label: 'açık / kaçan',
                  color: c.secondary,
                ),
                const SizedBox(height: S.md),
                _Metric(
                  value: '${report.planned}',
                  label: 'planlanan toplam',
                  color: c.inkDim,
                ),
                const SizedBox(height: S.md),
                // Aralığa duyarlı tek metrik: üstteki üç sayı aralık uzadıkça
                // zaten büyür, bu büyümez — yoğunluğu söyler.
                _Metric(
                  value: report.plannedPerDay.toStringAsFixed(1),
                  label: 'günde ortalama iş',
                  color: c.inkDim,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  final ProductivityReport report;
  const _WeekdayCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final worst = report.worstWeekday;
    return _Card(
      title: 'Haftaya göre tamamlanma',
      subtitle: worst == null
          ? null
          : 'Erteleme en çok ${ProductivityReport.weekdayNames[worst]} günü artıyor',
      child: VBarChart(
        values: report.weekdayCompletion,
        labels: ProductivityReport.weekdayNames,
        color: context.colors.accent,
        highlightIndex: worst,
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: T.display,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(width: S.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.inkDim,
              fontSize: T.caption,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: R.radiusMd,
        border: Border.all(color: c.lineSoft),
        boxShadow: c.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: S.xs),
              child: Text(
                subtitle!,
                style: TextStyle(
                  color: c.inkFaint,
                  fontSize: T.micro,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: S.lg),
          child,
        ],
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const _RangePicker({required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget chip(int d, String label) {
      final sel = days == d;
      return GestureDetector(
        onTap: () => onChanged(d),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            margin: const EdgeInsets.only(left: S.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.sm,
            ),
            decoration: BoxDecoration(
              color: sel ? c.surfaceAlt : Colors.transparent,
              borderRadius: R.radiusPill,
              boxShadow: sel ? c.shadowSm : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: sel ? c.navActiveInk : c.inkFaint,
                fontSize: T.caption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(S.xs),
      decoration: BoxDecoration(color: c.hover, borderRadius: R.radiusPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [chip(7, '7g'), chip(30, '30g'), chip(90, '90g')],
      ),
    );
  }
}
