// lib/widgets/pos/pos_top_bar.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PosTopBar extends StatelessWidget {
  final String activeTab;
  final int unpaidCount;
  final VoidCallback onMenuPressed;
  final Function(String) onTabChanged;
  final String quotaLabel;
  final bool isQuotaLocked;
  final VoidCallback onQrButtonPressed;
  final String planType;

  const PosTopBar({
    super.key,
    required this.activeTab,
    required this.unpaidCount,
    required this.onMenuPressed,
    required this.onTabChanged,
    required this.quotaLabel,
    required this.isQuotaLocked,
    required this.onQrButtonPressed,
    this.planType = 'free',
  });

  Widget _modeButton({
    required String tab,
    required String label,
    required IconData icon,
    int? badge,
  }) {
    final isSelected = activeTab == tab;
    final activeColor = const Color(0xFF292524); // สีดำออกน้ำตาล

    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(tab),
        child: AnimatedScale(
          scale: isSelected ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  size: 20,
                ),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        fontFamily: 'Kanit',
                      ),
                    ),
                  ),
                ],
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orange500,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _squareButton({
    required double size,
    required double radius,
    required Color color,
    required Color borderColor,
    required Color shadowColor,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12), // Fix radius for menu button
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
    );
  }

  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final isCompact = MediaQuery.of(context).size.width < 390;
    final barHeight = isDesktop ? 64.0 : 48.0;
    final radius = isDesktop ? 20.0 : 12.0;
    final gap = isDesktop ? 12.0 : 8.0;

    return SizedBox(
      height: barHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _squareButton(
            size: barHeight, // The square button width now matches the bar height
            radius: 12.0,
            color: const Color(0xFFDCD6CB), // ขาวไข่แบบเข้มขึ้น
            borderColor: Colors.transparent,
            shadowColor: Colors.transparent,
            icon: Icons.menu_rounded,
            iconColor: const Color(0xFF292524),
            onTap: onMenuPressed,
          ),
          SizedBox(width: gap),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFDCD6CB), // ขาวไข่แบบเข้มขึ้น
                borderRadius: BorderRadius.circular(16), // Match products_top_bar
              ),
              padding: EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _modeButton(
                    tab: 'tables',
                    label: isDesktop
                        ? 'โต๊ะ & รายการ'
                        : isCompact
                        ? ''
                        : 'โต๊ะ',
                    icon: Icons.receipt_long_rounded,
                    badge: unpaidCount,
                  ),
                  _modeButton(
                    tab: 'pos',
                    label: 'POS',
                    icon: Icons.grid_view_rounded,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: gap),
          AnimatedQuotaButton(
            planType: planType,
            quotaLabel: quotaLabel,
            isLocked: isQuotaLocked,
            onTap: onQrButtonPressed,
          ),
        ],
      ),
    );
  }
}

class AnimatedQuotaButton extends StatefulWidget {
  final String planType;
  final String quotaLabel;
  final bool isLocked;
  final VoidCallback onTap;

  const AnimatedQuotaButton({
    super.key,
    required this.planType,
    required this.quotaLabel,
    required this.isLocked,
    required this.onTap,
  });

  @override
  State<AnimatedQuotaButton> createState() => _AnimatedQuotaButtonState();
}

class _AnimatedQuotaButtonState extends State<AnimatedQuotaButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // 🌟 เปลี่ยนมาใช้ Animation หายใจเข้าออกแบบนุ่มนวล
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // จังหวะหายใจกำลังดี
    )..repeat(reverse: true); // ให้มันค่อยๆ สว่าง แล้วค่อยๆ จางสลับกัน

    // สร้างค่าแสงเงาตั้งแต่จางสุด (0.3) ไปถึงสว่างสุด (0.8)
    _pulseAnimation = Tween<double>(begin: 0.2, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final size = isDesktop ? 64.0 : 48.0; // Match new barHeight
    final radius = isDesktop ? 20.0 : 12.0;
    
    final normalizedPlan = widget.planType.toLowerCase().trim();

    // สกัดอิโมจิและอักขระพิเศษทิ้ง เหลือแค่ตัวอักษรภาษาไทย, อังกฤษ, ตัวเลข และ / เท่านั้น!
    final String cleanLabel = widget.quotaLabel
        .replaceAll(RegExp(r'[^\x00-\x7F\u0E00-\u0E7F]+'), '')
        .trim();

    // 1. ดักสัญญาล็อกลอจิกสำหรับค่าย FREE
    if (normalizedPlan == 'free' || normalizedPlan == 'unknown' || normalizedPlan.isEmpty) {
      return GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: size,
          decoration: BoxDecoration(
            color: widget.isLocked ? AppColors.rose50 : const Color(0xFFDCD6CB),
            borderRadius: BorderRadius.circular(12), // Match menu button
            border: Border.all(
              color: widget.isLocked
                  ? const Color(0xFFFCA5A5)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isLocked
                    ? Icons.lock_rounded
                    : Icons.qr_code_scanner_rounded,
                color: widget.isLocked ? AppColors.rose500 : const Color(0xFF292524),
                size: isDesktop ? 22 : 18,
              ),
              const SizedBox(height: 2),
              Text(
                cleanLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.isLocked
                      ? AppColors.rose500
                      : const Color(0xFF64748B),
                  fontSize: isDesktop ? 10 : 9,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Kanit',
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. แมปสีตามเกรดพรีเมียม (Basic, Pro, Ultimate)
    final Color iconColor;
    final Color insideBgColor;
    final IconData displayIcon;
    final bool isPulsing;

    if (normalizedPlan == 'ultimate') {
      // 🌟 ULTIMATE: ดำทอง หรูหรา (แสงทองวูบวาบ)
      iconColor = const Color(0xFFD4AF37); // สีทอง Premium
      insideBgColor = const Color(0xFF111827); // พื้นหลังดำเข้ม
      displayIcon = Icons.military_tech_rounded;
      isPulsing = true;
    } else if (normalizedPlan == 'pro') {
      // 🌟 PRO: ขาวสว่าง (พื้นหลังม่วง)
      iconColor = Colors.white; // ขาว
      insideBgColor = const Color(0xFF9333EA); // พื้นหลังม่วง
      displayIcon = Icons.star_rounded;
      isPulsing = true;
    } else {
      // 🌟 BASIC: ขาวสีกรมท่า คลีนๆ (ไม่วูบวาบ)
      iconColor = const Color(0xFF292524);
      insideBgColor = const Color(0xFFDCD6CB);
      displayIcon = Icons.storefront_rounded;
      isPulsing = false;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: insideBgColor,
              borderRadius: BorderRadius.circular(radius),
              // 🌟 จุดเปลี่ยน: ใช้ BoxShadow แทนการสร้างกล่องสี่เหลี่ยมด้านล่าง
              // ถ้าระดับ Pro/Ultimate ให้แสงขอบฟุ้งกระจายตามจังหวะหายใจ
              boxShadow: [
                BoxShadow(
                  color: isPulsing 
                    ? iconColor.withOpacity(_pulseAnimation.value) // แสงวูบวาบ
                    : iconColor.withOpacity(0.15), // Basic แสงนิ่งๆ อ่อนๆ
                  blurRadius: isPulsing ? 18 : 12,
                  spreadRadius: isPulsing ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
                // ใส่เงาพื้นฐานรองไว้อีกชั้นให้กล่องดูลอยมีมิติ
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              // ใส่เส้นขอบบางๆ สีเดียวกับไอคอนให้ดูคมขึ้น
              border: Border.all(
                color: isPulsing ? iconColor.withOpacity(0.3) : AppColors.slate200,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  displayIcon,
                  color: iconColor,
                  size: isDesktop ? 24 : 20, // ปรับไอคอนให้ใหญ่ขึ้นนิดนึง
                ),
                const SizedBox(height: 2),
                Text(
                  cleanLabel, 
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: isDesktop ? 9.5 : 8.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Kanit',
                    letterSpacing: 0.5, // เพิ่มช่องไฟให้ดูหรูขึ้น
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
