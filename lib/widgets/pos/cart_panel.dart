import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class CartPanel extends StatelessWidget {
  final String activeTab;
  final Map<String, dynamic>? selectedOrder;
  final List<Map<String, dynamic>> cart;
  final String paymentMethod;
  final double rawTotal;
  final double payableAmount;

  final Function(int) onRemoveFromCart;
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
    required this.onRemoveFromCart,
    required this.onPaymentMethodChanged,
    required this.onMainPaymentClick,
    required this.formatCurrency,
  });

  Widget _buildPaymentMethodBtn(String method, String label, IconData icon) {
    bool isSelected = paymentMethod == method;
    return InkWell(
      onTap: () => onPaymentMethodChanged(method),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
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
                    blurRadius: 8,
                    offset: const Offset(0, 2),
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
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
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
        borderRadius: BorderRadius.circular(isDesktop ? 32 : 24),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 40,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 24 : 16),
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
                      width: 40,
                      height: 40,
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
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "สรุปยอดชำระ",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.slate800,
                      ),
                    ),
                  ],
                ),
                if (isTableActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orange100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "โต๊ะ ${selectedOrder!['table_label']}",
                      style: const TextStyle(
                        color: AppColors.orange600,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: AppColors.slate50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: AppColors.slate200,
                              size: 32,
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
                      padding: EdgeInsets.all(isDesktop ? 20 : 12),
                      itemCount: itemsToRender.length,
                      itemBuilder: (context, index) {
                        final item = itemsToRender[index];
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
                          margin: EdgeInsets.only(bottom: isDesktop ? 12 : 10),
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 16 : 12,
                            vertical: isDesktop ? 12 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.slate100),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.025),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: isDesktop ? 40 : 36,
                                height: isDesktop ? 40 : 36,
                                decoration: BoxDecoration(
                                  color: AppColors.slate50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.slate100),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "x${qty.toInt()}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.slate700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              SizedBox(width: isDesktop ? 16 : 10),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.slate700,
                                        ),
                                      ),
                                      if (item['barcode'] != null)
                                        Text(
                                          item['barcode'],
                                          style: const TextStyle(
                                            color: AppColors.slate400,
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      if (variant.isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
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
                                              fontSize: 9,
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatCurrency(itemPrice * qty),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: AppColors.slate800,
                                    ),
                                  ),
                                  if (activeTab == 'pos') ...[
                                    const SizedBox(height: 4),
                                    InkWell(
                                      onTap: () => onRemoveFromCart(index),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: AppColors.slate50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline,
                                          color: AppColors.slate400,
                                          size: 16,
                                        ),
                                      ),
                                    ),
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
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 40,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(isDesktop ? 6 : 4),
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(20),
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
                        const SizedBox(width: 8),
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
                  SizedBox(height: isDesktop ? 20 : 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "ยอดสุทธิ ${paymentMethod == 'cash' ? '(ปัดเศษ)' : ''}",
                        style: const TextStyle(
                          color: AppColors.slate400,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (rawTotal != payableAmount)
                            Text(
                              formatCurrency(rawTotal),
                              style: const TextStyle(
                                fontSize: 14,
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.slate400,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          Text(
                            formatCurrency(payableAmount),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: AppColors.slate800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isDesktop ? 20 : 14),
                  SizedBox(
                    width: double.infinity,
                    height: isDesktop ? 64 : 56,
                    child: ElevatedButton(
                      onPressed: onMainPaymentClick,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: paymentMethod == 'promptpay'
                            ? AppColors.blue600
                            : AppColors.slate800,
                        foregroundColor: Colors.white,
                        elevation: 10,
                        shadowColor: paymentMethod == 'promptpay'
                            ? AppColors.blue600.withOpacity(0.5)
                            : AppColors.slate800.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            isDesktop ? 24 : 16,
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
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            paymentMethod == 'promptpay'
                                ? "แสดง QR"
                                : "รับชำระเงิน",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
