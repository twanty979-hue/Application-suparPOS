import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';

class QuotaHistoryModal extends StatelessWidget {
  final List<dynamic> history;

  const QuotaHistoryModal({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    // Sort by date ascending
    final sortedHistory = List<dynamic>.from(history)
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    double maxCount = 0;
    for (var item in sortedHistory) {
      final count = (item['count'] as num).toDouble();
      if (count > maxCount) maxCount = count;
    }
    // Pad maxCount so chart doesn't look squished
    maxCount = maxCount < 10 ? 10 : maxCount * 1.2;

    return Container(
      width: double.infinity,
      height: 500,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ประวัติการใช้งาน QR บิล (30 วัน)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.slate800,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: AppColors.slate400),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: sortedHistory.isEmpty
                ? const Center(
                    child: Text(
                      'ไม่มีข้อมูลประวัติ',
                      style: TextStyle(color: AppColors.slate400),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxCount,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppColors.slate800,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final dateStr = sortedHistory[group.x.toInt()]['date'];
                            final date = DateTime.parse(dateStr);
                            final formattedDate =
                                DateFormat('dd MMM', 'th').format(date);
                            return BarTooltipItem(
                              '$formattedDate\n${rod.toY.toInt()} บิล',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Kanit',
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= sortedHistory.length) {
                                return const SizedBox.shrink();
                              }
                              // แสดงวันที่แค่หัวกับท้าย (วันเริ่มนับ กับ วันสิ้นสุด)
                              if (index == 0 || index == sortedHistory.length - 1) {
                                final dateStr = sortedHistory[index]['date'];
                                final date = DateTime.parse(dateStr);
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    DateFormat('dd/MM').format(date),
                                    style: const TextStyle(
                                      color: AppColors.slate400,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxCount / 5,
                        getDrawingHorizontalLine: (value) {
                          return const FlLine(
                            color: AppColors.slate100,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: sortedHistory.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final count = (item['count'] as num).toDouble();
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: count,
                              color: count > 0
                                  ? const Color(0xFF6366F1)
                                  : AppColors.slate200,
                              width: 8,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
