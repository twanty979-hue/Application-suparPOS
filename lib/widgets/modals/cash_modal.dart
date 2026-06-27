import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import '../../theme/app_colors.dart';

class CashModal {
  static String _formatCurrency(double amount) {
    return NumberFormat.currency(locale: 'th_TH', symbol: '฿', decimalDigits: 2).format(amount);
  }

  static Future<dynamic> show(BuildContext context, double payableAmount) {
    double receivedAmount = 0;

    Widget buildNumpadBtn(String label, VoidCallback onTap, {Color? color, Color? textColor, IconData? icon}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color ?? Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color == null ? AppColors.slate100 : Colors.transparent),
          ),
          alignment: Alignment.center,
          child: icon != null 
            ? Icon(icon, color: AppColors.slate500, size: 24)
            : Text(label, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor ?? AppColors.slate700)),
        ),
      );
    }

    return showDialog<dynamic>(
      context: context,
      barrierColor: AppColors.slate900.withOpacity(0.6),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            double change = receivedAmount - payableAmount;
            bool canPay = receivedAmount >= payableAmount;
            bool isChangeLimitExceeded = change > 999.75;

            void onNumPadPress(String val) {
              setModalState(() {
                if (val == 'C') {
                  receivedAmount = 0;
                } else if (val == 'DEL') {
                  String currentStr = receivedAmount.toInt().toString();
                  if (currentStr.length > 1) {
                    receivedAmount = double.parse(currentStr.substring(0, currentStr.length - 1));
                  } else {
                    receivedAmount = 0;
                  }
                } else {
                  if (receivedAmount == 0 && val == '0') return;
                  String currentStr = receivedAmount == 0 ? '' : receivedAmount.toInt().toString();
                  receivedAmount = double.parse(currentStr + val);
                }
              });
            }

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 470,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: const BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(bottom: BorderSide(color: AppColors.slate100)),
                    ),
                    width: double.infinity,
                    child: const Text("รับเงินสด", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.slate800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.slate200)),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("ยอดรวม", style: TextStyle(color: AppColors.slate500, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(_formatCurrency(payableAmount), style: const TextStyle(color: AppColors.slate900, fontSize: 18)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: canPay ? AppColors.emerald500 : AppColors.orange500, width: 2))),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("รับเงิน", style: TextStyle(color: AppColors.slate400, fontWeight: FontWeight.bold, fontSize: 12)),
                                    Text(receivedAmount > 0 ? receivedAmount.toInt().toString() : '0', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("เงินทอน", style: TextStyle(color: AppColors.slate500, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(canPay ? _formatCurrency(change) : '-', style: TextStyle(color: canPay ? (isChangeLimitExceeded ? AppColors.rose500 : AppColors.emerald500) : AppColors.slate300, fontSize: 18, fontWeight: FontWeight.w900)),
                                ],
                              ),
                              if (isChangeLimitExceeded)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text("เงินทอนเกินกำหนด (สูงสุด 999.75 ฿)", style: TextStyle(color: AppColors.rose500, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [20, 50, 100, 500, 1000].map((v) => 
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: ElevatedButton(
                                  onPressed: () => setModalState(() { receivedAmount += v.toDouble(); }),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.slate50,
                                    foregroundColor: AppColors.slate600,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.slate200)),
                                  ),
                                  child: Text("+$v", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            )
                          ).toList(),
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          shrinkWrap: true, crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.4, physics: const NeverScrollableScrollPhysics(),
                          children: [
                            ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((v) => buildNumpadBtn(v, () => onNumPadPress(v))),
                            buildNumpadBtn('C', () => onNumPadPress('C'), color: AppColors.rose50, textColor: AppColors.rose500),
                            buildNumpadBtn('0', () => onNumPadPress('0')),
                            buildNumpadBtn('DEL', () => onNumPadPress('DEL'), icon: Icons.backspace_outlined),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context, payableAmount),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.blue50, foregroundColor: AppColors.blue600, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.blue50)),
                                ),
                                    child: const Text("จ่ายพอดี", style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: (canPay && !isChangeLimitExceeded) ? () => Navigator.pop(context, receivedAmount) : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.emerald500, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text("ยืนยัน", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            );
          }
        );
      },
    );
  }
}
