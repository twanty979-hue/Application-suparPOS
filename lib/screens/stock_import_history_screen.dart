// lib/screens/stock_import_history_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../widgets/suparpos_loading.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 1. นำเข้าตู้เซฟดิจิทัลหุ้มเกราะ

class StockImportHistoryScreen extends StatefulWidget {
  const StockImportHistoryScreen({super.key});

  @override
  State<StockImportHistoryScreen> createState() =>
      _StockImportHistoryScreenState();
}

class _StockImportHistoryScreenState extends State<StockImportHistoryScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _transactions = [];

  final String _cdnUrl = "https://img.pos-foodscan.com";
  String? _brandId;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  // 📥 GET: สั่งดึงประวัติการทำรายการสต็อกทั้งหมด
  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 🌟 2. แก้ไขจุดนี้: เปลี่ยนมาดึง Token และ Brand ID สดๆ จากตู้เซฟดิจิทัลอัจฉริยะ
      _brandId = await StorageService.getBrandId();
      final token = await StorageService.getToken();

      if (token == null || token.isEmpty)
        throw "ไม่พบเซสชัน กรุณาเข้าสู่ระบบใหม่";

      final response = await http.get(
        Uri.parse(ApiService.stockHistory),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer $token', // 🚀 ยื่นบัตร VIP ผ่านด่านเข้าสู่ประตูหลังบ้าน
        },
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        setState(() {
          _transactions = result['data'] ?? [];
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

  String _getImageUrl(String? imageName) {
    if (imageName == null || imageName.isEmpty) return "";
    if (imageName.startsWith('http')) return imageName;
    final cleanName = imageName.replaceAll(RegExp(r'^/+'), '');
    if (_brandId != null &&
        _brandId!.isNotEmpty &&
        !cleanName.startsWith(_brandId!)) {
      return "$_cdnUrl/$_brandId/$cleanName";
    }
    return "$_cdnUrl/$cleanName";
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
            Text(
              'ประวัติการทำรายการ',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'TRANSACTION HISTORY',
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
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SuparPosLoading(fullScreen: false);
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh),
              label: const Text("ลองใหม่อีกครั้ง"),
            ),
          ],
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Icon(Icons.history, size: 48, color: Colors.grey[300]),
            ),
            const SizedBox(height: 16),
            const Text(
              "ยังไม่มีประวัติการทำรายการ",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        return _TransactionCard(tx: tx, getImageUrl: _getImageUrl);
      },
    );
  }
}

class _TransactionCard extends StatefulWidget {
  final dynamic tx;
  final String Function(String?) getImageUrl;

  const _TransactionCard({required this.tx, required this.getImageUrl});

  @override
  State<_TransactionCard> createState() => _TransactionCardState();
}

class _TransactionCardState extends State<_TransactionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final DateTime date = DateTime.parse(widget.tx['created_at']).toLocal();
    final String dayLabel = DateFormat('dd').format(date);
    final String monthLabel = DateFormat(
      'MMM',
      'th',
    ).format(date).toUpperCase();
    final String timeLabel = DateFormat('HH:mm').format(date);

    final List logs = widget.tx['stock_logs'] ?? [];
    int totalQty = 0;
    for (var log in logs) {
      totalQty += (log['change_amount'] as num).toInt();
    }
    final bool isPositive = totalQty >= 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isExpanded ? Colors.blue[300]! : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          if (_isExpanded)
            BoxShadow(
              color: Colors.blue.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          else
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (expanded) =>
              setState(() => _isExpanded = expanded),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          iconColor: Colors.grey[400],
          collapsedIconColor: Colors.grey[400],
          title: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _isExpanded ? Colors.blue[600] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      monthLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _isExpanded ? Colors.white : Colors.grey[500],
                      ),
                    ),
                    Text(
                      dayLabel,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _isExpanded ? Colors.white : Colors.grey[800],
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPositive
                                ? Colors.green[50]
                                : Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isPositive ? 'STOCK IN' : 'STOCK OUT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: isPositive
                                  ? Colors.green[700]
                                  : Colors.red[700],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.tx['note']?.toString().isNotEmpty == true
                          ? widget.tx['note']
                          : 'ทำรายการสต็อก',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Ref: ${widget.tx['ref_no'] ?? '-'}",
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "ยอดรวม",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[400],
                    ),
                  ),
                  Text(
                    "${isPositive ? '+' : ''}$totalQty ชิ้น",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: isPositive ? Colors.green[600] : Colors.red[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16).copyWith(top: 0),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Column(
                children: logs.map<Widget>((log) {
                  final int changeAmt = (log['change_amount'] as num).toInt();
                  final bool isLogPositive = changeAmt >= 0;
                  final product = log['product_master'] ?? {};
                  final imgUrl = widget.getImageUrl(product['image_url']);

                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.01),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: imgUrl.isNotEmpty
                              ? Image.network(
                                  imgUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                )
                              : const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['name'] ?? 'สินค้าถูกลบ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                product['barcode'] ?? '-',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isLogPositive
                                ? Colors.green[50]
                                : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isLogPositive
                                  ? Colors.green[100]!
                                  : Colors.red[100]!,
                            ),
                          ),
                          child: Text(
                            "${isLogPositive ? '+' : ''}$changeAmt",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: isLogPositive
                                  ? Colors.green[600]
                                  : Colors.red[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
