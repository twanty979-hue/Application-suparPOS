import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PosTopBar extends StatelessWidget {
  final String activeTab;
  final int unpaidCount;
  final bool autoKitchen;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onKitchenToggled;

  const PosTopBar({
    super.key,
    required this.activeTab,
    required this.unpaidCount,
    required this.autoKitchen,
    required this.onTabChanged,
    required this.onKitchenToggled,
  });

  static const double _commonHeight = 44.0;
  static const double _commonRadius = 12.0;

  Widget _buildTabButton(String tab, String label, IconData icon, {int? badge}) {
    bool isSelected = activeTab == tab;
    Color activeColor = tab == 'tables' ? AppColors.slate800 : AppColors.orange500;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // 🔥 จุดสำคัญที่ 1: เอา margin ออก สีจะได้ยืดสุดขอบ
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(_commonRadius - 4), // โค้งรับกับขอบนอกพอดี
            boxShadow: isSelected 
                ? [BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))] 
                : [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: isSelected ? Colors.white : AppColors.slate500, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.slate600, 
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold, 
                      fontSize: 13,
                    ),
                  ),
                  if (badge != null && badge > 0) const SizedBox(width: 22),
                ],
              ),
              if (badge != null && badge > 0)
                Positioned(
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.25) : AppColors.orange500,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$badge",
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, {bool isActive = false, Color? activeColor, Color? activeBg, Color? iconColor}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_commonRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _commonHeight,
        height: _commonHeight,
        decoration: BoxDecoration(
          color: isActive ? (activeBg ?? AppColors.emerald50) : Colors.white,
          borderRadius: BorderRadius.circular(_commonRadius),
          border: Border.all(
            color: isActive ? (activeColor?.withOpacity(0.3) ?? AppColors.slate200) : AppColors.slate200, 
            width: 1.2
          ),
        ),
        child: Icon(
          icon, 
          color: isActive ? (activeColor ?? AppColors.emerald500) : (iconColor ?? AppColors.slate600), 
          size: 18
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _commonHeight, 
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, 
        children: [
          // 🔥 รางเมนู (Track)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3), // 🔥 จุดสำคัญที่ 2: ให้รางเป็นตัวบีบระยะขอบนอกแทน
              decoration: BoxDecoration(
                color: AppColors.slate100.withOpacity(0.6), // สีพื้นหลังรางเป็นสีเทาอ่อนๆ
                borderRadius: BorderRadius.circular(_commonRadius),
                border: Border.all(color: AppColors.slate200, width: 1.2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch, // 🔥 จุดสำคัญที่ 3: สั่งให้ปุ่มสีๆ ยืดความสูงเต็มราง
                children: [
                  _buildTabButton('tables', 'โต๊ะ', Icons.receipt_long_rounded, badge: unpaidCount),
                  _buildTabButton('pos', 'POS', Icons.grid_view_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildIconButton(
            Icons.bolt_rounded, 
            onKitchenToggled, 
            isActive: autoKitchen, 
            activeColor: AppColors.emerald500, 
            activeBg: AppColors.emerald50
          ),
          const SizedBox(width: 8),
          _buildIconButton(
            Icons.qr_code_scanner_rounded, 
            () {}, 
            iconColor: AppColors.slate600
          ),
        ],
      ),
    );
  }
}