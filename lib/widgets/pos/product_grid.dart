import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'category_list.dart';

class ProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final List<Map<String, dynamic>> displayProducts;
  final TextEditingController barcodeController;
  final ValueChanged<Map<String, dynamic>> onProductClick;
  final Map<String, dynamic> Function(Map<String, dynamic>, String) calculatePrice;
  final String Function(double) formatCurrency;

  const ProductGrid({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.displayProducts,
    required this.barcodeController,
    required this.onProductClick,
    required this.calculatePrice,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 ใช้ LayoutBuilder เพื่อเช็กความกว้างพื้นที่จริง (iPad / Web / Mobile)
    return LayoutBuilder(
      builder: (context, constraints) {
        // --- 1. คำนวณจำนวนคอลัมน์อัตโนมัติ ---
        // เราตั้งเป้าว่า ปุ่มหนึ่งปุ่มควรจะกว้างประมาณ 130 - 150 px กำลังสวย
        // เอาความกว้างจอหารด้วยขนาดเป้าหมาย จะได้จำนวนปุ่มที่ควรมีต่อแถว
        int crossAxisCount = (constraints.maxWidth / 140).floor(); 
        
        // กันเหนียว: บนมือถือจอแคบสุดๆ ให้มีอย่างน้อย 4 (ตามที่นายชอบ)
        if (crossAxisCount < 4) crossAxisCount = 4;
        
        // ถ้าจอใหญ่มาก (เช่น จอคอมกว้างๆ) ก็ให้มีได้ไม่เกิน 8-10 อันกันมันเล็กไป
        if (crossAxisCount > 8) crossAxisCount = 8;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- แถบยิงบาร์โค้ด (จิ๋วลง) ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppColors.slate100.withOpacity(0.8))),
              ),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.slate100, width: 1.5),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    const Icon(Icons.qr_code_2, color: AppColors.slate400, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: barcodeController,
                        decoration: const InputDecoration(
                          hintText: "บาร์โค้ด หรือสแกน",
                          hintStyle: TextStyle(color: AppColors.slate300, fontSize: 12, fontWeight: FontWeight.bold),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.slate800),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 36, height: 32,
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.slate800,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Icon(Icons.camera_alt, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- แถบหมวดหมู่ ---
            CategoryList(
              categories: categories,
              selectedCategory: selectedCategory,
              onCategorySelected: onCategorySelected,
            ),

            // --- กริตสินค้า (Responsive) ---
            Expanded(
              child: Container(
                color: AppColors.bgLight, 
                child: displayProducts.isEmpty
                    ? const Center(child: Text("ไม่พบสินค้า", style: TextStyle(color: AppColors.slate400, fontSize: 12)))
                    : GridView.builder(
                        padding: const EdgeInsets.all(6),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount, // 🔥 ใช้ค่าที่เราคำนวณมาแบบ Dynamic
                          childAspectRatio: 1.45, // 🔥 ล็อกสัดส่วนความสูงให้คงที่ ไม่มียืดบวม
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: displayProducts.length,
                        itemBuilder: (context, index) {
                          final product = displayProducts[index];
                          final pricing = calculatePrice(product, 'normal');
                          final hasDiscount = pricing['discount'] > 0;

                          return InkWell(
                            onTap: () => onProductClick(product),
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: hasDiscount ? AppColors.orange100 : AppColors.slate200),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 2, offset: const Offset(0, 1))],
                              ),
                              child: Stack(
                                children: [
                                  if (hasDiscount)
                                    Positioned(
                                      top: 0, right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.rose500,
                                          borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomLeft: Radius.circular(4)),
                                        ),
                                        child: const Text("SALE", style: TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.w900)),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          product['name'] ?? '', 
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: AppColors.slate700, height: 1.0), 
                                          maxLines: 2, 
                                          overflow: TextOverflow.ellipsis
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (hasDiscount)
                                              Text(
                                                formatCurrency(pricing['original']), 
                                                style: const TextStyle(fontSize: 8, decoration: TextDecoration.lineThrough, color: AppColors.slate400, height: 1.0)
                                              ),
                                            Text(
                                              formatCurrency(pricing['final']), 
                                              style: TextStyle(
                                                fontSize: 12, 
                                                fontWeight: FontWeight.w900, 
                                                color: hasDiscount ? AppColors.rose500 : AppColors.slate800, 
                                                letterSpacing: -0.5,
                                                height: 1.0
                                              )
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
              ),
            ),
          ],
        );
      },
    );
  }
}