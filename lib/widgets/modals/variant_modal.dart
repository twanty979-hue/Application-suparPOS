import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';

class VariantModal {
  static String _formatCurrency(double amount) {
    return NumberFormat.currency(locale: 'th_TH', symbol: '฿', decimalDigits: 2).format(amount);
  }

  static Future<String?> show(
      BuildContext context, 
      Map<String, dynamic> product, 
      Map<String, dynamic> Function(Map<String, dynamic>, String) calculatePrice) {
    
    Widget buildVariantBtn(String variantKey, String label) {
      final pricing = calculatePrice(product, variantKey);
      final hasDiscount = pricing['discount'] > 0;

      return InkWell(
        onTap: () => Navigator.pop(context, variantKey),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.slate100)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.slate700)),
                  if (hasDiscount)
                    Container(
                      margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.rose500, borderRadius: BorderRadius.circular(6)),
                      child: Text("ลด ${_formatCurrency(pricing['discount'])}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasDiscount) Text(_formatCurrency(pricing['original']), style: const TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough, color: AppColors.slate400)),
                  Text(_formatCurrency(pricing['final']), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: hasDiscount ? AppColors.rose500 : AppColors.slate800)),
                ],
              )
            ],
          ),
        ),
      );
    }

    return showDialog<String>(
      context: context,
      barrierColor: AppColors.slate900.withOpacity(0.4),
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          child: Container(
            width: 400, padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("เลือกขนาด", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.slate900)),
                const SizedBox(height: 32),
                buildVariantBtn('normal', 'ธรรมดา'),
                if (product['price_special'] != null) ...[const SizedBox(height: 12), buildVariantBtn('special', 'พิเศษ ✨')],
                if (product['price_jumbo'] != null) ...[const SizedBox(height: 12), buildVariantBtn('jumbo', 'จัมโบ้ 🔥')],
                const SizedBox(height: 16),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก", style: TextStyle(color: AppColors.slate400, fontWeight: FontWeight.bold)))
              ],
            ),
          ),
        );
      },
    );
  }
}