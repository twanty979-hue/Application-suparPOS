// lib/widgets/modals/promptpay_modal.dart
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PromptPayModal {
  static Future<void> show({
    required BuildContext context,
    required double payableAmount,
    required String promptPayNum,
    required String Function(double) formatCurrency,
    Future<void> Function()? onPrintReceiptWithQr,
    required VoidCallback
    onConfirm, // ฟังก์ชันสำหรับรันตอนกดยืนยัน (เช่น บันทึกลง DB)
  }) async {
    // ⚠️ ดักเช็คถ้าหากร้านค้ายังไม่ได้กรอกเบอร์พร้อมเพย์ในระบบ
    if (promptPayNum.isEmpty || promptPayNum == 'ยังไม่ได้ตั้งค่า') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ ไม่สามารถสร้าง QR ได้เนื่องจากยังไม่ได้ตั้งค่าเบอร์พร้อมเพย์',
          ),
          backgroundColor: AppColors.rose500,
        ),
      );
      return;
    }

    // 🎯 เจนลิงก์โดยดึงเบอร์พร้อมเพย์รวมเข้ากับยอดเงิน
    String generatedQrUrl =
        "https://promptpay.io/$promptPayNum/$payableAmount.png";

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        var isPrinting = false;

        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Row(
              children: [
                Icon(Icons.qr_code_2, color: AppColors.blue600, size: 28),
                SizedBox(width: 8),
                Text('ชำระเงิน', style: TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatCurrency(payableAmount),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppColors.slate800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'พร้อมเพย์: $promptPayNum',
                  style: const TextStyle(
                    color: AppColors.slate500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // 🖼️ แสดงภาพคิวอาร์โค้ด
                Container(
                  width: 220,
                  height: 220,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.slate100),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    generatedQrUrl,
                    key: ValueKey(payableAmount),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.blue600,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              color: AppColors.slate300,
                              size: 40,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'โหลด QR Code ล้มเหลว',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.slate400,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ยอดเงินจะฝังอยู่ใน QR ลูกค้าสแกนแล้วจ่ายได้ทันที',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.slate400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isPrinting ? null : () => Navigator.pop(context),
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(
                    color: AppColors.slate500,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onPrintReceiptWithQr != null)
                OutlinedButton.icon(
                  onPressed: isPrinting
                      ? null
                      : () async {
                          setModalState(() => isPrinting = true);
                          await onPrintReceiptWithQr();
                          if (context.mounted) {
                            setModalState(() => isPrinting = false);
                          }
                        },
                  icon: isPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_rounded, size: 18),
                  label: Text(isPrinting ? 'กำลังพิมพ์...' : 'พิมพ์ใบพร้อม QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue600,
                    side: const BorderSide(color: AppColors.blue600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ElevatedButton(
                onPressed: isPrinting
                    ? null
                    : () {
                        Navigator.pop(context);
                        onConfirm(); // 💥 เรียกฟังก์ชันที่ส่งเข้ามา (คือ _processPayment)
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'ยืนยันได้รับเงินแล้ว',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
