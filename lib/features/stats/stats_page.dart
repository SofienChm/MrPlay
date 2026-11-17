import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/stats_repository.dart';

/// Watch time: total, last 14 days, and per platform.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  @override
  Widget build(BuildContext context) {
    final stats = ref.read(statsRepositoryProvider);
    final days = _lastDays(stats.daily, 14);
    final platforms = stats.platforms.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = stats.totalSeconds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch Stats'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TotalCard(seconds: total),
          const SizedBox(height: 24),
          Text('Last 14 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: days.every((d) => d.seconds == 0)
                ? const Center(child: Text('No watch time recorded yet'))
                : _DailyChart(days: days),
          ),
          const SizedBox(height: 24),
          Text('By platform', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (platforms.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No platform data yet')),
            )
          else
            for (final p in platforms)
              _PlatformRow(name: p.key, seconds: p.value, fraction: total == 0 ? 0 : p.value / total),
        ],
      ),
    );
  }

  static List<({DateTime day, int seconds})> _lastDays(Map<String, int> daily, int count) {
    final today = DateTime.now();
    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final day = DateTime(today.year, today.month, today.day - i);
          return (day: day, seconds: daily[StatsRepository.dayKey(day)] ?? 0);
        }(),
    ];
  }
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 40, color: scheme.primary),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total watch time', style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  formatDuration(seconds),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days});

  final List<({DateTime day, int seconds})> days;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final maxMinutes = days.map((d) => d.seconds / 60).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxMinutes <= 0 ? 1 : maxMinutes * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              formatDuration(days[group.x].seconds),
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length || i.isOdd) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${days[i].day.day}/${days[i].day.month}', style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].seconds / 60,
                  color: color,
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({required this.name, required this.seconds, required this.fraction});

  final String name;
  final int seconds;
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name)),
                Text(formatDuration(seconds), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0), minHeight: 6),
            ),
          ],
        ),
      );
}
