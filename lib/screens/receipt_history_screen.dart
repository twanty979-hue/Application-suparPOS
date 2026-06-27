// lib/screens/receipt_history_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/printer_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../api_service.dart';

class ReceiptHistoryScreen extends StatefulWidget {
  const ReceiptHistoryScreen({super.key});

  @override
  State<ReceiptHistoryScreen> createState() => _ReceiptHistoryScreenState();
}

class _ReceiptHistoryScreenState extends State<ReceiptHistoryScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<dynamic> _receipts = [];
  bool _isLoading = true;
  bool _isLoadMoreLoading = false;
  String _errorMessage = '';
  String _effectivePlan = 'free';

  // --- States ระบบฟิลเตอร์และเวลา ---
  String _viewMode = 'custom'; // เปิดครั้งแรกเป็นช่วง 30 วันล่าสุด
  DateTime _currentDate = DateTime.now();
  DateTimeRange? _customDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 29)),
    end: DateTime.now(),
  );

  String _statusFilter = 'all';
  String _searchQuery = '';

  int _page = 1;
  bool _hasMore = false;
  String? _accessToken;

  @override
  void initState() {
    super.initState();
    _loadSessionAndFetch(isLoadMore: false);
  }

  Future<void> _loadSessionAndFetch({bool isLoadMore = false}) async {
    try {
      if (!isLoadMore) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
          _page = 1;
        });
      } else {
        setState(() => _isLoadMoreLoading = true);
      }

      final prefs = await SharedPreferences.getInstance();
      _accessToken = await StorageService.getToken();

      if (_accessToken != null && _accessToken!.isNotEmpty) {
        await _fetchReceiptsData(isLoadMore: isLoadMore);
      } else {
        setState(() {
          _errorMessage = 'ไม่พบเซสชันการยืนยันตัวตน กรุณาล็อกอินใหม่อีกครั้ง';
          _isLoading = false;
          _isLoadMoreLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดภายในเครื่อง: $e';
        _isLoading = false;
        _isLoadMoreLoading = false;
      });
    }
  }

  // 🗓️ คำนวณช่วงวันที่
  Map<String, String> _getDateRange() {
    DateTime start, end;
    if (_viewMode == 'day') {
      start = DateTime(
        _currentDate.year,
        _currentDate.month,
        _currentDate.day,
        0,
        0,
        0,
        0,
      );
      end = DateTime(
        _currentDate.year,
        _currentDate.month,
        _currentDate.day,
        23,
        59,
        59,
        999,
      );
    } else if (_viewMode == 'month') {
      start = DateTime(_currentDate.year, _currentDate.month, 1, 0, 0, 0, 0);
      end = DateTime(
        _currentDate.year,
        _currentDate.month + 1,
        0,
        23,
        59,
        59,
        999,
      );
    } else if (_viewMode == 'year') {
      start = DateTime(_currentDate.year, 1, 1, 0, 0, 0, 0);
      end = DateTime(_currentDate.year, 12, 31, 23, 59, 59, 999);
    } else {
      start = _customDateRange?.start ?? DateTime.now();
      start = DateTime(start.year, start.month, start.day, 0, 0, 0, 0);
      end = _customDateRange?.end ?? DateTime.now();
      end = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    }
    return {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    };
  }

  Future<void> _fetchReceiptsData({required bool isLoadMore}) async {
    try {
      final range = _getDateRange();
      final int targetPage = isLoadMore ? _page + 1 : 1;

      final String baseUrl = ApiService.baseUrl;
      final String fullUrl =
          "$baseUrl/receipts?start_date=${range['start']}&end_date=${range['end']}&page=$targetPage";

      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['success'] == true) {
          final List<dynamic> newFetched = resData['data'] ?? [];
          setState(() {
            if (isLoadMore) {
              _receipts.addAll(newFetched);
            } else {
              _receipts = newFetched;
            }
            _page = targetPage;
            _hasMore = resData['hasMore'] ?? false;
            _effectivePlan = resData['effectivePlan'] ?? 'free';
            _isLoading = false;
            _isLoadMoreLoading = false;
          });
        } else {
          throw resData['error'] ?? 'เซิร์ฟเวอร์ปฏิเสธการตอบรับข้อมูล';
        }
      } else {
        throw 'รหัสข้อผิดพลาดสถานะ: ${response.statusCode}';
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'ดึงข้อมูลไม่สำเร็จ: $e';
        _isLoading = false;
        _isLoadMoreLoading = false;
      });
    }
  }

  void _shiftDate(int amount) {
    if (_viewMode == 'custom') return;
    setState(() {
      if (_viewMode == 'day') {
        _currentDate = _currentDate.add(Duration(days: amount));
      } else if (_viewMode == 'month') {
        _currentDate = DateTime(
          _currentDate.year,
          _currentDate.month + amount,
          _currentDate.day,
        );
      } else if (_viewMode == 'year') {
        _currentDate = DateTime(
          _currentDate.year + amount,
          _currentDate.month,
          _currentDate.day,
        );
      }
    });
    _loadSessionAndFetch(isLoadMore: false);
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final isFreePlan = _effectivePlan == 'free';
    final firstAllowedDate = isFreePlan
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 29))
        : DateTime(2020);
    final currentRange =
        _customDateRange ??
        DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now);
    final initialEnd = currentRange.end.isBefore(firstAllowedDate)
        ? now
        : (currentRange.end.isAfter(now) ? now : currentRange.end);
    final initialRange = DateTimeRange(
      start: currentRange.start.isBefore(firstAllowedDate)
          ? firstAllowedDate
          : currentRange.start,
      end: initialEnd,
    );

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstAllowedDate,
      lastDate: now,
      initialDateRange: initialRange,
      helpText: isFreePlan
          ? 'เลือกช่วงเวลา (Free ดูย้อนหลังได้ 30 วัน)'
          : 'เลือกช่วงเวลาประวัติการขาย',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F172A),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _viewMode = 'custom';
        _customDateRange = picked;
      });
      _loadSessionAndFetch(isLoadMore: false);
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'th_TH',
      symbol: '฿',
      decimalDigits: 2,
    ).format(amount);
  }

  dynamic _mapValue(dynamic source, String key) {
    return source is Map ? source[key] : null;
  }

  String _formatDateDisplay() {
    const thMonths = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final yearTh = _currentDate.year + 543;
    if (_viewMode == 'day') {
      return "${_currentDate.day} ${thMonths[_currentDate.month - 1]} $yearTh";
    } else if (_viewMode == 'month') {
      return "${thMonths[_currentDate.month - 1]} $yearTh";
    } else if (_viewMode == 'year') {
      return "$yearTh";
    } else {
      if (_customDateRange == null) return "เลือกช่วงเวลา";
      final s = _customDateRange!.start;
      final e = _customDateRange!.end;
      return "${s.day}/${s.month}/${s.year + 543} - ${e.day}/${e.month}/${e.year + 543}";
    }
  }

  void _showReceiptDetailModal(Map<String, dynamic> receipt) {
    final List<dynamic> items = receipt['items'] ?? [];
    double totalSaved = 0.0;
    for (var item in items) {
      if (item['status'] != 'cancelled' && item['promotion_snapshot'] != null) {
        final promo = item['promotion_snapshot'];
        final double savedAmount =
            double.tryParse(
              (promo['savedAmount'] ?? promo['discount_amount'] ?? 0)
                  .toString(),
            ) ??
            0.0;
        final int qty = int.tryParse(item['quantity'].toString()) ?? 1;
        totalSaved += (savedAmount * qty);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'ใบเสร็จย้อนหลัง',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'History',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9)),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _mapValue(receipt['brand'], 'name') ?? 'ร้านค้า',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          receipt['table_label'] != null
                              ? 'Table: ${receipt['table_label']}'
                              : 'Walk-in',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'เวลา: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(receipt['created_at']).toLocal())}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          'บิลไอดี: #${receipt['id'].toString().substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Divider(
                          height: 24,
                          color: Color(0xFFE2E8F0),
                          thickness: 1,
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          itemBuilder: (context, idx) {
                            final i = items[idx];
                            final bool isItemVoid = i['status'] == 'cancelled';
                            final double itemPrice =
                                double.tryParse(i['price'].toString()) ?? 0.0;
                            final int itemQty =
                                int.tryParse(i['quantity'].toString()) ?? 1;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${itemQty}x ${i['product_name']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            decoration: isItemVoid
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: isItemVoid
                                                ? Colors.red[300]
                                                : const Color(0xFF1E293B),
                                          ),
                                        ),
                                        if (i['variant'] != null &&
                                            i['variant'] != 'normal')
                                          Text(
                                            '(${i['variant']})',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(itemPrice * itemQty),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      color: isItemVoid
                                          ? Colors.red[200]
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const Divider(
                          height: 24,
                          color: Color(0xFFE2E8F0),
                          thickness: 1,
                        ),
                        if (totalSaved > 0)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '🎁 ประหยัดไปได้',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              Text(
                                '- ${_formatCurrency(totalSaved)}',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ยอดรวมสุทธิ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              _formatCurrency(
                                double.tryParse(
                                      receipt['total_amount'].toString(),
                                    ) ??
                                    0.0,
                              ),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),

                        // 🔥 1. เติมโค้ดบล็อกนี้เข้าไป เพื่อแสดงบรรทัดรับเงินและเงินทอน เฉพาะบิลเงินสดที่ไม่ถูกยกเลิก
                        if (receipt['payment_method']
                                    .toString()
                                    .toLowerCase() ==
                                'cash' &&
                            receipt['status'] != 'cancelled') ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'รับเงินสด',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              Text(
                                _formatCurrency(
                                  double.tryParse(
                                        receipt['received_amount']
                                                ?.toString() ??
                                            '0',
                                      ) ??
                                      0.0,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'เงินทอน',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              Text(
                                _formatCurrency(
                                  double.tryParse(
                                        receipt['change_amount']?.toString() ??
                                            '0',
                                      ) ??
                                      0.0,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],

                        // 🔥 จบส่วนที่เติม
                        const Divider(
                          height: 24,
                          color: Color(0xFFE2E8F0),
                          thickness: 1,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ชำระโดย',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              receipt['payment_method']
                                  .toString()
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'พนักงานที่ทำรายการ',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              _mapValue(receipt['cashier'], 'full_name') ??
                                  'System',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final brandId =
                        receipt['brand_id']?.toString() ??
                        _mapValue(receipt['brand'], 'id')?.toString();
                    if (brandId != null && brandId.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กำลังสั่งพิมพ์ใบเสร็จซ้ำ...'),
                        ),
                      );
                      bool success = await PrinterService.printReceipt(
                        receipt,
                        brandId,
                        isReprint: true,
                      );
                      if (context.mounted) {
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'สั่งพิมพ์สำเร็จ',
                                style: TextStyle(color: Colors.green),
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'พิมพ์ไม่สำเร็จ กรุณาตรวจสอบเครื่องพิมพ์',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          );
                        }
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'ไม่พบข้อมูลร้านค้า',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.print_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'พิมพ์ใบเสร็จ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedReceipts = _receipts.where((rpt) {
      final bool isCancelled =
          rpt['status'] == 'cancelled' || rpt['payment_method'] == 'CANCELLED';
      String tableName =
          rpt['table_label']?.toString().toLowerCase() ?? 'walk-in';
      String brandName =
          _mapValue(rpt['brand'], 'name')?.toString().toLowerCase() ?? '';

      bool statusMatch = true;
      if (_statusFilter == 'completed') statusMatch = !isCancelled;
      if (_statusFilter == 'cancelled') statusMatch = isCancelled;

      final searchLower = _searchQuery.toLowerCase();
      bool searchMatch =
          _searchQuery.isEmpty ||
          tableName.contains(searchLower) ||
          brandName.contains(searchLower);

      return statusMatch && searchMatch;
    }).toList();

    final double summaryTotal = displayedReceipts.fold(0.0, (sum, r) {
      final bool isCancelled =
          r['status'] == 'cancelled' || r['payment_method'] == 'CANCELLED';
      if (isCancelled) return sum;
      return sum + (double.tryParse(r['total_amount'].toString()) ?? 0.0);
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: const AppSidebar(activeMenu: 'receipt_history'),
      body: SafeArea(
        child: Column(
          children: [
            // --- 🍔 แฮมเบอร์เกอร์เปิดเมนูด้านซ้าย ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.menu_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'ประวัติการขาย',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _loadSessionAndFetch(isLoadMore: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'รีเฟรช',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- 📅 บาร์ส่วนหัวเลือก วัน/เดือน/ปี/ช่วงเวลา ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children:
                                (_effectivePlan == 'free'
                                        ? ['day', 'custom']
                                        : ['day', 'month', 'year', 'custom'])
                                    .map((mode) {
                                      final bool isModeSelected =
                                          _viewMode == mode;
                                      return GestureDetector(
                                        onTap: () {
                                          if (mode == 'custom') {
                                            _selectCustomDateRange();
                                          } else {
                                            setState(() {
                                              _viewMode = mode;
                                              _currentDate = DateTime.now();
                                            });
                                            _loadSessionAndFetch(
                                              isLoadMore: false,
                                            );
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isModeSelected
                                                ? const Color(0xFF0F172A)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                          child: Text(
                                            mode == 'day'
                                                ? 'วัน'
                                                : mode == 'month'
                                                ? 'เดือน'
                                                : mode == 'year'
                                                ? 'ปี'
                                                : 'ช่วงเวลา',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: isModeSelected
                                                  ? Colors.white
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: _viewMode == 'custom'
                                    ? null
                                    : () => _shiftDate(-1),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _viewMode == 'custom'
                                        ? const Color(0xFFF1F5F9)
                                        : const Color(0xFFF8FAFC),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.chevron_left,
                                    size: 16,
                                    color: _viewMode == 'custom'
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _formatDateDisplay(),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _viewMode == 'custom'
                                    ? null
                                    : () => _shiftDate(1),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _viewMode == 'custom'
                                        ? const Color(0xFFF1F5F9)
                                        : const Color(0xFFF8FAFC),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: _viewMode == 'custom'
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFFF1F5F9)),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildStatusFilterButton(
                              'all',
                              'ทั้งหมด',
                              const Color(0xFF0F172A),
                            ),
                            const SizedBox(width: 6),
                            _buildStatusFilterButton(
                              'completed',
                              'สำเร็จ',
                              const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 6),
                            _buildStatusFilterButton(
                              'cancelled',
                              'ยกเลิก',
                              const Color(0xFFEF4444),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'ยอดรวมระบบ',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                _formatCurrency(summaryTotal),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            size: 16,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'ค้นหาเลขเบอร์โต๊ะอาหาร...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
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

            // --- 🗂️ ส่วนกระดานลิสต์ประวัติบิล (ทีละ 20 บิล) ---
            Expanded(
              child: _isLoading
                  ? const SuparPosLoading(fullScreen: false)
                  : _errorMessage.isNotEmpty
                  ? Center(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : displayedReceipts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'ไม่พบประวัติข้อมูลบิลในตอนนี้',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: displayedReceipts.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == displayedReceipts.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                onPressed: _isLoadMoreLoading
                                    ? null
                                    : () => _loadSessionAndFetch(
                                        isLoadMore: true,
                                      ),
                                child: _isLoadMoreLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'โหลดข้อมูลเพิ่มเติม (ทีละ 20 บิล)...',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        }

                        final rpt = displayedReceipts[index];
                        final bool isVoided =
                            rpt['status'] == 'cancelled' ||
                            rpt['payment_method'] == 'CANCELLED';
                        final double totalBill =
                            double.tryParse(rpt['total_amount'].toString()) ??
                            0.0;
                        final String payMethod =
                            rpt['payment_method']?.toString() ?? 'CASH';

                        return GestureDetector(
                          onTap: () => _showReceiptDetailModal(rpt),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isVoided
                                  ? const Color(0xFFFFF1F2)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isVoided
                                    ? const Color(0xFFFFE4E6)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isVoided
                                            ? Colors.white
                                            : (payMethod.toLowerCase() ==
                                                      'promptpay'
                                                  ? const Color(0xFFEFF6FF)
                                                  : const Color(0xFFECFDF5)),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        isVoided
                                            ? Icons.warning_amber_rounded
                                            : Icons.description_outlined,
                                        color: isVoided
                                            ? Colors.red
                                            : (payMethod.toLowerCase() ==
                                                      'promptpay'
                                                  ? Colors.blue
                                                  : Colors.green),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              rpt['table_label'] ?? 'Walk-in',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: isVoided
                                                    ? const Color(0xFF991B1B)
                                                    : const Color(0xFF1E293B),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isVoided
                                                    ? const Color(0xFFFFE4E6)
                                                    : const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                _mapValue(
                                                      rpt['brand'],
                                                      'name',
                                                    ) ??
                                                    'ร้าน',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: isVoided
                                                      ? Colors.red
                                                      : Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.access_time_rounded,
                                              size: 12,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              DateFormat('HH:mm').format(
                                                DateTime.parse(
                                                  rpt['created_at'],
                                                ).toLocal(),
                                              ),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF94A3B8),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.person_outline_rounded,
                                              size: 12,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _mapValue(
                                                    rpt['cashier'],
                                                    'full_name',
                                                  ) ??
                                                  'System',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF94A3B8),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // ⭐⭐⭐ จุดที่เป็นปัญหาถูกแก้ไขให้ปลอดภัย ไร้ const แล้วตรงนี้ครับนาย! ⭐⭐⭐
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isVoided
                                            ? const Color(0xFFFECDD3)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isVoided
                                            ? 'VOIDED'
                                            : payMethod.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: isVoided
                                              ? Colors.red
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatCurrency(totalBill),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        decoration: isVoided
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: isVoided
                                            ? Colors.red[300]
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
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

  Widget _buildStatusFilterButton(
    String statusId,
    String label,
    Color activeBgColor,
  ) {
    final bool isSelected = _statusFilter == statusId;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = statusId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
