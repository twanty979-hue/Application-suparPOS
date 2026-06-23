import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';

// Import หน้าทั้ง 5 ที่นายสร้างไว้แล้ว
import 'receive_stock_screen.dart';
import 'inventory_overview_screen.dart';
import 'stock_balance_screen.dart';
import 'stock_import_history_screen.dart';
import 'stock_import_history_screen.dart';
import 'stock_adjustment_screen.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      drawer: const AppSidebar(activeMenu: 'inventory'),
      body: Builder(
        builder: (scaffoldContext) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _InventoryHeader(
                  title: 'จัดการคลังสินค้า',
                  subtitle: 'ระบบจัดการสต็อกแบบ Real-time แม่นยำทุก\nรายการ',
                  onBack: () => _handleBackOrMenu(context, scaffoldContext),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Transform.translate(
                        offset: const Offset(0, -6),
                        child: _ReceiveStockCard(
                          // ลบ const ออกตรงนี้
                          onTap: () =>
                              _openPage(context, ReceiveStockScreen()), 
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.08,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _InventoryMenuTile(
                            icon: Icons.bar_chart_rounded,
                            iconColor: const Color(0xFF10B981),
                            iconBackground: const Color(0xFFE5FFF3),
                            title: 'สรุปภาพรวมคลัง',
                            subtitle: 'สถิติสินค้าขายดี และออเดอร์\nรวม',
                            // ลบ const ออกตรงนี้
                            onTap: () => _openPage(
                              context,
                              InventoryOverviewScreen(), 
                            ),
                          ),
                          _InventoryMenuTile(
                            icon: Icons.inventory_2_outlined,
                            iconColor: const Color(0xFF3B82F6),
                            iconBackground: const Color(0xFFEFF6FF),
                            title: 'รายการสินค้าคงเหลือ',
                            subtitle: 'เช็คจำนวนปัจจุบันและสินค้า\nใกล้หมด',
                            // ลบ const ออกตรงนี้
                            onTap: () =>
                                _openPage(context, StockBalanceScreen()), 
                          ),
                          _InventoryMenuTile(
                            icon: Icons.history_rounded,
                            iconColor: const Color(0xFFA855F7),
                            iconBackground: const Color(0xFFFAE8FF),
                            title: 'ประวัติการนำเข้า',
                            subtitle: 'ตรวจสอบล็อตการรับของ\nย้อนหลัง',
                            // ลบ const ออกตรงนี้
                            onTap: () => _openPage(
                              context,
                              StockImportHistoryScreen(), 
                            ),
                          ),
                          _InventoryMenuTile(
                            icon: Icons.tune_rounded,
                            iconColor: const Color(0xFF475569),
                            iconBackground: const Color(0xFFF1F5F9),
                            title: 'ปรับปรุง/ของเสีย',
                            subtitle: 'ตัดสต็อกสินค้าเสียหาย หรือ\nปรับยอด',
                            // ลบ const ออกตรงนี้
                            onTap: () => _openPage(
                              context,
                              StockAdjustmentScreen(), 
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static void _handleBackOrMenu(
    BuildContext context,
    BuildContext scaffoldContext,
  ) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Scaffold.of(scaffoldContext).openDrawer();
  }

  static void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

// ---------------------------------------------------------
// UI Components
// ---------------------------------------------------------

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      height: topPadding + 162,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF285EE4), Color(0xFF4540A5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E2E84).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'ย้อนกลับ',
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        icon: Icon(icon, size: 28),
      ),
    );
  }
}

class _ReceiveStockCard extends StatelessWidget {
  const _ReceiveStockCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernInteractiveCard(
      onTap: onTap,
      borderRadius: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3E4DF6), Color(0xFF3344E7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3344E7).withValues(alpha: 0.36),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.file_download_outlined,
                color: Colors.white,
                size: 31,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCEBFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'SCAN NOW',
                      style: TextStyle(
                        color: Color(0xFF3867E8),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'รับสินค้าเข้าสต็อก',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF050A19),
                      fontSize: 20,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ใช้สแกนเพิ่มสินค้าใหม่เข้าคลัง',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF6B7CA5),
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryMenuTile extends StatelessWidget {
  const _InventoryMenuTile({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernInteractiveCard(
      onTap: onTap,
      borderRadius: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF050A19),
                fontSize: 13,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF7890B7),
                fontSize: 11,
                height: 1.18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModernInteractiveCard extends StatefulWidget {
  const ModernInteractiveCard({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 20,
  });

  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;

  @override
  State<ModernInteractiveCard> createState() => _ModernInteractiveCardState();
}

class _ModernInteractiveCardState extends State<ModernInteractiveCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : (_isHovered ? 1.01 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: _isHovered ? 0.08 : 0.04),
                  blurRadius: _isHovered ? 32 : 16,
                  offset: Offset(0, _isHovered ? 12 : 6),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}