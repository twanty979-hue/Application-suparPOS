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
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _surface = Colors.white;
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF64748B);
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _pending = Color(0xFFF97316);
  static const Color _preparing = Color(0xFF2563EB);

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
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _line),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            color: Color(0xFFCBD5E1),
                            size: 44,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'ไม่มีออเดอร์ในสถานะนี้',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Kanit',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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

  Widget _buildTabButton(
    String tabId,
    String title,
    int count,
    Color activeColor,
  ) {
    final isActive = _activeTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tabId),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tabId == 'pending'
                    ? Icons.receipt_long_rounded
                    : Icons.restaurant_rounded,
                size: 18,
                color: isActive ? Colors.white : _muted,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : _muted,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Kanit',
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withOpacity(0.22)
                        : activeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: const Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        order['table_label']?.toString().toUpperCase() ?? '-',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'โต๊ะ',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Kanit',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isPending ? 'รอรับออเดอร์' : 'กำลังทำ',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Kanit',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    InkWell(
                      // 🚀 แก้ไข onTap ตรงนี้ครับนาย!
                      onTap: () => _printKitchenOrder(order),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.print_outlined,
                          color: _muted,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _cancelOrder(order['id']),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: _muted,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: items.map((item) {
                bool isCancelled = item['status'] == 'cancelled';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isCancelled
                              ? const Color(0xFFF8FAFC)
                              : accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCancelled
                                ? const Color(0xFFE2E8F0)
                                : accent.withOpacity(0.16),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${item['quantity']}x',
                          style: TextStyle(
                            color: isCancelled
                                ? const Color(0xFFCBD5E1)
                                : accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
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
                                    item['product_name'] ?? 'ไม่ระบุชื่อ',
                                    style: TextStyle(
                                      color: isCancelled
                                          ? const Color(0xFF94A3B8)
                                          : _ink,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      decoration: isCancelled
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                                if (isCancelled)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'ยกเลิก',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Kanit',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (item['variant'] != 'normal' &&
                                item['variant'] != null)
                              Text(
                                'ตัวเลือก: ${item['variant']}',
                                style: TextStyle(
                                  color: isCancelled
                                      ? const Color(0xFFCBD5E1)
                                      : _muted,
                                  fontSize: 13,
                                  decoration: isCancelled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            if (item['note'] != null &&
                                item['note'].toString().trim().isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isCancelled
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isCancelled
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFFFED7AA),
                                  ),
                                ),
                                child: Text(
                                  'หมายเหตุ: ${item['note']}',
                                  style: TextStyle(
                                    color: isCancelled
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFFEA580C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () =>
                            _toggleItemStatus(item['id'], item['status']),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isCancelled
                                ? const Color(0xFFF8FAFC)
                                : Colors.white,
                            border: Border.all(
                              color: isCancelled ? Colors.transparent : _line,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCancelled
                                ? Icons.reply_rounded
                                : Icons.delete_outline,
                            color: isCancelled ? _preparing : _muted,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPending ? _ink : _preparing,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                final nextStatus = isPending ? 'preparing' : 'done';
                _updateOrderStatus(order['id'], nextStatus);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isPending ? 'รับออเดอร์' : 'ทำเสร็จแล้ว',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
