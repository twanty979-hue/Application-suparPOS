// lib/screens/stock_adjustment_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // เก็บไว้สำหรับจำค่าตั้งค่าภายในเครื่องอื่นๆ (ถ้ามี)

import '../db/database_helper.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 1. นำเข้าตู้เซฟดิจิทัล
import '../widgets/modals/barcode_scanner_modal.dart';

class StockAdjustmentScreen extends StatefulWidget {
  const StockAdjustmentScreen({super.key});

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final dbHelper = DatabaseHelper.instance;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _refNoController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _drafts = [];

  String _adjustType = 'WASTE';
  bool _isSaving = false;
  String _viewMode = 'scan'; // scan / review

  final String _cdnUrl = "https://img.pos-foodscan.com";
  String? _brandId;

  @override
  void initState() {
    super.initState();
    _loadBrandId();
    _loadDrafts();

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refNoController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // 🌟 📥 แก้ไขจุดที่ 1: ดึง Brand ID สดใหม่ขึ้นมาจากตู้เซฟดิจิทัล ป้องกันรูปภาพหาย
  Future<void> _loadBrandId() async {
    final savedBrandId = await StorageService.getBrandId(); // ดึงจากตู้เซฟ

    if (!mounted) return;

    setState(() {
      _brandId = savedBrandId.isNotEmpty ? savedBrandId : null;
    });
  }

  Future<void> _loadDrafts() async {
    await dbHelper.ensureStockAdjustmentDraftsTable();
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'stock_adjustment_drafts',
    );

    if (!mounted) return;

    setState(() {
      _drafts = maps.map((item) => Map<String, dynamic>.from(item)).toList();
    });
  }

  void _scanBarcodeWithCamera() {
    BarcodeScannerModal.show(context, (scannedCode) {
      _searchProduct(scannedCode);
    });
  }

  Future<void> _searchProduct(String code) async {
    final keyword = code.trim();

    if (keyword.isEmpty) return;

    try {
      final db = await dbHelper.database;

      final List<Map<String, dynamic>> products = await db.query(
        'products',
        where: 'barcode = ? OR sku = ? OR name LIKE ?',
        whereArgs: [keyword, keyword, '$keyword%'],
        limit: 1,
      );

      _searchController.clear();

      if (products.isNotEmpty) {
        _showAdjustDialog(products.first);
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่พบสินค้ารหัส: $keyword'),
            backgroundColor: Colors.orange,
          ),
        );

        _searchFocusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );

      _searchController.clear();
      _searchFocusNode.requestFocus();
    }
  }

  void _showAdjustDialog(Map<String, dynamic> product) {
    final TextEditingController qtyController = TextEditingController(
      text: '1',
    );

    setState(() {
      _adjustType = 'WASTE';
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildProductImage(product, size: 92),

                  const SizedBox(height: 16),

                  Text(
                    product['name']?.toString() ?? 'ไม่มีชื่อสินค้า',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    product['barcode']?.toString() ?? '-',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 24),

                  StatefulBuilder(
                    builder: (context, setModalState) {
                      return Row(
                        children: ['WASTE', 'DAMAGED', 'CORRECTION'].map((type) {
                          final bool isSelected = _adjustType == type;

                          final String label = type == 'WASTE'
                              ? 'ของเสีย'
                              : type == 'DAMAGED'
                                  ? 'ชำรุด'
                                  : 'แก้ยอด';

                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: OutlinedButton(
                                onPressed: () {
                                  setModalState(() {
                                    _adjustType = type;
                                  });
                                  setState(() {});
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? Colors.blue.shade600
                                      : Colors.transparent,
                                  side: BorderSide(
                                    color: isSelected
                                        ? Colors.blue.shade600
                                        : Colors.grey.shade300,
                                  ),
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: 'จำนวน',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Colors.blue.shade600,
                          width: 2,
                        ),
                      ),
                    ),
                    onTap: () {
                      qtyController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: qtyController.text.length,
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  StatefulBuilder(
                    builder: (context, setModalState) {
                      return Text(
                        _adjustType == 'CORRECTION'
                            ? 'แก้ยอดจะบวกจำนวนตามที่กรอก'
                            : 'ของเสีย/ชำรุด จะตัดยอดออกจากสต็อก',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        final int qty = int.tryParse(qtyController.text) ?? 0;

                        if (qty <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('กรุณาใส่จำนวนมากกว่า 0'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        final int finalQty = (_adjustType == 'WASTE' || _adjustType == 'DAMAGED')
                            ? -qty.abs()
                            : qty.abs();

                        final navigator = Navigator.of(context);
                        await _addToDraft(product, finalQty, _adjustType);

                        if (!navigator.mounted) return;

                        navigator.pop();
                      },
                      child: const Text(
                        "ตกลง",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  Future<void> _addToDraft(
    Map<String, dynamic> product,
    int qty,
    String type,
  ) async {
    await dbHelper.ensureStockAdjustmentDraftsTable();
    final db = await dbHelper.database;
    final String productId = (product['id'] ?? product['product_id'] ?? '').toString();

    final List<Map<String, dynamic>> existing = await db.query(
      'stock_adjustment_drafts',
      where: 'product_id = ? AND type = ?',
      whereArgs: [productId, type],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final int currentQty = (existing.first['qty'] as int?) ?? 0;
      final int newQty = currentQty + qty;

      if (newQty == 0) {
        await db.delete(
          'stock_adjustment_drafts',
          where: 'product_id = ? AND type = ?',
          whereArgs: [productId, type],
        );
      } else {
        await db.update(
          'stock_adjustment_drafts',
          {'qty': newQty},
          where: 'product_id = ? AND type = ?',
          whereArgs: [productId, type],
        );
      }
    } else {
      await db.insert('stock_adjustment_drafts', {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'product_id': productId,
        'barcode': product['barcode'],
        'sku': product['sku'],
        'name': product['name'],
        'image_url': _getProductImageName(product),
        'qty': qty,
        'type': type,
      });
    }

    await _loadDrafts();

    if (!mounted) return;

    setState(() {
      _viewMode = 'review';
    });
  }

  Future<void> _removeDraftAt(int index) async {
    if (index < 0 || index >= _drafts.length) return;

    await dbHelper.ensureStockAdjustmentDraftsTable();
    final db = await dbHelper.database;
    final String draftId = (_drafts[index]['id'] ?? '').toString();

    if (draftId.isNotEmpty) {
      await db.delete(
        'stock_adjustment_drafts',
        where: 'id = ?',
        whereArgs: [draftId],
      );
      await _loadDrafts();
      return;
    }

    setState(() {
      _drafts.removeAt(index);
    });
  }

  // 🌟 📤 แก้ไขจุดที่ 2: เปลี่ยนระบบส่งคำขอขึ้นคลาวด์ Next.js ให้เช็คผ่านสิทธิ์ตู้เซฟดิจิทัลแทน SharedPreferences
  Future<void> _submitToCloud() async {
    if (_drafts.isEmpty) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final String? token = await StorageService.getToken(); // ดึงจากตู้เซฟ
      final String? savedBrandId = await StorageService.getBrandId(); // ดึงจากตู้เซฟ

      if (token == null || token.isEmpty) {
        throw "ไม่พบ Token กรุณาล็อกอินใหม่";
      }

      if (savedBrandId == null || savedBrandId.isEmpty) {
        throw "ไม่พบ Brand ID กรุณาล็อกอินใหม่";
      }

      final String refNo = _refNoController.text.trim().isNotEmpty
          ? _refNoController.text.trim()
          : "ADJ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

      final List<Map<String, dynamic>> itemsPayload = _drafts.map((item) {
        return {
          "product_id": item["product_id"] ?? item["id"],
          "qty": item["qty"],
          "type": item["type"],
        };
      }).toList();

      final Map<String, dynamic> payload = {
        "brandId": savedBrandId,
        "refNo": refNo,
        "note": "ปรับปรุงสต็อกหน้าร้าน",
        "items": itemsPayload,
      };

      final response = await http.post(
        Uri.parse(ApiService.adjustStock),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        await dbHelper.ensureStockAdjustmentDraftsTable();
        final db = await dbHelper.database;
        await db.delete('stock_adjustment_drafts');

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตยอดสต็อกเรียบร้อยแล้ว'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          _drafts = [];
          _refNoController.clear();
          _viewMode = 'scan';
        });

        _searchFocusNode.requestFocus();
      } else {
        throw result['error'] ?? 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์';
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _getProductImageName(Map<String, dynamic> item) {
    return item['image_url']?.toString() ??
        item['image']?.toString() ??
        item['image_name']?.toString() ??
        item['thumbnail']?.toString() ??
        item['photo']?.toString();
  }

  String _getImageUrl(String? imageName) {
    if (imageName == null || imageName.trim().isEmpty) return "";

    final String raw = imageName.trim();

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final String cleanName = raw.replaceAll(RegExp(r'^/+'), '');

    if (_brandId != null &&
        _brandId!.isNotEmpty &&
        !cleanName.startsWith(_brandId!)) {
      return "$_cdnUrl/$_brandId/$cleanName";
    }

    return "$_cdnUrl/$cleanName";
  }

  Widget _buildProductImage(Map<String, dynamic> item, {double size = 56}) {
    final String imageUrl = _getImageUrl(_getProductImageName(item));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.hardEdge,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.grey,
                );
              },
            )
          : const Icon(Icons.inventory_2_outlined, color: Colors.grey),
    );
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'WASTE':
        return 'ของเสีย';
      case 'DAMAGED':
        return 'ชำรุด';
      case 'CORRECTION':
        return 'แก้ยอด';
      default:
        return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'WASTE':
        return Colors.red.shade600;
      case 'DAMAGED':
        return Colors.orange.shade700;
      case 'CORRECTION':
        return Colors.green.shade600;
      default:
        return Colors.blueGrey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int totalQty = _drafts.fold<int>(
      0,
      (sum, item) => sum + ((item['qty'] as int?) ?? 0),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF475569)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ปรับปรุงสต็อก / ของเสีย',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'ADJUSTMENT & WASTE',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    title: 'เลือกสินค้า',
                    icon: Icons.qr_code_scanner_rounded,
                    isActive: _viewMode == 'scan',
                    onTap: () {
                      setState(() {
                        _viewMode = 'scan';
                      });
                      _searchFocusNode.requestFocus();
                    },
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    title: 'ตรวจสอบ',
                    icon: Icons.list_alt_rounded,
                    badgeCount: _drafts.length,
                    isActive: _viewMode == 'review',
                    onTap: () {
                      setState(() {
                        _viewMode = 'review';
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _viewMode == 'scan' ? _buildScanView() : _buildReviewView(totalQty),
      bottomNavigationBar: _viewMode == 'review' && _drafts.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submitToCloud,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'ยืนยันการปรับปรุง ($totalQty ชิ้น)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildScanView() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _searchProduct,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                  decoration: InputDecoration(
                    hintText: "สแกนบาร์โค้ด หรือพิมพ์รหัส...",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.bold,
                    ),
                    prefixIcon: Icon(Icons.search, color: Colors.blue.shade600),
                    filled: true,
                    fillColor: Colors.blue.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _scanBarcodeWithCamera,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.settings_suggest_rounded,
                      size: 48,
                      color: Colors.blue.shade600,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    "วิธีการใช้งาน",
                    style: TextStyle(
                      color: Color(0xFF1E40AF),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    "สแกนสินค้าที่ต้องการปรับปรุงยอด\nระบุจำนวน และเลือกเหตุผล",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    "ของเสีย/ชำรุด = ตัดยอดออก\nแก้ยอด = บวกยอดเข้า",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewView(int totalQty) {
    if (_drafts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              "ยังไม่มีรายการที่เลือก",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¼นึกรายการ',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_drafts.length} SKU',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),

              Container(width: 1, height: 40, color: Colors.white24),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'ยอดรวมปรับปรุง',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$totalQty ชิ้น',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _refNoController,
            decoration: InputDecoration(
              labelText: 'อ้างอิง / หมายเหตุ',
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
              hintText: 'เลขเอกสาร, หมายเหตุ...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'รายการสินค้า',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
          ),
        ),

        const SizedBox(height: 12),

        for (int index = 0; index < _drafts.length; index++)
          _buildDraftItemCard(index),
      ],
    );
  }

  Widget _buildDraftItemCard(int index) {
    final Map<String, dynamic> item = _drafts[index];
    final int qty = (item['qty'] as int?) ?? 0;
    final String type = item['type']?.toString() ?? '';
    final bool isNegative = qty < 0;
    final Color typeColor = _getTypeColor(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _buildProductImage(item, size: 54),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 4),

                Text(
                  item['barcode']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getTypeLabel(type),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          Text(
            "${qty > 0 ? '+' : ''}$qty",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isNegative ? Colors.red.shade600 : Colors.green.shade600,
            ),
          ),

          const SizedBox(width: 8),

          IconButton(
            onPressed: () => _removeDraftAt(index),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFEF4444),
            ),
            style: IconButton.styleFrom(backgroundColor: Colors.red.shade50),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;

  const _TabButton({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8),
            ),

            const SizedBox(width: 6),

            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isActive
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF64748B),
              ),
            ),

            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: isActive
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}