// lib/screens/inventory_overview_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 1. นำเข้าตู้เซฟดิจิทัลหุ้มเกราะ

class InventoryOverviewScreen extends StatefulWidget {
  const InventoryOverviewScreen({super.key});

  @override
  State<InventoryOverviewScreen> createState() => _InventoryOverviewScreenState();
}

class _InventoryOverviewScreenState extends State<InventoryOverviewScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _data = {
    'stats': {
      'totalSKUs': 0, 'totalItems': 0, 'lowStockCount': 0,
      'outOfStockCount': 0, 'totalValue': 0, 'lostValue': 0, 'lostItemsCount': 0
    },
    'recentTransactions': []
  };

  @override
  void initState() {
    super.initState();
    _fetchOverview();
  }

  // 📥 GET: ดึงข้อมูลภาพรวมคลังสินค้าผ่านสิทธิ์ตู้เซฟดิจิทัล
  Future<void> _fetchOverview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 🌟 2. แก้ไขจุดนี้: ดึง Token สดใหม่จากตู้เซฟดิจิทัล ปลอดภัยทะลุกำแพง RLS
      final token = await StorageService.getToken();

      if (token == null || token.isEmpty) throw "ไม่พบเซสชัน กรุณาเข้าสู่ระบบใหม่";

      final response = await http.get(
        Uri.parse(ApiService.stockOverview), 
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', // 🚀 ยื่นแสดงบัตรผ่านประตู
        },
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        setState(() {
          _data = result;
        });
      } else {
        throw result['error'] ?? "เกิดข้อผิดพลาดในการโหลดข้อมูล";
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(num amount) {
    return NumberFormat.currency(locale: 'th_TH', symbol: '฿', decimalDigits: 0).format(amount);
  }

  String _formatTime(String isoString) {
    final date = DateTime.parse(isoString).toLocal();
    return "${DateFormat('d MMM', 'th').format(date)} ${DateFormat('HH:mm').format(date)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF475569)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ภาพรวมคลังสินค้า', style: TextStyle(color: Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.w900)),
            Text('DASHBOARD ANALYTICS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _fetchOverview,
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, color: Colors.blue),
            style: IconButton.styleFrom(backgroundColor: Colors.blue.shade50),
          ),
          const SizedBox(width: 16),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchOverview,
              icon: const Icon(Icons.refresh),
              label: const Text("ลองใหม่อีกครั้ง"),
            )
          ],
        ),
      );
    }

    final stats = _data['stats'];
    final num totalStatus = (stats['totalSKUs'] == 0) ? 1 : stats['totalSKUs'];
    final double outPercent = (stats['outOfStockCount'] / totalStatus) * 100;
    final double lowPercent = (stats['lowStockCount'] / totalStatus) * 100;
    final double goodPercent = 100 - outPercent - lowPercent;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🌟 1. การ์ดแสดงมูลค่าเงิน
          Wrap(
            spacing: 16, 
            runSpacing: 16, 
            children: [
              SizedBox(
                width: (MediaQuery.of(context).size.width - 48) / 2, 
                child: _buildGradientCard(
                  title: 'สินค้าพร้อมขาย',
                  amount: _formatCurrency(stats['totalValue'] ?? 0),
                  subtitle: 'จาก ${stats['totalItems']} ชิ้น (${stats['totalSKUs']} SKU)',
                  colors: [const Color(0xFF10B981), const Color(0xFF0D9488)],
                  icon: Icons.inventory_2_outlined,
                  isLoading: _isLoading,
                ),
              ),
              SizedBox(
                width: (MediaQuery.of(context).size.width - 48) / 2, 
                child: _buildGradientCard(
                  title: 'มูลค่าสูญหาย/ชำรุด',
                  amount: _formatCurrency(stats['lostValue'] ?? 0),
                  subtitle: 'ตัดทิ้ง ${stats['lostItemsCount']} ชิ้น',
                  colors: [const Color(0xFFF43F5E), const Color(0xFFE11D48)],
                  icon: Icons.trending_down_rounded,
                  isLoading: _isLoading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 🌟 2. แจ้งเตือนสถานะสินค้า
          Row(
            children: [
              Expanded(
                child: _buildAlertCard(
                  title: 'สินค้าใกล้หมด',
                  count: stats['lowStockCount'].toString(),
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  isLoading: _isLoading,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildAlertCard(
                  title: 'หมดสต็อก',
                  count: stats['outOfStockCount'].toString(),
                  icon: Icons.cancel_outlined,
                  color: Colors.red,
                  isLoading: _isLoading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 🌟 3. Health Bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('สุขภาพคลังสินค้า (Stock Health)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 16),
                if (_isLoading)
                  Container(height: 20, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)))
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 20,
                      child: Row(
                        children: [
                          if (goodPercent > 0) Expanded(flex: goodPercent.toInt(), child: Container(color: Colors.green.shade500)),
                          if (lowPercent > 0) Expanded(flex: lowPercent.toInt(), child: Container(color: Colors.orange.shade400)),
                          if (outPercent > 0) Expanded(flex: outPercent.toInt(), child: Container(color: Colors.red.shade500)),
                          if (goodPercent == 0 && lowPercent == 0 && outPercent == 0) Expanded(child: Container(color: Colors.grey.shade200)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _buildHealthLegend(Colors.green.shade500, 'ปกติ', goodPercent),
                      const SizedBox(width: 16),
                      _buildHealthLegend(Colors.orange.shade400, 'ใกล้หมด', lowPercent),
                      const SizedBox(width: 16),
                      _buildHealthLegend(Colors.red.shade500, 'หมด', outPercent),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 🌟 4. ความเคลื่อนไหวล่าสุด
          const Row(
            children: [
              Icon(Icons.show_chart_rounded, color: Colors.blue),
              SizedBox(width: 8),
              Text('รายการรับเข้าล่าสุด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                : (_data['recentTransactions'] as List).isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text("ยังไม่มีความเคลื่อนไหว", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: (_data['recentTransactions'] as List).length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final tx = _data['recentTransactions'][index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                              child: Icon(Icons.download_rounded, color: Colors.green.shade600, size: 20),
                            ),
                            title: Text(tx['ref_no'] ?? 'ไม่มีเลขที่อ้างอิง', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                            subtitle: Text(tx['note'] ?? 'รับสินค้าเข้าสต็อก', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_formatTime(tx['created_at']), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('IN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientCard({required String title, required String amount, required String subtitle, required List<Color> colors, required IconData icon, required bool isLoading}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: colors[0].withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.8), size: 16),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            Container(height: 32, width: 100, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)))
          else
            Text(amount, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildAlertCard({required String title, required String count, required IconData icon, required MaterialColor color, required bool isLoading}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.shade50, shape: BoxShape.circle),
            child: Icon(icon, color: color.shade500, size: 20),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          if (isLoading)
            Container(height: 28, width: 40, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)))
          else
            Text(count, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildHealthLegend(Color color, String label, double percent) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text("$label (${percent.toStringAsFixed(0)}%)", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }
}