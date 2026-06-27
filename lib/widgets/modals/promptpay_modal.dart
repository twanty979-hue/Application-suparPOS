// lib/widgets/modals/promptpay_modal.dart
import 'package:flutter/material.dart';
import 'dart:ui';

import '../../theme/app_colors.dart';

class PromptPayModal {
  static Future<void> show({
    required BuildContext context,
    required double payableAmount,
    required String promptPayNum,
    required String Function(double) formatCurrency,
    Future<void> Function()? onPrintReceiptWithQr,
    required VoidCallback onConfirm,
  }) async {
    if (promptPayNum.isEmpty || promptPayNum == 'ยังไม่ได้ตั้งค่า') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ยังไม่ได้ตั้งค่าเบอร์พร้อมเพย์'),
          backgroundColor: AppColors.rose500,
        ),
      );
      return;
    }

    final generatedQrUrl =
        'https://promptpay.io/$promptPayNum/$payableAmount.png';

    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) {
        var isPrinting = false;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: StatefulBuilder(
            builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 390),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 12, 14, 12),
                      decoration: const BoxDecoration(
                        color: AppColors.slate900,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.qr_code_2_rounded,
                              color: Colors.white,
                              size: 27,
                            ),
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PromptPay',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: isPrinting
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatCurrency(payableAmount),
                            style: const TextStyle(
                              color: AppColors.slate900,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'PromptPay: $promptPayNum',
                              style: const TextStyle(
                                color: AppColors.slate600,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: 180,
                            height: 180,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1D4ED8,
                                  ).withValues(alpha: 0.1),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.network(
                              generatedQrUrl,
                              key: ValueKey(payableAmount),
                              fit: BoxFit.contain,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: AppColors.blue600,
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Text(
                                    'โหลด QR ไม่สำเร็จ',
                                    style: TextStyle(
                                      color: AppColors.slate400,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              if (onPrintReceiptWithQr != null) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
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
                                    label: Text(
                                      isPrinting ? 'พิมพ์...' : 'พิมพ์ QR',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: isPrinting
                                      ? null
                                      : () {
                                          Navigator.pop(context);
                                          onConfirm();
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.emerald500,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'ยืนยันรับเงินแล้ว',
                                    style: TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        );
      },
    );
  }
}
