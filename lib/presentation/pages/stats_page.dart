import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../services/playback_stats_service.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, int>> _dailyFuture;
  late Future<Map<String, int>> _platformFuture;
  late Future<int> _totalFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _dailyFuture = PlaybackStatsService.instance.dailyStats();
    _platformFuture = PlaybackStatsService.instance.platformStats();
    _totalFuture = PlaybackStatsService.instance.totalSeconds();
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$h h $m m';
    final s = d.inSeconds.remainder(60);
    return '$m m $s s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch Stats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(_load),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<int>(
            future: _totalFuture,
            builder: (context, snapshot) {
              final seconds = snapshot.data ?? 0;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        _formatDuration(seconds),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total watch time',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Last 14 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: FutureBuilder<Map<String, int>>(
              future: _dailyFuture,
              builder: (context, snapshot) {
                final data = snapshot.data ?? {};
                final days = _lastDays(14, data);
                if (days.every((e) => e == 0)) {
                  return const Center(
                    child: Text('No watch time recorded yet'),
                  );
                }
                return BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: _maxOf(days) * 1.2,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                            BarTooltipItem(
                          _formatDuration(rod.toY.toInt()),
                          const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= days.length) {
                              return const SizedBox.shrink();
                            }
                            final dt = DateTime.now()
                                .subtract(Duration(days: days.length - 1 - index));
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${dt.month}/${dt.day}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      for (var i = 0; i < days.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: days[i].toDouble(),
                              color: Theme.of(context).colorScheme.primary,
                              width: 10,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('By platform', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, int>>(
            future: _platformFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {};
              if (data.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No platform data yet'),
                  ),
                );
              }
              final total = data.values.fold<int>(0, (sum, s) => sum + s);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final entry in data.entries) ...[
                        _PlatformRow(
                          name: entry.key,
                          seconds: entry.value,
                          fraction: total == 0 ? 0 : entry.value / total,
                          color: _platformColor(entry.key),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<double> _lastDays(int count, Map<String, int> data) {
    final now = DateTime.now();
    return [
      for (var i = count - 1; i >= 0; i--)
        _secondsOn(now.subtract(Duration(days: i)), data).toDouble(),
    ];
  }

  int _secondsOn(DateTime day, Map<String, int> data) {
    final key = '${day.year}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return data[key] ?? 0;
  }

  double _maxOf(List<double> values) {
    var max = 1.0;
    for (final v in values) {
      if (v > max) max = v;
    }
    return max;
  }

  Color _platformColor(String name) {
    if (name.contains('YouTube')) return const Color(0xFFFF0000);
    return Theme.of(context).colorScheme.primary;
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.name,
    required this.seconds,
    required this.fraction,
    required this.color,
  });

  final String name;
  final int seconds;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(name)),
            Text(
              '${Duration(seconds: seconds).inMinutes} min',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: fraction, color: color),
      ],
    );
  }
}
