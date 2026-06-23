// lib/screens/receive_stock_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 1. นำเข้าตู้เซฟดิจิทัลเข้ารหัสหุ้มเกราะ
import '../widgets/modals/barcode_scanner_modal.dart'; 

class ReceiveStockScreen extends StatefulWidget {
  const ReceiveStockScreen({super.key});

  @override
  State<ReceiveStockScreen> createState() => _ReceiveStockScreenState();
}

class _ReceiveStockScreenState extends State<ReceiveStockScreen> {
  final dbHelper = DatabaseHelper.instance;
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _refNoController = TextEditingController();
  
  bool _isLoading = false;
  String _viewMode = 'scan'; // 'scan' หรือ 'review'
  List<Map<String, dynamic>> _draftItems = [];

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('stock_drafts');
    setState(() {
      _draftItems = maps;
    });
  }

  Future<void> _searchProduct(String code) async {
    if (code.trim().isEmpty) return;

    final db = await dbHelper.database;
    final List<Map<String, dynamic>> products = await db.query(
      'products',
      where: 'barcode = ? OR sku = ?',
      whereArgs: [code.trim(), code.trim()],
      limit: 1,
    );

    if (products.isNotEmpty) {
      final product = products.first;
      _barcodeController.clear();
      _showQtyDialog(product);
    } else {
      _barcodeController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่พบสินค้า รหัส: $code'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scanBarcodeWithCamera() {
    BarcodeScannerModal.show(context, (scannedCode) {
      _searchProduct(scannedCode);
    });
  }

  void _showQtyDialog(Map<String, dynamic> product) {
    final TextEditingController qtyController = TextEditingController(text: "1");

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(product['name'] ?? 'ไม่มีชื่อสินค้า', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('บาร์โค้ด: ${product['barcode'] ?? '-'}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.blue.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                autofocus: true,
                onTap: () => qtyController.selection = TextSelection(baseOffset: 0, extentOffset: qtyController.text.length),
              ),
              const SizedBox(height: 8),
              const Text('ใส่ - (ลบ) ด้านหน้าเพื่อลดยอด', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () async {
                final int qty = int.tryParse(qtyController.text) ?? 0;
                if (qty != 0) {
                  await _saveToDraft(product, qty);
                }
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('ตกลง', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveToDraft(Map<String, dynamic> product, int qty) async {
    final db = await dbHelper.database;
    final String productId = product['id'].toString();

    final List<Map<String, dynamic>> existing = await db.query(
      'stock_drafts',
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    if (existing.isNotEmpty) {
      final int currentQty = existing.first['qty'] as int;
      final int newQty = currentQty + qty;

      if (newQty <= 0) {
        await db.delete('stock_drafts', where: 'product_id = ?', whereArgs: [productId]);
      } else {
        await db.update(
          'stock_drafts',
          {'qty': newQty},
          where: 'product_id = ?',
          whereArgs: [productId],
        );
      }
    } else if (qty > 0) {
      await db.insert('stock_drafts', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'product_id': productId,
        'barcode': product['barcode'],
        'name': product['name'],
        'qty': qty,
      });
    }
    
    _loadDrafts();
  }

  Future<void> _removeDraft(String id) async {
    final db = await dbHelper.database;
    await db.delete('stock_drafts', where: 'id = ?', whereArgs: [id]);
    _loadDrafts();
  }

  // 🚀 ยิงกวาดล้าง SharedPreferences ออก และเชื่อมสัญญากับตู้เซฟ StorageService
  Future<void> _submitToCloud() async {
    if (_draftItems.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // 🌟 แก้ไขจุดนี้: เรียกดึงสิทธิ์และรหัสร้านค้าสดใหม่ผ่านตู้เซฟดิจิทัล ปลอดภัย 100%
      final String brandId = await StorageService.getBrandId();
      final String? accessToken = await StorageService.getToken();

      if (brandId.isEmpty || accessToken == null) {
        throw "ไม่พบข้อมูลยืนยันตัวตน กรุณาล็อกอินใหม่";
      }

      final List<Map<String, dynamic>> itemsPayload = _draftItems.map((e) => {
        "product_id": e["product_id"],
        "qty": e["qty"]
      }).toList();

      final payload = {
        "brand_id": brandId,
        "ref_no": _refNoController.text.trim(),
        "note": "รับเข้าผ่านแอป",
        "items": itemsPayload
      };

      final response = await http.post(
        Uri.parse("${ApiService.baseUrl}/stock/receive"), 
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        final db = await dbHelper.database;
        await db.delete('stock_drafts');
        _refNoController.clear();
        await _loadDrafts();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('อัปเดตสต็อกเรียบร้อยแล้ว! 🎉'), backgroundColor: Colors.green),
          );
          setState(() => _viewMode = 'scan');
        }
      } else {
        throw result['error'] ?? "เกิดข้อผิดพลาดจากเซิร์ฟเวอร์";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalQty = _draftItems.fold(0, (sum, item) => sum + (item['qty'] as int));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF475569)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('รับสินค้าเข้าสต็อก', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text('STOCK INBOUND RECEIVING', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    title: 'สแกน',
                    icon: Icons.qr_code_scanner,
                    isActive: _viewMode == 'scan',
                    onTap: () => setState(() => _viewMode = 'scan'),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    title: 'ตรวจสอบ',
                    badgeCount: _draftItems.length,
                    icon: Icons.list_alt_rounded,
                    isActive: _viewMode == 'review',
                    onTap: () => setState(() => _viewMode = 'review'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _viewMode == 'scan' ? _buildScanView() : _buildReviewView(totalQty),
      bottomNavigationBar: _viewMode == 'review' && _draftItems.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitToCloud,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('ยืนยันรับเข้าสต็อก ($totalQty ชิ้น)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildScanView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'ยิงบาร์โค้ด',
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.w900, 
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ใช้ปืนสแกนยิงหรือพิมพ์รหัสสินค้า',
              style: TextStyle(
                color: Color(0xFF64748B), 
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 18.0, right: 10.0),
                    child: Icon(Icons.view_week_rounded, color: Color(0xFFCBD5E1), size: 22),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _barcodeController,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w700, 
                        color: Color(0xFF334155),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'รหัสสินค้า / SKU...',
                        hintStyle: TextStyle(
                          color: Color(0xFF94A3B8), 
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: _searchProduct,
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _scanBarcodeWithCamera, 
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.camera_alt_outlined, 
                            color: Colors.white, 
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewView(int totalQty) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('จำนวนรายการ', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('${_draftItems.length} SKU', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('ชิ้นรวมทั้งหมด', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('$totalQty ชิ้น', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
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
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              hintText: 'เลขที่เอกสาร, PO...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('รายการสินค้า', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        const SizedBox(height: 12),
        if (_draftItems.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('ไม่มีรายการรับเข้า', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
        for (var i = 0; i < _draftItems.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                  child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_draftItems[i]['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF334155))),
                      const SizedBox(height: 2),
                      Text(_draftItems[i]['barcode'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                  child: Text('+${_draftItems[i]['qty']}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                  onPressed: () => _removeDraft(_draftItems[i]['id']),
                ),
              ],
            ),
          ),
      ],
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
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isActive ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isActive ? const Color(0xFF2563EB) : const Color(0xFF64748B))),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: isActive ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}