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
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      height: isDesktop ? 62 : 52,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : 12,
          vertical: isDesktop ? 10 : 8,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat['id'];
          return GestureDetector(
            onTap: () => onCategorySelected(cat['id']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 16),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.slate800 : Colors.white,
                borderRadius: BorderRadius.circular(isDesktop ? 12 : 10),
                border: Border.all(
                  color: isSelected ? AppColors.slate800 : AppColors.slate100,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.slate800.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              alignment: Alignment.center,
              child: Text(
                cat['name'],
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.slate500,
                  fontWeight: FontWeight.w800,
                  fontSize: isDesktop ? 14 : 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
