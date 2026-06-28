import 'package:flutter/material.dart';

// 🔗 ดึง TopBar และ Sidebar มาไว้ที่หน้าพ่อ
import '../widgets/products/products_top_bar.dart';
import '../widgets/app_sidebar.dart';

// 🔗 ดึงหน้าจอย่อยทั้ง 3 หน้ามารอไว้สลับไส้ใน
import 'menu_management_screen.dart';
import 'master_product_screen.dart';
import 'banner_management_screen.dart';
import 'table_management_screen.dart';

class ProductsMainScreen extends StatefulWidget {
  const ProductsMainScreen({super.key});

  @override
  State<ProductsMainScreen> createState() => _ProductsMainScreenState();
}

class _ProductsMainScreenState extends State<ProductsMainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // 🔑 สเตตัสเริ่มต้น ให้เปิดมาเจอแท็บเมนูอาหารก่อน
  String _activeTab = 'menu';

  // 📦 ลอจิกเลือกหน้าจอย่อยมาแสดงผลแบบสมูทๆ
  Widget _buildBody() {
    switch (_activeTab) {
      case 'menu':
        return const MenuManagementScreen(showTopBar: false);
      case 'main_product':
        return const MasterProductScreen(showTopBar: false);
      case 'banner':
        return const BannerManagementScreen();
      case 'table':
        return const TableManagementScreen(showTopBar: false);
      default:
        return const MenuManagementScreen(showTopBar: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFEDE9E3), // สีขาวไข่แบบเข้ม
      // 🍔 ใส่ Drawer ไว้ที่หน้าพ่อตัวเดียว คุมเปิดปิดได้ทุกหน้าจอย่อย
      drawer: const AppSidebar(activeMenu: 'menu_management'),
      body: SafeArea(
        child: Column(
          children: [
            // 🌟 ท็อปบาร์อยู่กับที่ แอนิเมชันปุ่มสลับพริ้วๆ
            ProductsTopBar(
              activeTab: _activeTab,
              navigateOnTabSelected: false,
              onMenuPressed: () {
                // ⚡️ สั่งเปิด Sidebar ด้านซ้ายออโต้เมื่อกดปุ่มแฮมเบอร์เกอร์
                _scaffoldKey.currentState?.openDrawer();
              },
              onTabSelected: (String tabId) {
                setState(() {
                  _activeTab = tabId; // สลับหน้าไส้ในทันที ไม่มีหน้าจอกะพริบ
                });
              },
            ),
            // 🖼️ สลับเนื้อหาหน้าจอย่อยแบบสมูทๆ ไร้รอยต่อ
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_activeTab),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
