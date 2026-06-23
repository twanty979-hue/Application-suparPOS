// lib/screens/discount_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/modals/add_discount_modal.dart';
import '../widgets/products/products_top_bar.dart';
import '../widgets/suparpos_loading.dart';
import '../api_service.dart';

class DiscountScreen extends StatefulWidget {
  const DiscountScreen({super.key});

  @override
  State<DiscountScreen> createState() => _DiscountScreenState();
}

class _DiscountScreenState extends State<DiscountScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<dynamic> discounts = [];
  List<dynamic> products = [];
  List<dynamic> productMaster = [];
  bool isLoading = true;
  String errorMessage = '';
  String? brandId;
  String? accessToken;
  String _searchQuery = '';
  String _scopeFilter = 'all'; // สถานะ filter ที่หายไป

  String get _baseUrl => ApiService.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadSessionAndFetch();
  }

  Future<void> _loadSessionAndFetch() async {
    try {
      final savedBrandId = await StorageService.getBrandId();
      final savedToken = await StorageService.getToken();

      if (!mounted) return;

      if (savedBrandId.isNotEmpty && savedToken != null) {
        setState(() {
          brandId = savedBrandId;
          accessToken = savedToken;
        });
        await fetchDiscounts();
      } else {
        setState(() {
          errorMessage = 'ไม่พบข้อมูลเซสชัน กรุณาเข้าสู่ระบบใหม่';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'โหลดข้อมูลไม่สำเร็จ: $e';
        isLoading = false;
      });
    }
  }

  Future<void> fetchDiscounts() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/discounts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body) as Map<String, dynamic>;
        if (responseData['success'] == true) {
          setState(() {
            discounts = responseData['discounts'] ?? [];
            products = responseData['products'] ?? [];
            productMaster = responseData['product_master'] ?? [];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage =
                responseData['error'] ?? 'เซิร์ฟเวอร์ไม่สามารถโหลดข้อมูลได้';
            isLoading = false;
          });
        }
      } else if (response.statusCode == 401) {
        setState(() {
          errorMessage = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage =
              'เชื่อมต่อเซิร์ฟเวอร์ไม่สำเร็จ (Status ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _createNewDiscount(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/discounts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && resData['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกโปรโมชันสำเร็จแล้ว'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
        await fetchDiscounts();
      } else {
        throw resData['error'] ?? 'เซิร์ฟเวอร์ปฏิเสธการบันทึก';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _deleteDiscount(String discountId) async {
    final confirmDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text(
                  'ยืนยันการลบ',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            content: const Text(
              'ต้องการลบโปรโมชันนี้ออกจากระบบใช่ไหม?\nข้อมูลที่ลบแล้วไม่สามารถกู้คืนได้',
              style: TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('ลบโปรโมชัน'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmDelete) return;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/discounts?id=$discountId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      final resData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && resData['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบโปรโมชันเรียบร้อยแล้ว'),
            backgroundColor: Color(0xFFF59E0B),
          ),
        );
        await fetchDiscounts();
      } else {
        throw resData['error'] ?? 'เซิร์ฟเวอร์ปฏิเสธคำสั่งลบ';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบไม่สำเร็จ: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _openAddDiscountModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AddDiscountModal(
          products: products,
          productMaster: productMaster,
          onSave: _createNewDiscount,
        );
      },
    );
  }

  Future<void> _handleRefresh() async {
    if (accessToken != null) {
      await fetchDiscounts();
    } else {
      await _loadSessionAndFetch();
    }
  }

  List<Map<String, dynamic>> get _discountMaps {
    return discounts
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredDiscounts {
    final query = _searchQuery.trim().toLowerCase();

    return _discountMaps.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final value = (item['value'] ?? '').toString().toLowerCase();
      final type = (item['type'] ?? '').toString().toLowerCase();
      final matchesSearch =
          query.isEmpty ||
          name.contains(query) ||
          value.contains(query) ||
          type.contains(query);

      if (!matchesSearch) return false;

      switch (_scopeFilter) {
        case 'store':
          return _isStoreWide(item);
        case 'specific':
          return !_isStoreWide(item);
        default:
          return true;
      }
    }).toList();
  }

  bool _isStoreWide(Map<String, dynamic> item) {
    return item['apply_to'] == 'all';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _formatNumber(dynamic value) {
    final number = double.tryParse(value?.toString() ?? '0') ?? 0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(2);
  }

  String _formatDateShort(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = (date.year + 543).toString().substring(2);
    return '$day/$month/$year';
  }

  String _dateRangeLabel(Map<String, dynamic> item) {
    final start = _parseDate(item['start_date']);
    final end = _parseDate(item['end_date']);

    if (start == null && end == null) return 'สิ้นสุด: ตลอดไป';
    if (start != null && end != null) {
      return '${_formatDateShort(start)} - ${_formatDateShort(end)}';
    }
    if (start != null) return 'เริ่ม: ${_formatDateShort(start)}';
    return 'สิ้นสุด: ${_formatDateShort(end!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFFAFAFA),
      drawer: const AppSidebar(activeMenu: 'discount'),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddDiscountModal,
        backgroundColor: const Color(0xFF0F172A),
        elevation: 8,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ProductsTopBar(
              onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
              activeTab: 'discount',
              onTabSelected: (_) {},
            ),
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFEF4444)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF97316).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.sell_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'โปรโมชัน & ส่วนลด',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'จัดการแคมเปญลดราคาเพื่อกระตุ้นยอดขาย',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B).withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const SuparPosLoading(fullScreen: false);
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFEF4444),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(errorMessage, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _handleRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              child: const Text('ลองใหม่อีกครั้ง'),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredDiscounts;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: const Color(0xFFF97316),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 🌟 Search & Filter แถบสลับเมนู (เอาคืนมาให้แล้วครับ)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  // แถบค้นหา
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'ค้นหาโปรโมชัน...',
                              hintStyle: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Color(0xFF94A3B8),
                                size: 20,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // แถบสลับ Filter (Segmented Control)
                  Row(
                    children: [
                      _buildFilterButton('ทั้งหมด', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterButton('ทั้งร้าน', 'store'),
                      const SizedBox(width: 8),
                      _buildFilterButton('เฉพาะเมนู', 'specific'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (discounts.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(
                icon: Icons.local_offer_rounded,
                title: 'ยังไม่มีโปรโมชัน',
                message: 'กดปุ่ม + ด้านล่างขวาเพื่อสร้างโปรโมชันแรกของคุณ',
              ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(
                icon: Icons.search_off_rounded,
                title: 'ไม่พบโปรโมชันที่ค้นหา',
                message: 'ลองเปลี่ยนคำค้นหาดูอีกครั้ง',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 260,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildDiscountCard(filtered[index]),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String label, String value) {
    final isSelected = _scopeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _scopeFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0F172A)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildDiscountCard(Map<String, dynamic> item) {
    final isStoreWide = _isStoreWide(item);
    final itemId = item['id']?.toString() ?? item.hashCode.toString();
    final itemName = (item['name'] ?? 'ไม่มีชื่อโปรโมชัน').toString();
    final isPercent = item['type'] == 'percentage';
    final valueStr = _formatNumber(item['value']);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0).withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isStoreWide
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isStoreWide ? 'ทั้งร้าน' : 'บางเมนู',
                style: TextStyle(
                  color: isStoreWide
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF9333EA),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              itemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isPercent)
                  const Text(
                    '฿',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFEA580C),
                      height: 1.2,
                    ),
                  ),
                Text(
                  valueStr,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFEA580C),
                    height: 1,
                    letterSpacing: -1,
                  ),
                ),
                if (isPercent)
                  const Text(
                    '%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFEA580C),
                      height: 1.2,
                    ),
                  ),
              ],
            ),

            const Spacer(),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 12,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _dateRangeLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: () => _deleteDiscount(itemId),
                icon: const Icon(Icons.delete_outline_rounded, size: 14),
                label: const Text('ลบ'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: const Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
