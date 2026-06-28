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

  final List<Map<String, dynamic>> _tabs = [
    {'id': 'menu', 'icon': Icons.add_box_outlined, 'label': 'เมนูอาหาร'},
    {'id': 'main_product', 'icon': Icons.create_new_folder_outlined, 'label': 'สินค้าหลัก'},
    {'id': 'table', 'icon': Icons.table_restaurant_outlined, 'label': 'จัดการโต๊ะ'},
    {'id': 'banner', 'icon': Icons.image_outlined, 'label': 'แบนเนอร์'},
    {'id': 'discount', 'icon': Icons.local_offer_outlined, 'label': 'ส่วนลด/โปรฯ'},
  ];

  int get _activeIndex => _tabs.indexWhere((tab) => tab['id'] == widget.activeTab);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDE9E3), // ขาวไข่แบบเข้ม
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          InkWell(
            onTap: widget.onMenuPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFDCD6CB), // สีขาวไข่เข้มขึ้นอีกสเต็ป
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_rounded, color: Color(0xFF292524)), // สีดำออกน้ำตาล
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 390;
                
                // สำหรับจอเล็ก (compact) ให้คำนวณความกว้างเฉลี่ยเพื่อให้ปุ่มเต็มพื้นที่พอดี
                final double usableWidth = constraints.maxWidth - 8; // ลบ padding ซ้ายขวาฝั่งละ 4
                final double compactButtonW = usableWidth / _tabs.length;
                
                final double inactiveW = compact ? compactButtonW : 54.0;
                final double activeW = compact ? compactButtonW : 135.0; // จอเล็กไม่ต้องขยายความกว้าง เพราะไม่มีตัวหนังสือ
                final int activeIdx = _activeIndex;
                final double indicatorLeft = activeIdx >= 0 ? activeIdx * inactiveW : 0.0;
                
                final pillContainer = Container(
                  height: compact ? 42 : 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCD6CB), // สีขาวไข่เข้มขึ้นอีกสเต็ป
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      // ตัวชี้ (Indicator) ที่วิ่งไปมาสไลด์จริงๆ
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        left: indicatorLeft,
                        top: 0,
                        bottom: 0,
                        width: activeIdx >= 0 ? activeW : 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF292524), // ดำน้ำตาล
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF292524).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                        ),
                      ),
                      // ปุ่มกดแบบโปร่งใส วางทับอยู่ด้านบน
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_tabs.length, (index) {
                          final tab = _tabs[index];
                          final isActive = index == activeIdx;
                          return GestureDetector(
                            onTap: () => _handleTabTap(context, tab['id']),
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              width: isActive ? activeW : inactiveW,
                              alignment: Alignment.center,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      tab['icon'],
                                      size: 20,
                                      color: isActive ? Colors.white : const Color(0xFF64748B),
                                    ),
                                    if (isActive && !compact) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        tab['label'],
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
                          );
                        }),
                      ),
                    ],
                  ),
                );

                if (compact) {
                  return pillContainer;
                }

                return SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: pillContainer,
                );
              },
            ),
          ),
        ],
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
