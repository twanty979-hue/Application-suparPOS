import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TableList extends StatelessWidget {
  final List<Map<String, dynamic>> unpaidOrders;
  final Map<String, dynamic>? selectedOrder;
  final ValueChanged<Map<String, dynamic>> onSelectOrder;
  final String Function(double) formatCurrency;

  const TableList({
    super.key,
    required this.unpaidOrders,
    this.selectedOrder,
    required this.onSelectOrder,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      child: unpaidOrders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 96, height: 96, decoration: BoxDecoration(color: AppColors.slate50, shape: BoxShape.circle, border: Border.all(color: AppColors.slate100)), child: const Icon(Icons.receipt_long, size: 40, color: AppColors.slate300)),
                  const SizedBox(height: 16),
                  const Text("ไม่มีรายการค้างชำระ", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate300, letterSpacing: 1)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: unpaidOrders.length,
              itemBuilder: (context, index) {
                final order = unpaidOrders[index];
                final isSelected = selectedOrder?['id'] == order['id'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => onSelectOrder(order),
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.orange50.withOpacity(0.5) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: isSelected ? AppColors.orange500 : AppColors.slate100),
                        boxShadow: isSelected ? [const BoxShadow(color: AppColors.orange100, blurRadius: 10)] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56, height: 56,
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.orange500 : AppColors.slate100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.center,
                                child: Text(order['table_label'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : AppColors.slate600)),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("โต๊ะ ${order['table_label']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.slate800)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(6)),
                                        child: Text("${(order['order_items'] as List).length} ITEMS", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.slate500, letterSpacing: 1)),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.slate300, shape: BoxShape.circle)),
                                      const SizedBox(width: 8),
                                      const Text("Waiting Payment", style: TextStyle(fontSize: 12, color: AppColors.slate400)),
                                    ],
                                  )
                                ],
                              )
                            ],
                          ),
                          Text(formatCurrency(order['total_price']), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isSelected ? AppColors.orange600 : AppColors.slate700)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}