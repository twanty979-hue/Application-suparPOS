// lib/screens/master_product_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 🌟 เก็บไว้จำค่ารูปแบบ List/Grid ตัวจุกจิก (อันนี้ถูกหลักการ)

import '../api_service.dart'; // 🌟 1. นำเข้า ApiService เพื่อสลับลิงก์คลาวด์/แลน อัตโนมัติ
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 2. ดึงตู้เซฟเข้ารหัสหุ้มเกราะดิจิทัล
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../theme/app_colors.dart';
import '../widgets/products/products_top_bar.dart';
import '../widgets/modals/add_master_product_modal.dart';
import '../widgets/bouncing_card.dart';

class MasterProductScreen extends StatefulWidget {
  final bool showTopBar;
  final bool isListView;

  const MasterProductScreen({
    super.key,
    this.showTopBar = true,
    this.isListView = false,
  });

  @override
  State<MasterProductScreen> createState() => _MasterProductScreenState();
}

class _MasterProductScreenState extends State<MasterProductScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<dynamic> masterProducts = [];
  List<dynamic> masterCategories = [];

  bool isLoading = true;
  String errorMessage = '';
  String? brandId;
  String? accessToken;

  String selectedMasterCategoryId = 'ALL';
  String searchQuery = '';
  String currentActiveTab = 'main_product';
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
  void didUpdateWidget(covariant MasterProductScreen oldWidget) {
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

  String? _getImageUrl(String? imageUrl) {
    if (imageUrl == null) return null;
    final cleaned = imageUrl.trim();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }

  // 🌟 📥 แก้ไขจุดที่ 1: ดึง Brand ID และสิทธิ์พนักงานสแกนจากตู้เซฟเข้ารหัส (Secure Storage)
  Future<void> _loadSessionAndFetch() async {
    try {
      final savedBrandId =
          await StorageService.getBrandId(); // ดึงจากตู้เซฟดิจิทัล
      final savedToken = await StorageService.getToken(); // ดึงจากตู้เซฟดิจิทัล

      if (savedBrandId.isNotEmpty && savedToken != null) {
        setState(() {
          brandId = savedBrandId;
          accessToken = savedToken;
        });
        await fetchMasterData();
      } else {
        setState(() {
          errorMessage = 'ไม่พบเซสชันการล็อกอิน กรุณาล็อกอินใหม่อีกครั้ง';
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

  // 📥 GET: ดึงข้อมูลคลังสินค้าหลัก (ผูกป้อนผ่านโครงสร้าง ApiService.baseUrl อัตโนมัติ)
  Future<void> fetchMasterData() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      // 🌟 แก้ไขจุดที่ 2: ดึงกระแสลิงก์อัตโนมัติจาก ApiService โดยตรง ไร้ขยะ Hardcode ลิงก์ IP
      final String fullUrl = "${ApiService.baseUrl}/master-products";

      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            masterProducts = responseData['products'] ?? [];
            masterCategories = responseData['categories'] ?? [];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage =
                responseData['error'] ?? 'เซิร์ฟเวอร์ตอบรับข้อมูลล้มเหลว';
            isLoading = false;
          });
        }
      } else if (response.statusCode == 401) {
        throw 'เซสชันหมดอายุ กรุณาล็อกอินใหม่อีกครั้ง (401)';
      } else {
        setState(() {
          errorMessage =
              'การเชื่อมต่อผิดพลาด (Status Code: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '$e';
        isLoading = false;
      });
    }
  }

  // 📤 POST: บันทึกส่งสร้างชิ้นใหม่หรือแก้ไขทับ (ผูกป้อนผ่านโครงสร้าง ApiService.baseUrl อัตโนมัติ)
  Future<void> _saveMasterProductData(Map<String, dynamic> payload) async {
    try {
      // 🌟 แก้ไขจุดที่ 3: ใช้ฐานโครงสร้างยิงสลิงก์ข้อมูลจาก ApiService สลับ Environment ได้ทันที
      final response = await http.post(
        Uri.parse("${ApiService.baseUrl}/master-products"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกข้อมูลเข้าคลังสินค้าหลักเรียบร้อยแล้ว! 🎉'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await fetchMasterData();
      } else {
        throw resData['error'] ?? 'เซิร์ฟเวอร์ปฏิเสธการบันทึก';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกสินค้าหลักล้มเหลว: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMasterProductData(String id) async {
    try {
      final response = await http.delete(
        Uri.parse("${ApiService.baseUrl}/master-products/$id"),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ลบสินค้าเรียบร้อยแล้ว'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await fetchMasterData();
      } else {
        throw resData['error'] ?? 'ลบสินค้าล้มเหลว';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลบสินค้าล้มเหลว: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openMasterFormModal({Map<String, dynamic>? initialProductData}) {
    if (brandId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF9F6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return AddMasterProductModal(
          brandId: brandId!,
          masterCategories: masterCategories,
          initialData: initialProductData,
          onSave: (formData) {
            if (initialProductData != null) {
              formData['id'] = initialProductData['id'];
            }
            _saveMasterProductData(formData);
          },
          onDelete: initialProductData != null
              ? () => _deleteMasterProductData(
                  initialProductData['id'].toString(),
                )
              : null,
        );
      },
    );
  }

  Widget _buildMasterProductListTile({
    required Map<String, dynamic> p,
    required String pName,
    required String catName,
    required String skuCode,
    required String barcode,
    required String price,
    required String? imageUrl,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE9E3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: BouncingCard(
        onTap: () => _openMasterFormModal(initialProductData: p),
        glowColor: const Color(0xFF3B82F6),
        child: Padding(
          padding: const EdgeInsets.all(6),
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
                                color: Color(0xFFFAF9F6),
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
                          color: Color(0xFFFAF9F6),
                          child: Center(
                            child: Icon(
                              Icons.inventory_2_outlined,
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
                    Text(
                      pName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Color(0xFF1E293B),
                      ),
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
              SizedBox(
                width: 90,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '฿$price',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Color(0xFF64748B),
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
        border: Border.all(color: const Color(0xFFEDE9E3)),
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
      ...masterCategories.map(
        (c) => {
          'id': c['id']?.toString(),
          'name': c['name']?.toString() ?? 'ไม่มีชื่อ',
        },
      ),
    ];

    final filteredMasterProducts = masterProducts.where((p) {
      final String pName = p['name']?.toString() ?? '';
      final String pBarcode = p['barcode']?.toString() ?? '';
      final String pSku = p['sku']?.toString() ?? '';

      final matchesSearch =
          pName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          pBarcode.contains(searchQuery) ||
          pSku.toLowerCase().contains(searchQuery.toLowerCase());

      final matchesCategory =
          selectedMasterCategoryId == 'ALL' ||
          p['category_id'] == selectedMasterCategoryId;
      return matchesSearch && matchesCategory;
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgLight,
      drawer: const AppSidebar(activeMenu: 'inventory'),
      floatingActionButton: SizedBox(
        width: 44,
        height: 44,
        child: FloatingActionButton(
          heroTag: 'add_master_product',
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onPressed: _openMasterFormModal,
          child: const Icon(Icons.add_rounded, size: 24),
        ),
      ),
      body: Builder(
        builder: (context) {
          return SafeArea(
            child: Column(
              children: [
                if (widget.showTopBar)
                  ProductsTopBar(
                    activeTab: currentActiveTab,
                    onMenuPressed: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    onTabSelected: (tabId) {
                      if (tabId == 'menu') {
                        Navigator.pushReplacementNamed(
                          context,
                          '/menu_management',
                        );
                      } else {
                        setState(() {
                          currentActiveTab = tabId;
                        });
                      }
                    },
                  ),

                // --- 🔍 ช่องค้นหาอเนกประสงค์ ---
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
                            border: Border.all(color: const Color(0xFFEDE9E3)),
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
                                    hintText:
                                        'ค้นหาชื่อสินค้า, บาร์โค้ด, SKU...',
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

                // --- 🌟 แถบตัวกรองหมวดหมู่หลัก ---
                SizedBox(
                  height: 32,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: displayCategories.length,
                    itemBuilder: (context, index) {
                      final cat = displayCategories[index];
                      final isSelected = selectedMasterCategoryId == cat['id'];

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(
                            () => selectedMasterCategoryId = cat['id'],
                          ),
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
                                  : Border.all(color: const Color(0xFFEDE9E3)),
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

                // --- 🗂️ ตารางรายการสินค้าหลัก ---
                Expanded(
                  child: isLoading
                      ? const SuparPosLoading(fullScreen: false)
                      : filteredMasterProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.widgets_outlined,
                                size: 72,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'ไม่พบรายการสินค้าหลักในระบบ',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _isListView
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: filteredMasterProducts.length,
                          itemBuilder: (context, index) {
                            final p = filteredMasterProducts[index];
                            final String pName =
                                p['name']?.toString() ?? 'ไม่มีชื่อ';
                            final String price = p['price']?.toString() ?? '0';
                            final String skuCode = p['sku']?.toString() ?? '-';
                            final String barcode =
                                p['barcode']?.toString() ?? '-';
                            final catObj = masterCategories.firstWhere(
                              (c) => c['id'] == p['category_id'],
                              orElse: () => {'name': 'สินค้าทั่วไป'},
                            );
                            final String catName = catObj['name'];
                            final String? imageUrl = _getImageUrl(
                              p['image_url'],
                            );

                            return _buildMasterProductListTile(
                              p: p,
                              pName: pName,
                              catName: catName,
                              skuCode: skuCode,
                              barcode: barcode,
                              price: price,
                              imageUrl: imageUrl,
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
                          itemCount: filteredMasterProducts.length,
                          itemBuilder: (context, index) {
                            final p = filteredMasterProducts[index];
                            final String pName =
                                p['name']?.toString() ?? 'ไม่มีชื่อ';
                            final String price = p['price']?.toString() ?? '0';

                            final catObj = masterCategories.firstWhere(
                              (c) => c['id'] == p['category_id'],
                              orElse: () => {'name': 'สินค้าทั่วไป'},
                            );
                            final String catName = catObj['name'];
                            final String? imageUrl = _getImageUrl(
                              p['image_url'],
                            );

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFEDE9E3),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.01),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: BouncingCard(
                                onTap: () =>
                                    _openMasterFormModal(initialProductData: p),
                                glowColor: const Color(0xFF3B82F6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        width: double.infinity,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFFAF9F6),
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
                                                              0xFFFAF9F6,
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
                                                        0xFFFAF9F6,
                                                      ),
                                                      child: const Center(
                                                        child: Icon(
                                                          Icons
                                                              .inventory_2_outlined,
                                                          size: 36,
                                                          color: Color(
                                                            0xFFCBD5E1,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 58,
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
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 8,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '฿$price',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF0F172A),
                                              ),
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
          );
        },
      ),
    );
  }
}


