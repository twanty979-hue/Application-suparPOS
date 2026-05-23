import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class CategoryList extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52, // 🔥 ลดความสูงจาก 64 เหลือ 52
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // 🔥 ลด padding แนวนอนและตั้ง
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat['id'];
          return GestureDetector(
            onTap: () => onCategorySelected(cat['id']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16), // 🔥 ลด padding ซ้ายขวาของปุ่ม
              decoration: BoxDecoration(
                color: isSelected ? AppColors.slate800 : Colors.white,
                borderRadius: BorderRadius.circular(10), // ปรับความโค้ง
                border: Border.all(color: isSelected ? AppColors.slate800 : AppColors.slate100),
                boxShadow: isSelected ? [BoxShadow(color: AppColors.slate800.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],
              ),
              alignment: Alignment.center,
              child: Text(cat['name'], style: TextStyle(color: isSelected ? Colors.white : AppColors.slate500, fontWeight: FontWeight.bold, fontSize: 13)), // 🔥 ย่อฟอนต์จาก 14 เป็น 13
            ),
          );
        },
      ),
    );
  }
}