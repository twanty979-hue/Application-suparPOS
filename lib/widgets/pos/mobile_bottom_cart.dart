import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class MobileBottomCart extends StatelessWidget {
  final int totalItems;
  final double payableAmount;
  final String Function(double) formatCurrency;
  final VoidCallback onTap;

  const MobileBottomCart({
    super.key,
    required this.totalItems,
    required this.payableAmount,
    required this.formatCurrency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // คงความเตี้ยไว้ด้วย Padding ที่น้อยลง
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), 
      decoration: BoxDecoration(
        color: Colors.white, 
        // นำขอบเส้นตรงด้านบนกลับมา และเอาความโค้งออกให้เป็นสี่เหลี่ยมตามเดิม
        border: const Border(top: BorderSide(color: AppColors.slate100)), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1), 
            blurRadius: 20, 
            offset: const Offset(0, -4)
          )
        ]
      ),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            // Padding ด้านในปุ่มยังคงบางลงครึ่งนึงเหมือนที่ปรับไว้
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.slate800, 
              borderRadius: BorderRadius.circular(12), 
              boxShadow: [
                BoxShadow(
                  color: AppColors.slate800.withOpacity(0.4), 
                  blurRadius: 8, 
                  offset: const Offset(0, 4)
                )
              ]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24, height: 24, 
                      decoration: const BoxDecoration(
                        color: AppColors.orange500, 
                        shape: BoxShape.circle
                      ), 
                      alignment: Alignment.center, 
                      child: Text(
                        "$totalItems", 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
                      )
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "ดูตะกร้า", 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text(
                      "รวม", 
                      style: TextStyle(color: Colors.white70, fontSize: 12)
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatCurrency(payableAmount), 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}