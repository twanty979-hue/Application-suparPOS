// lib/widgets/pos/table_list.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TableList extends StatelessWidget {
  final List<dynamic> unpaidOrders;
  final Map<String, dynamic>? selectedOrder;
  final Function(Map<String, dynamic>?) onSelectOrder;
  final String Function(double) formatCurrency;

  const TableList({
    super.key,
    required this.unpaidOrders,
    required this.selectedOrder,
    required this.onSelectOrder,
    required this.formatCurrency,
  });

  String _shortTableLabel(dynamic label) {
    final text = label?.toString().trim() ?? '?';
    return text.replaceFirst(RegExp(r'^โต๊ะ\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (unpaidOrders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 58,
              color: AppColors.slate300,
            ),
            SizedBox(height: 16),
            Text(
              'ไม่มีรายการค้างชำระ',
              style: TextStyle(
                color: AppColors.slate400,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 20 : 12,
        isDesktop ? 20 : 12,
        isDesktop ? 20 : 12,
        24,
      ),
      itemCount: unpaidOrders.length,
      itemBuilder: (context, index) {
        final order = unpaidOrders[index];
        final isSelected =
            selectedOrder != null && selectedOrder!['id'] == order['id'];
        final itemsCount = (order['order_items'] as List?)?.length ?? 0;
        final total =
            double.tryParse(order['total_price']?.toString() ?? '0') ?? 0;
        final tableLabel = order['table_label'] ?? '-';
        final shortLabel = _shortTableLabel(tableLabel);

        return Container(
          margin: EdgeInsets.only(bottom: isDesktop ? 12 : 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.orange50.withOpacity(0.5)
                : Colors.white,
            borderRadius: BorderRadius.circular(isDesktop ? 24 : 12),
            border: Border.all(
              color: isSelected ? AppColors.orange500 : AppColors.slate100,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppColors.orange500.withOpacity(0.12)
                    : Colors.black.withOpacity(0.035),
                blurRadius: isSelected ? 18 : 12,
                spreadRadius: isSelected ? -1 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isDesktop ? 24 : 12),
              onTap: () {
                if (isSelected) {
                  onSelectOrder(null);
                } else {
                  onSelectOrder(order);
                }
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 20 : 12,
                  vertical: isDesktop ? 18 : 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: isDesktop ? 56 : 44,
                      height: isDesktop ? 56 : 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.orange500
                            : AppColors.slate50,
                        borderRadius: BorderRadius.circular(
                          isDesktop ? 16 : 10,
                        ),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: AppColors.orange500.withOpacity(0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.table_restaurant_rounded,
                          size: isDesktop ? 30 : 24,
                          color: isSelected
                              ? Colors.white
                              : AppColors.slate600,
                        ),
                      ),
                    ),
                    SizedBox(width: isDesktop ? 16 : 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "โต๊ะ $shortLabel",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isDesktop ? 18 : 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.slate800,
                            ),
                          ),
                          SizedBox(height: isDesktop ? 8 : 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.blue50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "$itemsCount ITEMS",
                                  style: TextStyle(
                                    color: AppColors.slate600,
                                    fontSize: isDesktop ? 10 : 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: AppColors.slate300,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Flexible(
                                child: Text(
                                  "Waiting Payment",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.slate400,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isDesktop ? 14 : 10),

                    Text(
                      formatCurrency(total),
                      style: TextStyle(
                        fontSize: isDesktop ? 20 : 16,
                        fontWeight: FontWeight.w900,
                        color: isSelected
                            ? AppColors.orange600
                            : AppColors.slate800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
