import 'dart:io';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class CartPanel extends StatelessWidget {
  final String activeTab;
  final Map<String, dynamic>? selectedOrder;
  final List<Map<String, dynamic>> cart;
  final String paymentMethod;
  final double rawTotal;
  final double payableAmount;
  final bool showProductImages;

  final Function(int) onRemoveFromCart;
  final Future<void> Function()? onCancelOrder;
  final Function(String) onPaymentMethodChanged;
  final VoidCallback onMainPaymentClick;
  final String Function(double) formatCurrency;

  const CartPanel({
    super.key,
    required this.activeTab,
    this.selectedOrder,
    required this.cart,
    required this.paymentMethod,
    required this.rawTotal,
    required this.payableAmount,
    this.showProductImages = false,
    required this.onRemoveFromCart,
    this.onCancelOrder,
    required this.onPaymentMethodChanged,
    required this.onMainPaymentClick,
    required this.formatCurrency,
  });

  Widget _buildPaymentMethodBtn(String method, String label, IconData icon) {
    bool isSelected = paymentMethod == method;
    return InkWell(
      onTap: () => onPaymentMethodChanged(method),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (method == 'promptpay'
                      ? AppColors.blue50
                      : AppColors.slate200)
                : Colors.transparent,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? (method == 'promptpay'
                        ? AppColors.blue600
                        : AppColors.slate900)
                  : AppColors.slate400,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected
                    ? (method == 'promptpay'
                          ? AppColors.blue600
                          : AppColors.slate900)
                    : AppColors.slate400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _resolveImageUrl(Map item) {
    final raw = item['image_url'] ?? item['image_name'] ?? item['image'];
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'https://xvhibjejvbriotfpunvv.supabase.co/storage/v1/object/public/images/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Widget _buildItemLeading({
    required Map item,
    required double qty,
    required bool isCancelled,
    required bool isDesktop,
  }) {
    final size = isDesktop ? 38.0 : 34.0;
    final localPath = item['local_image_path']?.toString();
    final localFile = localPath == null || localPath.isEmpty
        ? null
        : File(localPath);
    final imageUrl = _resolveImageUrl(item);

    if (showProductImages) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: size,
          height: size,
          color: AppColors.slate100,
          child: localFile != null && localFile.existsSync()
              ? Image.file(localFile, fit: BoxFit.cover)
              : imageUrl != null
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_outlined,
                    color: AppColors.slate300,
                    size: 18,
                  ),
                )
              : const Icon(
                  Icons.image_outlined,
                  color: AppColors.slate300,
                  size: 18,
                ),
        ),
      );
    }

    return Container(
      width: isDesktop ? 34 : 32,
      height: isDesktop ? 34 : 32,
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.slate100),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.receipt_long_outlined,
        color: isCancelled ? AppColors.slate300 : AppColors.slate400,
        size: 17,
      ),
    );
  }

  Widget _buildQtyPill({
    required double qty,
    required bool isCancelled,
    required bool isDesktop,
  }) {
    return Container(
      height: isDesktop ? 30 : 28,
      constraints: BoxConstraints(minWidth: isDesktop ? 36 : 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isCancelled ? AppColors.slate100 : AppColors.slate50,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        "x${qty.toInt()}",
        style: TextStyle(
          color: isCancelled ? AppColors.slate400 : AppColors.slate700,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          decoration: isCancelled
              ? TextDecoration.lineThrough
              : TextDecoration.none,
        ),
      ),
    );
  }

  Widget _buildRemoveButton(int index) {
    return InkWell(
      onTap: () => onRemoveFromCart(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: AppColors.slate50,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.delete_outline,
          color: AppColors.slate400,
          size: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    bool isTableActive = activeTab == 'tables' && selectedOrder != null;
    List itemsToRender = isTableActive
        ? (selectedOrder!['order_items'] as List)
        : cart;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 14),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 14 : 12,
              vertical: isDesktop ? 10 : 9,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.slate50)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.slate700, AppColors.slate900],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.slate900.withOpacity(0.3),
                            blurRadius: 5,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      "สรุปยอดชำระ",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.slate800,
                      ),
                    ),
                  ],
                ),
                if (isTableActive && onCancelOrder != null)
                  Material(
                    color: AppColors.rose50,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onCancelOrder,
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.rose500,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                if (isTableActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orange100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      "โต๊ะ ${selectedOrder!['table_label']}",
                      style: const TextStyle(
                        color: AppColors.orange600,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              color: AppColors.bgCard,
              child: itemsToRender.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: AppColors.slate50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: AppColors.slate200,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "ยังไม่มีรายการ",
                            style: TextStyle(
                              color: AppColors.slate400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(isDesktop ? 12 : 8),
                      itemCount: itemsToRender.length,
                      itemBuilder: (context, index) {
                        final item = itemsToRender[index];
                        final isTableItem = activeTab == 'tables';
                        final isCancelled =
                            isTableItem &&
                            item['status']?.toString().toLowerCase() ==
                                'cancelled';
                        final double itemPrice =
                            double.tryParse(item['price']?.toString() ?? '0') ??
                            0.0;
                        final double qty =
                            double.tryParse(item['qty']?.toString() ?? '1') ??
                            1.0;

                        String itemName =
                            item['name'] ?? item['product_name'] ?? '';
                        String variant = item['variant'] == 'normal'
                            ? ''
                            : (item['variant'] ?? '');

                        return Container(
                          margin: EdgeInsets.only(bottom: isDesktop ? 8 : 6),
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 11 : 9,
                            vertical: isDesktop ? 8 : 7,
                          ),
                          decoration: BoxDecoration(
                            color: isCancelled
                                ? AppColors.slate50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCancelled
                                  ? AppColors.rose500.withOpacity(0.18)
                                  : AppColors.slate100,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.025),
                                blurRadius: 5,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildItemLeading(
                                item: item,
                                qty: qty,
                                isCancelled: isCancelled,
                                isDesktop: isDesktop,
                              ),
                              SizedBox(width: isDesktop ? 11 : 8),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isCancelled
                                              ? AppColors.slate400
                                              : AppColors.slate700,
                                          decoration: isCancelled
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                      if (isCancelled)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.rose50,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: AppColors.rose500
                                                  .withOpacity(0.18),
                                            ),
                                          ),
                                          child: const Text(
                                            'ยกเลิกแล้ว',
                                            style: TextStyle(
                                              color: AppColors.rose500,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      if (item['barcode'] != null)
                                        Text(
                                          item['barcode'],
                                          style: const TextStyle(
                                            color: AppColors.slate400,
                                            fontSize: 9,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      if (variant.isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.orange50,
                                            border: Border.all(
                                              color: AppColors.orange100,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            variant.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.orange500,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Baseline(
                                    baseline: 18,
                                    baselineType: TextBaseline.alphabetic,
                                    child: Text(
                                      formatCurrency(itemPrice * qty),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: isCancelled
                                            ? AppColors.slate400
                                            : AppColors.slate800,
                                        decoration: isCancelled
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildQtyPill(
                                    qty: qty,
                                    isCancelled: isCancelled,
                                    isDesktop: isDesktop,
                                  ),
                                  if (!isCancelled) ...[
                                    const SizedBox(width: 8),
                                    _buildRemoveButton(index),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),

          if (itemsToRender.isNotEmpty)
            Container(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 16 : 12,
                isDesktop ? 14 : 12,
                isDesktop ? 16 : 12,
                isDesktop ? 16 : 14,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildPaymentMethodBtn(
                            'cash',
                            'เงินสด',
                            Icons.account_balance_wallet,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildPaymentMethodBtn(
                            'promptpay',
                            'พร้อมเพย์',
                            Icons.qr_code_2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isDesktop ? 12 : 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "ยอดสุทธิ ${paymentMethod == 'cash' ? '(ปัดเศษ)' : ''}",
                        style: const TextStyle(
                          color: AppColors.slate400,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (rawTotal != payableAmount)
                            Text(
                              formatCurrency(rawTotal),
                              style: const TextStyle(
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.slate400,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          Text(
                            formatCurrency(payableAmount),
                            style: TextStyle(
                              fontSize: isDesktop ? 28 : 26,
                              fontWeight: FontWeight.w900,
                              color: AppColors.slate800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isDesktop ? 12 : 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: isDesktop ? 48 : 46,
                          child: ElevatedButton(
                            onPressed: onMainPaymentClick,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: paymentMethod == 'promptpay'
                                  ? AppColors.blue600
                                  : AppColors.slate800,
                              foregroundColor: Colors.white,
                              elevation: 5,
                              shadowColor: paymentMethod == 'promptpay'
                                  ? AppColors.blue600.withOpacity(0.28)
                                  : AppColors.slate800.withOpacity(0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  isDesktop ? 14 : 12,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  paymentMethod == 'promptpay'
                                      ? Icons.qr_code_2
                                      : Icons.check_circle,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  paymentMethod == 'promptpay'
                                      ? "แสดง QR"
                                      : "รับชำระเงิน",
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }
}
