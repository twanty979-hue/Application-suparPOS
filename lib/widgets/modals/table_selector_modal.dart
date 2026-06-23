// lib/widgets/modals/table_selector_modal.dart
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TableSelectorModal {
  // ฟังก์ชันตัวช่วยวาดป้ายบอกความหมายสีสถานะด้านบน
  static Widget _buildStatusIndicator(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.slate500)),
      ],
    );
  }

  static Future<void> show({
    required BuildContext context,
    required List<Map<String, dynamic>> tables,
    required List<Map<String, dynamic>> unpaidOrders,
    required Function(Map<String, dynamic>) onTableSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.80, 
          minChildSize: 0.50,    
          maxChildSize: 0.95,    
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 12),
              child: Column(
                children: [
                  // แถบเทาสำหรับลากปิดโมดอล
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.slate200, 
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  const Row(
                    children: [
                      Icon(Icons.grid_view_rounded, size: 28, color: AppColors.slate800),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("เลือกโต๊ะ", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.slate800)),
                          Text("พิมพ์ QR Code สำหรับสั่งอาหาร", style: TextStyle(fontSize: 13, color: AppColors.slate400, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      _buildStatusIndicator(Colors.green, "ว่าง"),
                      const SizedBox(width: 16),
                      _buildStatusIndicator(AppColors.slate400, "ยังไม่คิดเงิน / มีลูกค้า"),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: tables.isEmpty 
                      ? const Center(child: Text("ไม่มีข้อมูลโต๊ะในระบบ", style: TextStyle(color: AppColors.slate400)))
                      : GridView.builder(
                          controller: scrollController, 
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, 
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.9, 
                          ),
                          itemCount: tables.length,
                          itemBuilder: (context, index) {
                            final table = tables[index];
                            
                            // 🪛 แก้ไขลอจิกเช็คสถานะใหม่แบบละเอียด (แก้ปัญหาเรื่องชนิดข้อมูล String/int/UUID ไม่ตรงกัน)
                            final bool hasUnpaidOrder = unpaidOrders.any((order) {
                              final orderTableId = order['table_id'];
                              final currentTableId = table['id'];
                              
                              if (orderTableId == null || currentTableId == null) return false;
                              
                              // เทียบค่าแบบแปลงเป็น String ทั้งคู่เพื่อตัดปัญหาเรื่อง Type หลุดครับนาย
                              return orderTableId.toString().trim().toLowerCase() == 
                                     currentTableId.toString().trim().toLowerCase();
                            });
                            
                            Color statusColor = hasUnpaidOrder ? AppColors.slate400 : Colors.green;
                            Color cardBgColor = hasUnpaidOrder ? AppColors.bgCard : Colors.white;
                            Color borderColor = hasUnpaidOrder ? AppColors.slate100 : AppColors.slate200;

                            return InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                Navigator.pop(context); 
                                onTableSelected(table); 
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardBgColor,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: borderColor, width: 1.5),
                                  boxShadow: hasUnpaidOrder 
                                      ? [] 
                                      : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 14,
                                      right: 14,
                                      child: Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                      ),
                                    ),
                                    Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(height: 8),
                                          Text(
                                            table['label'] ?? '?',
                                            style: TextStyle(
                                              fontSize: 24, 
                                              fontWeight: FontWeight.w900, 
                                              color: hasUnpaidOrder ? AppColors.slate500 : AppColors.slate800,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: hasUnpaidOrder ? Colors.white : AppColors.bgCard,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              "พิมพ์ QR", 
                                              style: TextStyle(
                                                fontSize: 11, 
                                                fontWeight: FontWeight.bold, 
                                                color: hasUnpaidOrder ? AppColors.slate400 : AppColors.slate600,
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                  // 🔥 เอาปุ่ม "ปิดหน้าต่าง" ด้านล่างออกให้ตามคำขอเรียบร้อยครับนาย!
                ],
              ),
            );
          },
        );
      },
    );
  }
}