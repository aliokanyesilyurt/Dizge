import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../models/task.dart';
import '../services/productivity_report.dart';
import '../theme.dart';
import '../widgets/report_charts.dart';
import 'section_header.dart';

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
    final tasks = ref.watch(appStoreProvider).tasks;
    final report = ProductivityReport.build(tasks, days: _days);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
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
            const Divider(color: AppColors.lineSoft, height: 1),
            Expanded(
              child: report.planned == 0
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      children: [
                        _OverviewCard(report: report),
                        const SizedBox(height: 14),
                        _Card(
                          title: 'Kategoriye göre zaman',
                          child: HBarChart(
                            rows: [
                              for (final b in report.byCategory.take(6))
                                HBarRow(b.label, b.color, b.hours,
                                    Task.formatDuration(b.hours)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Card(
                          title: 'Etikete göre zaman',
                          child: HBarChart(
                            rows: [
                              for (final b in report.byTag.take(6))
                                HBarRow(
                                    '#${b.label}',
                                    AppColors.blue,
                                    b.hours,
                                    Task.formatDuration(b.hours)),
                            ],
                            emptyText:
                                'Görevlere etiket ekleyince burada dağılım çıkar.',
                          ),
                        ),
                        const SizedBox(height: 14),
                        _WeekdayCard(report: report),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 34, color: AppColors.inkFaint),
            SizedBox(height: 12),
            Text(
              'Rapor için yeterli veri yok.\nBirkaç görev ekleyip tamamlayınca grafikler dolar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.inkFaint,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _OverviewCard extends StatelessWidget {
  final ProductivityReport report;
  const _OverviewCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Tamamlanma',
      child: Row(
        children: [
          CompletionRing(
            value: report.completionRate,
            caption: 'zamanında',
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Metric(
                  value: '${report.completed}',
                  label: 'tamamlanan görev',
                  color: AppColors.blue,
                ),
                const SizedBox(height: 12),
                _Metric(
                  value: '${report.planned - report.completed}',
                  label: 'açık / kaçan',
                  color: AppColors.pink,
                ),
                const SizedBox(height: 12),
                _Metric(
                  value: '${report.planned}',
                  label: 'planlanan toplam',
                  color: AppColors.inkDim,
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
        color: AppColors.blue,
        highlightIndex: worst,
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Metric(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.inkDim,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 14),
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
    Widget chip(int d, String label) {
      final sel = days == d;
      return GestureDetector(
        onTap: () => onChanged(d),
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? AppColors.blue.withValues(alpha: 0.18) : AppColors.hover,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: sel ? AppColors.blue : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: sel ? AppColors.blue : AppColors.inkDim,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [chip(7, '7g'), chip(30, '30g'), chip(90, '90g')],
    );
  }
}
