// lib/widgets/modals/completed_receipt_modal.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CompletedReceiptModal {
  static void show(
    BuildContext context,
    Map<String, dynamic> receiptData,
    VoidCallback onClose, {
    Future<void> Function()? onPrint,
  }) {
    final currencyFormat = NumberFormat.currency(
      locale: 'th_TH',
      symbol: '฿',
      decimalDigits: 2,
    );

    // ดึงข้อมูลจาก Map
    final String brandName = receiptData['brand_name'] ?? 'ร้านของคุณ';
    final String tableLabel = receiptData['table_label'] ?? 'Walk-in';
    final String orderId = receiptData['order_id'] ?? 'unknown';
    final List<dynamic> items = receiptData['items'] ?? [];

    // คำนวณ Subtotal และ ส่วนลดรวม จากรายการอาหาร
    double calcSubtotal = 0;
    double calcTotalDiscount = 0;
    for (var item in items) {
      double original =
          double.tryParse(item['original_price']?.toString() ?? '0') ?? 0;
      double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      int qty = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

      if (original <= 0) original = price; // กันเหนียวกรณีไม่มี original_price
      calcSubtotal += (original * qty);
      calcTotalDiscount += ((original - price) * qty);
    }

    final double totalAmount = receiptData['total_amount'] ?? 0.0;
    final String paymentMethod = receiptData['payment_method'] ?? 'CASH';
    final double receivedAmount = receiptData['received_amount'] ?? totalAmount;
    final double changeAmount = receiptData['change_amount'] ?? 0.0;
    final String cashierName = receiptData['cashier_name'] ?? 'System';

    // จัดรูปแบบวันที่
    final now = DateTime.now();
    final thaiYear = now.year + 543;
    final thaiMonths = [
      "ม.ค.",
      "ก.พ.",
      "มี.ค.",
      "เม.ย.",
      "พ.ค.",
      "มิ.ย.",
      "ก.ค.",
      "ส.ค.",
      "ก.ย.",
      "ต.ค.",
      "พ.ย.",
      "ธ.ค.",
    ];
    final formattedDate =
        "${now.day} ${thaiMonths[now.month - 1]} $thaiYear ${DateFormat('HH:mm').format(now)}";
    final shortOrderId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Header (แถบด้านบน) ---
                Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 8,
                    top: 12,
                    bottom: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "รายละเอียดใบเสร็จ",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.print_outlined,
                              color: Colors.black54,
                            ),
                            onPressed: onPrint == null ? null : () => onPrint(),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.black54,
                            ),
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onClose();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.black12),

                // --- เนื้อหาใบเสร็จ (เลื่อนขึ้นลงได้ถ้ารายการเยอะ) ---
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          brandName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Table: $tableLabel',
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'Courier',
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Courier',
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          'Order ID: #$shortOrderId',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Courier',
                            color: Colors.black54,
                          ),
                        ),

                        _buildDashedLine(),

                        if (items.isEmpty)
                          const Text(
                            "ไม่มีรายการ",
                            style: TextStyle(fontFamily: 'Courier'),
                          ),

                        // --- ลิสต์รายการอาหาร ---
                        ...items.map((item) {
                          final String itemName =
                              item['product_name'] ?? item['name'] ?? 'Unknown';
                          final String variant = item['variant'] ?? 'normal';
                          final String variantText = variant == 'special'
                              ? ' (พิเศษ)'
                              : variant == 'jumbo'
                              ? ' (จัมโบ้)'
                              : '';
                          final int qty =
                              int.tryParse(
                                item['quantity']?.toString() ?? '1',
                              ) ??
                              1;
                          final double price =
                              double.tryParse(
                                item['price']?.toString() ?? '0',
                              ) ??
                              0;
                          final double originalPrice =
                              double.tryParse(
                                item['original_price']?.toString() ??
                                    price.toString(),
                              ) ??
                              price;
                          final double discount = originalPrice - price;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${qty}x ',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontFamily: 'Courier',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '$itemName$variantText',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontFamily: 'Courier',
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (discount > 0)
                                          Text(
                                            currencyFormat.format(
                                              originalPrice * qty,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'Courier',
                                              color: Colors.grey,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                          ),
                                        Text(
                                          currencyFormat.format(price * qty),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontFamily: 'Courier',
                                            fontWeight: FontWeight.bold,
                                            color: discount > 0
                                                ? Colors.red
                                                : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (discount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 24,
                                      top: 4,
                                    ),
                                    child: Text(
                                      '(ส่วนลด: -${currencyFormat.format(discount * qty)})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'Courier',
                                        color: Colors.red,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),

                        _buildDashedLine(),

                        // --- สรุปยอด ---
                        _buildRow(
                          'ยอดรวม (Subtotal)',
                          currencyFormat.format(calcSubtotal),
                        ),
                        if (calcTotalDiscount > 0)
                          _buildRow(
                            'ส่วนลดรวม (Discount)',
                            '-${currencyFormat.format(calcTotalDiscount)}',
                            color: Colors.red,
                          ),
                        const SizedBox(height: 8),
                        _buildRow(
                          'ยอดรวมสุทธิ',
                          currencyFormat.format(totalAmount),
                          isBold: true,
                          size: 20,
                        ),

                        _buildDashedLine(),

                        // --- การชำระเงิน ---
                        _buildRow('ชำระโดย / $paymentMethod', ''),
                        _buildRow(
                          'รับเงิน (Received)',
                          currencyFormat.format(receivedAmount),
                        ),
                        _buildRow(
                          'เงินทอน (Change)',
                          currencyFormat.format(changeAmount),
                        ),

                        _buildDashedLine(),

                        // --- Footer ---
                        const SizedBox(height: 8),
                        Text(
                          'CASHIER: ${cashierName.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Courier',
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ขอบคุณที่ใช้บริการ / THANK YOU',
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- ปุ่มพิมพ์ด้านล่าง ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.print, color: Colors.white),
                      label: const Text(
                        "พิมพ์ใบเสร็จ",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: onPrint == null ? null : () => onPrint(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildDashedLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        List.filled(40, '-').join(),
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          color: Colors.black45,
          letterSpacing: 2,
          fontFamily: 'Courier',
        ),
      ),
    );
  }

  static Widget _buildRow(
    String title,
    String value, {
    bool isBold = false,
    double size = 14,
    Color color = Colors.black87,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: size,
              fontFamily: 'Courier',
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontFamily: 'Courier',
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
