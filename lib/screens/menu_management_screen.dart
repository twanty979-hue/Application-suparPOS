// lib/screens/menu_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 เรียกใช้ตู้เซฟ
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../theme/app_colors.dart';
import '../widgets/modals/add_product_modal.dart';
import '../widgets/products/products_top_bar.dart';
import '../api_service.dart';

class MenuManagementScreen extends StatefulWidget {
  final bool showTopBar;
  final bool isListView;

  const MenuManagementScreen({
    super.key,
    this.showTopBar = true,
    this.isListView = false,
  });

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<dynamic> products = [];
  List<dynamic> categories = [];

  bool isLoading = true;
  String errorMessage = '';
  String? brandId;
  String? accessToken;

  String selectedCategoryId = 'ALL';
  String searchQuery = '';
  String currentActiveTab = 'menu';
  late bool _isListView;
  static const String _viewModePrefKey = 'products_management_is_list_view';

  @override
  void initState() {
    super.initState();
    _isListView = widget.isListView;
    _loadSavedViewMode();
    _loadSessionAndFetch();
  }

  @override
  void didUpdateWidget(covariant MenuManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isListView != widget.isListView) {
      _isListView = widget.isListView;
    }
  }

  Future<void> _loadSavedViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool(_viewModePrefKey);
    if (!mounted || savedValue == null) return;
    setState(() => _isListView = savedValue);
  }

  Future<void> _setListView(bool value) async {
    setState(() => _isListView = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_viewModePrefKey, value);
  }

  String? _getImageUrl(String? imageName) {
    if (imageName == null) {
      return null;
    }
    final cleanedName = imageName.trim();
    if (cleanedName.isEmpty) {
      return null;
    }
    if (cleanedName.startsWith('http://') ||
        cleanedName.startsWith('https://')) {
      return cleanedName;
    }
    if (cleanedName.contains('/')) {
      return "https://img.pos-foodscan.com/$cleanedName";
    }
    return "https://xvhibjejvbriotfpunvv.supabase.co/storage/v1/object/public/images/$cleanedName";
  }

  // 🌟 โหลดทั้ง Brand ID และ Token จากตู้เซฟดิจิทัลเท่านั้น
  Future<void> _loadSessionAndFetch() async {
    try {
      final savedBrandId = await StorageService.getBrandId(); // 🌟 ดึงจากตู้เซฟ
      final savedToken = await StorageService.getToken(); // 🌟 ดึงจากตู้เซฟ

      if (savedBrandId.isNotEmpty && savedToken != null) {
        setState(() {
          brandId = savedBrandId;
          accessToken = savedToken;
        });
        await _fetchMenuData();
      } else {
        setState(() {
          errorMessage = 'ไม่พบเซสชัน กรุณาล็อกอินใหม่อีกครั้ง';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'เกิดข้อผิดพลาดคลังหน่วยความจำเครื่อง: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchMenuData() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      final String baseUrl = ApiService.baseUrl;
      final String fullUrl = "$baseUrl/products";

      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> resData = json.decode(response.body);
        if (resData['success'] == true) {
          setState(() {
            products = resData['products'] ?? [];
            categories = resData['categories'] ?? [];
            isLoading = false;
          });
        } else {
          throw resData['error'] ?? 'เซิร์ฟเวอร์ตอบรับล้มเหลว';
        }
      } else if (response.statusCode == 401) {
        throw 'เซสชันหมดอายุ กรุณาล็อกอินใหม่ (401)';
      } else {
        throw 'การเชื่อมต่อผิดพลาด (Status Code: ${response.statusCode})';
      }
    } catch (e) {
      setState(() {
        errorMessage = '$e';
        isLoading = false;
      });
    }
  }

  Future<void> _saveProductData(Map<String, dynamic> payload) async {
    try {
      final String baseUrl = ApiService.baseUrl;
      final response = await http.post(
        Uri.parse("$baseUrl/products"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกข้อมูลเมนูเรียบร้อย! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchMenuData();
      } else {
        throw resData['error'] ?? 'ปฏิเสธการบันทึก';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleProductAvailability(
    String productId,
    bool currentStatus,
  ) async {
    try {
      final String baseUrl = ApiService.baseUrl;
      final response = await http.post(
        Uri.parse("$baseUrl/products"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'id': productId, 'is_available': !currentStatus}),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        setState(() {
          final index = products.indexWhere((p) => p['id'] == productId);
          if (index != -1) products[index]['is_available'] = !currentStatus;
        });
      } else {
        throw resData['error'] ?? 'อัปเดตสถานะล้มเหลว';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เปลี่ยนสถานะไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openProductFormModal({Map<String, dynamic>? initialProductData}) {
    if (brandId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return AddProductModal(
          brandId: brandId!,
          categories: categories,
          initialData: initialProductData,
          onSave: (formData) {
            if (initialProductData != null) {
              formData['id'] = initialProductData['id'];
            }
            _saveProductData(formData);
          },
        );
      },
    );
  }

  Widget _buildProductListTile({
    required Map<String, dynamic> p,
    required String pId,
    required String pName,
    required String catName,
    required String price,
    required String? imageUrl,
    required bool isAvailable,
    required bool isRecommended,
    required String? priceSpecial,
    required String? priceJumbo,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 92,
              height: 92,
              child: imageUrl != null
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                            color: Color(0xFFF1F5F9),
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 30,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                          ),
                    )
                  : const ColoredBox(
                      color: Color(0xFFF1F5F9),
                      child: Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 30,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (isRecommended)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: Color(0xFFF59E0B),
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'แนะนำ',
                              style: TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  catName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '฿$price',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildMiniPriceBadge(
                      isAvailable ? 'พร้อมขาย' : 'ปิดขาย',
                      isAvailable
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                    ),
                    if (priceSpecial != null &&
                        priceSpecial.isNotEmpty &&
                        priceSpecial != 'null')
                      _buildMiniPriceBadge(
                        '+w $priceSpecial',
                        const Color(0xFF4F46E5),
                      ),
                    if (priceJumbo != null &&
                        priceJumbo.isNotEmpty &&
                        priceJumbo != 'null')
                      _buildMiniPriceBadge(
                        '+จ $priceJumbo',
                        const Color(0xFF7C3AED),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRoundAction(
                icon: Icons.edit_outlined,
                color: const Color(0xFF64748B),
                onTap: () => _openProductFormModal(initialProductData: p),
              ),
              const SizedBox(height: 8),
              _buildRoundAction(
                icon: isAvailable
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: isAvailable
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
                onTap: () => _toggleProductAvailability(pId, isAvailable),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPriceBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _buildRoundAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _buildInlineViewToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewToggleButton(
            icon: Icons.grid_view_rounded,
            selected: !_isListView,
            onTap: () => _setListView(false),
          ),
          _buildViewToggleButton(
            icon: Icons.view_agenda_rounded,
            selected: _isListView,
            onTap: () => _setListView(true),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFF0F172A) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 40,
          child: Icon(
            icon,
            color: selected ? Colors.white : const Color(0xFF64748B),
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> displayCategories = [
      {'id': 'ALL', 'name': 'ทั้งหมด'},
      ...categories.map(
        (c) => {
          'id': c['id']?.toString(),
          'name': c['name']?.toString() ?? 'ไม่มีชื่อ',
        },
      ),
    ];

    final filteredProducts = products.where((p) {
      final String pName = p['name']?.toString() ?? '';
      final matchesSearch = pName.toLowerCase().contains(
        searchQuery.toLowerCase(),
      );
      final matchesCategory =
          selectedCategoryId == 'ALL' || p['category_id'] == selectedCategoryId;
      return matchesSearch && matchesCategory;
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgLight,
      drawer: const AppSidebar(activeMenu: 'menu_management'),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_menu_product',
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: _openProductFormModal,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.showTopBar)
              ProductsTopBar(
                activeTab: currentActiveTab,
                onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                onTabSelected: (tabId) {
                  setState(() => currentActiveTab = tabId);
                },
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              onChanged: (val) =>
                                  setState(() => searchQuery = val),
                              decoration: const InputDecoration(
                                hintText: 'ค้นหาชื่อเมนูอาหาร...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildInlineViewToggle(),
                ],
              ),
            ),

            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: displayCategories.length,
                itemBuilder: (context, index) {
                  final cat = displayCategories[index];
                  final isSelected = selectedCategoryId == cat['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => selectedCategoryId = cat['id']),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: isSelected
                              ? null
                              : Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          cat['name'],
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: isLoading
                  ? const SuparPosLoading(fullScreen: false)
                  : filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restaurant_menu_rounded,
                            size: 72,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'ไม่พบรายการอาหารในร้าน',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _isListView
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = filteredProducts[index];
                        final String pId = p['id']?.toString() ?? '';
                        final String pName =
                            p['name']?.toString() ?? 'ไม่มีชื่อ';
                        final bool isAvailable = p['is_available'] ?? true;
                        final bool isRecommended = p['is_recommended'] ?? false;
                        final String price = p['price']?.toString() ?? '0';
                        final catObj = categories.firstWhere(
                          (c) => c['id'] == p['category_id'],
                          orElse: () => {'name': 'เมนูทั่วไป'},
                        );
                        final String catName = catObj['name'];
                        final String? priceSpecial = p['price_special']
                            ?.toString();
                        final String? priceJumbo = p['price_jumbo']?.toString();
                        final String? imageUrl = _getImageUrl(p['image_name']);

                        return _buildProductListTile(
                          p: p,
                          pId: pId,
                          pName: pName,
                          catName: catName,
                          price: price,
                          imageUrl: imageUrl,
                          isAvailable: isAvailable,
                          isRecommended: isRecommended,
                          priceSpecial: priceSpecial,
                          priceJumbo: priceJumbo,
                        );
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 226,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = filteredProducts[index];
                        final String pId = p['id']?.toString() ?? '';
                        final String pName =
                            p['name']?.toString() ?? 'ไม่มีชื่อ';
                        final bool isAvailable = p['is_available'] ?? true;
                        final bool isRecommended = p['is_recommended'] ?? false;
                        final String price = p['price']?.toString() ?? '0';

                        final catObj = categories.firstWhere(
                          (c) => c['id'] == p['category_id'],
                          orElse: () => {'name': 'เมนูทั่วไป'},
                        );
                        final String catName = catObj['name'];
                        final String? priceSpecial = p['price_special']
                            ?.toString();
                        final String? priceJumbo = p['price_jumbo']?.toString();
                        final String? imageUrl = _getImageUrl(p['image_name']);

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.01),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(19),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(19),
                                            ),
                                        child: imageUrl != null
                                            ? Image.network(
                                                imageUrl,
                                                width: double.infinity,
                                                height: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => Container(
                                                      color: const Color(
                                                        0xFFF1F5F9,
                                                      ),
                                                      child: const Center(
                                                        child: Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                          size: 36,
                                                          color: Color(
                                                            0xFFCBD5E1,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                              )
                                            : Container(
                                                color: const Color(0xFFF1F5F9),
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.image_outlined,
                                                    size: 36,
                                                    color: Color(0xFFCBD5E1),
                                                  ),
                                                ),
                                              ),
                                      ),
                                      if (isRecommended)
                                        Positioned(
                                          top: 8,
                                          left: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              children: [
                                                Icon(
                                                  Icons.star_rounded,
                                                  color: Colors.white,
                                                  size: 12,
                                                ),
                                                SizedBox(width: 2),
                                                Text(
                                                  'แนะนำ',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        bottom: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _toggleProductAvailability(
                                                pId,
                                                isAvailable,
                                              ),
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.1),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: isAvailable
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFFEF4444),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Column(
                                          children: [
                                            GestureDetector(
                                              onTap: () =>
                                                  _openProductFormModal(
                                                    initialProductData: p,
                                                  ),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                margin: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.05,
                                                          ),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.edit_outlined,
                                                  color: Color(0xFF64748B),
                                                  size: 15,
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () =>
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'ฟีเจอร์ลบรายการอาหารแสตนด์บายพร้อมใช้งานครับนาย! 🗑️',
                                                      ),
                                                    ),
                                                  ),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.05,
                                                          ),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Color(0xFF94A3B8),
                                                  size: 15,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      catName,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '฿$price',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (priceSpecial != null &&
                                            priceSpecial.isNotEmpty &&
                                            priceSpecial != 'null')
                                          Container(
                                            margin: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '+w $priceSpecial',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF4F46E5),
                                              ),
                                            ),
                                          ),
                                        if (priceJumbo != null &&
                                            priceJumbo.isNotEmpty &&
                                            priceJumbo != 'null')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F3FF),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '+จ $priceJumbo',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF7C3AED),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
