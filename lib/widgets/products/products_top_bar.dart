// lib/widgets/products/products_top_bar.dart
import 'package:flutter/material.dart';

import '../../screens/banner_management_screen.dart';
import '../../screens/discount_screen.dart';
import '../../screens/master_product_screen.dart';
import '../../screens/menu_management_screen.dart';
import '../../screens/table_management_screen.dart';
import '../suparpos_navigation_loader.dart';

class ProductsTopBar extends StatefulWidget {
  final VoidCallback onMenuPressed;
  final String activeTab;
  final Function(String) onTabSelected;
  final bool navigateOnTabSelected;

  const ProductsTopBar({
    super.key,
    required this.onMenuPressed,
    required this.activeTab,
    required this.onTabSelected,
    this.navigateOnTabSelected = true,
  });

  @override
  State<ProductsTopBar> createState() => _ProductsTopBarState();
}

class _ProductsTopBarState extends State<ProductsTopBar> {
  bool _isChangingTab = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleRevealActiveTab();
  }

  @override
  void didUpdateWidget(covariant ProductsTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      _scheduleRevealActiveTab();
    }
  }

  void _scheduleRevealActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = widget.activeTab == 'discount'
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          InkWell(
            onTap: widget.onMenuPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_rounded, color: Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 390;
                final buttons = _buildNavButtons(context, compact: compact);

                if (compact) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: buttons,
                  );
                }

                return SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(children: buttons),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNavButtons(BuildContext context, {required bool compact}) {
    return [
      _buildNavButton(
        context,
        id: 'menu',
        icon: Icons.add_box_outlined,
        label: 'เมนูอาหาร',
        isActive: widget.activeTab == 'menu',
        compact: compact,
      ),
      _buildNavButton(
        context,
        id: 'main_product',
        icon: Icons.create_new_folder_outlined,
        label: 'สินค้าหลัก',
        isActive: widget.activeTab == 'main_product',
        compact: compact,
      ),
      _buildNavButton(
        context,
        id: 'table',
        icon: Icons.table_restaurant_outlined,
        label: 'จัดการโต๊ะ',
        isActive: widget.activeTab == 'table',
        compact: compact,
      ),
      _buildNavButton(
        context,
        id: 'banner',
        icon: Icons.image_outlined,
        label: 'แบนเนอร์',
        isActive: widget.activeTab == 'banner',
        compact: compact,
      ),
      _buildNavButton(
        context,
        id: 'discount',
        icon: Icons.local_offer_outlined,
        label: 'ส่วนลด/โปรฯ',
        isActive: widget.activeTab == 'discount',
        compact: compact,
      ),
    ];
  }

  Widget _buildNavButton(
    BuildContext context, {
    required String id,
    required IconData icon,
    required String label,
    required bool isActive,
    required bool compact,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: compact ? 2 : 6),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => _handleTabTap(context, id),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                ),
                if (isActive && !compact) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
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

  Future<void> _handleTabTap(BuildContext context, String id) async {
    if (_isChangingTab || id == widget.activeTab) return;

    setState(() => _isChangingTab = true);

    if (!widget.navigateOnTabSelected) {
      widget.onTabSelected(id);
      if (mounted) setState(() => _isChangingTab = false);
      return;
    }

    final destination = _screenForTab(id);
    if (destination == null) {
      widget.onTabSelected(id);
      if (mounted) setState(() => _isChangingTab = false);
      return;
    }

    await Navigator.of(context).pushReplacement(_smoothRoute(destination));
  }

  Widget? _screenForTab(String id) {
    switch (id) {
      case 'menu':
        return const MenuManagementScreen();
      case 'main_product':
        return const MasterProductScreen();
      case 'table':
        return const TableManagementScreen();
      case 'banner':
        return const BannerManagementScreen();
      case 'discount':
        return const DiscountScreen();
      default:
        return null;
    }
  }

  PageRouteBuilder<void> _smoothRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          SuparPosNavigationLoader(fullScreen: false, child: page),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, animation, __, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.025, 0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }
}
