// lib/screens/kitchen_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../utils/printer_service.dart';

class KitchenScreen extends StatefulWidget {
  final String brandId;

  const KitchenScreen({super.key, required this.brandId});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  static const Color _bg = Color(0xFFFAF9F6); // สีขาวไข่ (Off-white)
  static const Color _surface = Colors.white;
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF64748B);
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _pending = Color(0xFF15803D); // สีเขียวหลักสำหรับสถานะ "รอรับ"
  static const Color _preparing = Color(0xFF059669); // สีเขียวอีกเฉดสำหรับสถานะ "กำลังทำ"

  List<dynamic> _pendingOrders = [];
  List<dynamic> _preparingOrders = [];
  bool _isLoading = true;
  String _activeTab = 'pending';

  @override
  void initState() {
    super.initState();
    _fetchKitchenOrders();
    _setupFCMListener();
  }

  void _setupFCMListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'NEW_ORDER' ||
          message.data['type'] == 'SILENT_UPDATE') {
        print("[Kitchen App] FCM received. Refreshing kitchen orders...");
        _fetchKitchenOrders();
      }
    });
  }

  // โหลดออเดอร์เข้าห้องครัว
  Future<void> _fetchKitchenOrders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = await StorageService.getToken();

      final uri = Uri.parse(ApiService.kitchenOrders);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final allOrders = result['data'] as List<dynamic>;
          if (mounted) {
            setState(() {
              _pendingOrders = allOrders
                  .where((o) => o['status'] == 'pending')
                  .toList();
              _preparingOrders = allOrders
                  .where((o) => o['status'] == 'preparing')
                  .toList();
              _isLoading = false;
            });
          }
        } else {
          throw Exception(result['error'] ?? "เกิดข้อผิดพลาดจาก API");
        }
      } else {
        throw Exception("API Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Fetch Kitchen Orders Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // อัปเดตสถานะบิล (เช่น จาก pending -> preparing -> done)
  Future<void> _updateOrderStatus(String orderId, String nextStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = await StorageService.getToken();

      final response = await http.post(
        Uri.parse(ApiService.kitchenUpdateStatus),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'orderId': orderId, 'status': nextStatus}),
      );
      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        _fetchKitchenOrders();
      } else {
        print("Update Status API Error: ${result['error']}");
      }
    } catch (e) {
      print("Update Status Error: $e");
    }
  }

  // ฟังก์ชันยกเลิกทั้งบิล (SaaS)
  Future<void> _cancelOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'ยกเลิกออเดอร์',
          style: TextStyle(fontFamily: 'Kanit'),
        ),
        content: const Text('ต้องการยกเลิกออเดอร์นี้ทั้งหมดใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ปิด'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ยืนยันยกเลิก',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = await StorageService.getToken();

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/kitchen/cancel-order'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'orderId': orderId}),
      );

      if (jsonDecode(response.body)['success'] == true) {
        _fetchKitchenOrders();
      }
    } catch (e) {
      print("Cancel Order Error: $e");
    }
  }

  // ฟังก์ชันสลับสถานะจานอาหารย่อย (ยกเลิก / คืนค่า) (SaaS)
  Future<void> _toggleItemStatus(String itemId, String currentStatus) async {
    final nextStatus = currentStatus == 'cancelled' ? 'active' : 'cancelled';
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = await StorageService.getToken();

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/kitchen/update-item-status'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'itemId': itemId, 'status': nextStatus}),
      );

      if (jsonDecode(response.body)['success'] == true) {
        _fetchKitchenOrders();
      }
    } catch (e) {
      print("Toggle Item Status Error: $e");
    }
  }

  // 🖨️ ฟังก์ชันสั่งปริ้นใบออเดอร์เข้าครัว
  Future<void> _printKitchenOrder(Map<String, dynamic> order) async {
    final items = List<dynamic>.from(order['order_items'] ?? []);

    // จัดรูปแบบข้อมูลสำหรับใบครัว (ไม่เน้นราคา เน้นรายการอาหารและหมายเหตุ)
    final kitchenReceiptData = {
      'is_kitchen_ticket': true, // แฟล็กบอกให้ PrinterService รู้ว่าเป็นบิลครัว
      'table_label': order['table_label'] ?? 'Walk-in',
      'order_id': order['id'],
      'items': items,
      'created_at': order['created_at'],
      'cashier_name': 'Kitchen System',
    };

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กำลังส่งข้อมูลไปเครื่องปริ้นห้องครัว...')),
    );

    try {
      // เรียกใช้ PrinterService (ใช้ฟังก์ชันเดียวกับใบเสร็จ แต่ส่งแฟล็ก is_kitchen_ticket ไป)
      bool success = await PrinterService.printReceipt(
        kitchenReceiptData,
        widget.brandId,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'สั่งปริ้นใบออเดอร์เข้าครัวสำเร็จ!',
                style: TextStyle(color: Colors.green),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ปริ้นไม่สำเร็จ กรุณาตรวจสอบเครื่องปริ้นครัว',
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print("❌ [Kitchen Print Error]: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayOrders = _activeTab == 'pending'
        ? _pendingOrders
        : _preparingOrders;

    return Scaffold(
      backgroundColor: _bg,
      drawer: const AppSidebar(activeMenu: 'kitchen'),
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 72,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
            child: GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.menu_rounded, color: _muted, size: 24),
              ),
            ),
          ),
        ),
        title: const Text(
          'ระบบจัดการครัว',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w900,
            fontFamily: 'Kanit',
            fontSize: 20,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: _surface,
                foregroundColor: _muted,
                side: const BorderSide(color: _line),
              ),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchKitchenOrders,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                _buildTabButton(
                  'pending',
                  'รอรับ',
                  _pendingOrders.length,
                  _pending,
                ),
                _buildTabButton(
                  'preparing',
                  'กำลังทำ',
                  _preparingOrders.length,
                  _preparing,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const SuparPosLoading(fullScreen: false)
                : displayOrders.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _line),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, color: Color(0xFFCBD5E1), size: 32),
                          SizedBox(height: 8),
                          Text(
                            'ไม่มีออเดอร์',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Kanit',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: displayOrders.length,
                    itemBuilder: (context, index) {
                      final order = displayOrders[index];
                      return _buildOrderCard(order);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabId, String title, int count, Color activeColor) {
    final isActive = _activeTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tabId),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Kanit',
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white.withOpacity(0.25) : _line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: isActive ? Colors.white : _muted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final items = order['order_items'] as List<dynamic>? ?? [];
    final isPending = order['status'] == 'pending';
    final accent = isPending ? _pending : _preparing;
    final timeStr = _formatTime(order['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order['table_label']?.toString().toUpperCase() ?? '-',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildSmallIconBtn(Icons.print_outlined, () => _printKitchenOrder(order)),
                    const SizedBox(width: 6),
                    _buildSmallIconBtn(Icons.delete_outline, () => _cancelOrder(order['id'])),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          // Items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: items.map((item) {
                bool isCancelled = item['status'] == 'cancelled';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${item['quantity']}x',
                          style: TextStyle(
                            color: isCancelled ? const Color(0xFFCBD5E1) : accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['product_name'] ?? 'ไม่ระบุชื่อ',
                              style: TextStyle(
                                color: isCancelled ? const Color(0xFF94A3B8) : _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                decoration: isCancelled ? TextDecoration.lineThrough : null,
                                height: 1.2,
                              ),
                            ),
                            if (item['variant'] != 'normal' && item['variant'] != null)
                              Text(
                                '${item['variant']}',
                                style: TextStyle(
                                  color: isCancelled ? const Color(0xFFCBD5E1) : _muted,
                                  fontSize: 11,
                                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                                  height: 1.2,
                                ),
                              ),
                            if (item['note'] != null && item['note'].toString().trim().isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isCancelled ? const Color(0xFFF8FAFC) : const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${item['note']}',
                                  style: TextStyle(
                                    color: isCancelled ? const Color(0xFFCBD5E1) : const Color(0xFFEA580C),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => _toggleItemStatus(item['id'], item['status']),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            isCancelled ? Icons.reply_rounded : Icons.close_rounded,
                            color: isCancelled ? _preparing : const Color(0xFFCBD5E1),
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // Action Button
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: SizedBox(
              height: 36,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPending ? _ink : _preparing,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final nextStatus = isPending ? 'preparing' : 'done';
                  _updateOrderStatus(order['id'], nextStatus);
                },
                child: Text(
                  isPending ? 'รับออเดอร์' : 'ทำเสร็จแล้ว',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallIconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: _muted),
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} น.';
    } catch (e) {
      return '';
    }
  }
}
