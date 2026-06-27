// lib/screens/menu_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 เรียกใช้ตู้เซฟ
import '../widgets/app_sidebar.dart';
import '../widgets/bouncing_card.dart';
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

  Future<bool> _saveProductData(Map<String, dynamic> payload) async {
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
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกข้อมูลเมนูเรียบร้อย! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchMenuData();
        return true;
      } else {
        throw resData['error'] ?? 'ปฏิเสธการบันทึก';
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
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
          onSave: (formData) async {
            if (initialProductData != null) {
              formData['id'] = initialProductData['id'];
            }
            return await _saveProductData(formData);
          },
        );
      },
    );
  }

  Widget _buildProductListTile({
    required Map<String, dynamic> p,
    required String pName,
    required String catName,
    required String price,
    required String? imageUrl,
    required bool isRecommended,
    required String? priceSpecial,
    required String? priceJumbo,
  }) {
    return BouncingCard(
      onTap: () => _openProductFormModal(initialProductData: p),
      glowColor: const Color(0xFF3B82F6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isRecommended
                ? const Color(0xFFF59E0B)
                : const Color(0xFFE2E8F0),
            width: isRecommended ? 2 : 1,
          ),
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
                width: 64,
                height: 64,
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
                                  size: 18,
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
                            size: 18,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                            fontSize: 12,
                            color: Color(0xFF1E293B),
                          ),
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
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildListPrices(
              price: price,
              priceSpecial: priceSpecial,
              priceJumbo: priceJumbo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListPrices({
    required String price,
    String? priceSpecial,
    String? priceJumbo,
  }) {
    final hasSpecial =
        priceSpecial != null &&
        priceSpecial.isNotEmpty &&
        priceSpecial != 'null';
    final hasJumbo =
        priceJumbo != null && priceJumbo.isNotEmpty && priceJumbo != 'null';

    Widget priceRow(String label, String value, Color color, double fontSize) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: '฿$value',
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: 110,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          priceRow('ปกติ', price, const Color(0xFF0F172A), 13),
          if (hasSpecial) ...[
            const SizedBox(height: 2),
            priceRow('พิเศษ', priceSpecial, const Color(0xFF4F46E5), 10),
          ],
          if (hasJumbo) ...[
            const SizedBox(height: 2),
            priceRow('จัมโบ้', priceJumbo, const Color(0xFF7C3AED), 10),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceLine({
    required String price,
    String? priceSpecial,
    String? priceJumbo,
    bool compact = false,
  }) {
    final hasSpecial =
        priceSpecial != null &&
        priceSpecial.isNotEmpty &&
        priceSpecial != 'null';
    final hasJumbo =
        priceJumbo != null && priceJumbo.isNotEmpty && priceJumbo != 'null';

    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '฿$price',
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              if (hasSpecial)
                TextSpan(
                  text: '  พิเศษ ฿$priceSpecial',
                  style: TextStyle(
                    fontSize: compact ? 8 : 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              if (hasJumbo)
                TextSpan(
                  text: '  จัมโบ้ ฿$priceJumbo',
                  style: TextStyle(
                    fontSize: compact ? 8 : 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineViewToggle() {
    return Container(
      height: 38,
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

    final filteredProducts =
        products.where((p) {
          final String pName = p['name']?.toString() ?? '';
          final matchesSearch = pName.toLowerCase().contains(
            searchQuery.toLowerCase(),
          );
          final matchesCategory =
              selectedCategoryId == 'ALL' ||
              p['category_id'] == selectedCategoryId;
          return matchesSearch && matchesCategory;
        }).toList()..sort((a, b) {
          final aIsRecommended = a['is_recommended'] == true;
          final bIsRecommended = b['is_recommended'] == true;

          if (aIsRecommended != bIsRecommended) {
            return aIsRecommended ? -1 : 1;
          }

          final nameComparison = (a['name']?.toString() ?? '')
              .toLowerCase()
              .compareTo((b['name']?.toString() ?? '').toLowerCase());
          if (nameComparison != 0) return nameComparison;

          return (a['id']?.toString() ?? '').compareTo(
            b['id']?.toString() ?? '',
          );
        });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgLight,
      drawer: const AppSidebar(activeMenu: 'menu_management'),
      floatingActionButton: SizedBox(
        width: 44,
        height: 44,
        child: FloatingActionButton(
          heroTag: 'add_menu_product',
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onPressed: _openProductFormModal,
          child: const Icon(Icons.add_rounded, size: 24),
        ),
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
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            color: Color(0xFF94A3B8),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (val) =>
                                  setState(() => searchQuery = val),
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                hintText: 'ค้นหาชื่อเมนูอาหาร...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
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
              height: 32,
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
                          horizontal: 12,
                          vertical: 4,
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
                            fontSize: 11,
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
                        final String pName =
                            p['name']?.toString() ?? 'ไม่มีชื่อ';
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
                          pName: pName,
                          catName: catName,
                          price: price,
                          imageUrl: imageUrl,
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
                            maxCrossAxisExtent: 110,
                            mainAxisExtent: 164,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = filteredProducts[index];
                        final String pName =
                            p['name']?.toString() ?? 'ไม่มีชื่อ';
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

                        return BouncingCard(
                          onTap: () =>
                              _openProductFormModal(initialProductData: p),
                          glowColor: const Color(0xFF3B82F6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isRecommended
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFFF1F5F9),
                                width: isRecommended ? 2 : 1,
                              ),
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
                                AspectRatio(
                                  aspectRatio: 1,
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
                                                  color: const Color(
                                                    0xFFF1F5F9,
                                                  ),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.image_outlined,
                                                      size: 36,
                                                      color: Color(0xFFCBD5E1),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          catName,
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 8,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        _buildPriceLine(
                                          price: price,
                                          priceSpecial: priceSpecial,
                                          priceJumbo: priceJumbo,
                                          compact: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
