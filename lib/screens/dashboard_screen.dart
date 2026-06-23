// lib/screens/dashboard_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui'
    as ui; // 🌟 เพิ่มบรรทัดนี้ เพื่อกันชื่อ TextDirection ชนกับของ intl
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/sync_manager.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoading = true;
  String _errorMessage = '';

  // Data States
  Map<String, dynamic> _summary = {};
  List<dynamic> _chartData = [];
  List<dynamic> _topProducts = [];

  // Offline Sync States
  int _unsyncedCount = 0;
  bool _isSyncing = false;
  bool _showSyncBanner = false;
  bool _hasShownSyncDialog = false;

  // Filter & UI States
  String _viewMode = 'month'; // day, month, year, custom
  DateTime _currentDate = DateTime.now();
  DateTimeRange? _customDateRange;

  int _selectedBottomTab = 0; // 0 = กราฟรายได้, 1 = เมนูขายดี

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    _checkOfflineData();
  }

  Map<String, String> _getDateRange() {
    DateTime start, end;
    if (_viewMode == 'day') {
      start = DateTime(_currentDate.year, _currentDate.month, _currentDate.day);
      end = DateTime(
        _currentDate.year,
        _currentDate.month,
        _currentDate.day,
        23,
        59,
        59,
      );
    } else if (_viewMode == 'month') {
      start = DateTime(_currentDate.year, _currentDate.month, 1);
      end = DateTime(_currentDate.year, _currentDate.month + 1, 0, 23, 59, 59);
    } else if (_viewMode == 'year') {
      start = DateTime(_currentDate.year, 1, 1);
      end = DateTime(_currentDate.year, 12, 31, 23, 59, 59);
    } else {
      start =
          _customDateRange?.start ??
          DateTime.now().subtract(const Duration(days: 7));
      end = _customDateRange?.end ?? DateTime.now();
      end = DateTime(end.year, end.month, end.day, 23, 59, 59);
    }
    return {
      'start': DateFormat('yyyy-MM-dd').format(start),
      'end': DateFormat('yyyy-MM-dd').format(end),
    };
  }

  Future<void> _fetchDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final accessToken = await StorageService.getToken();
      final range = _getDateRange();

      final uri = Uri.parse(
        '${ApiService.dashboard}?start_date=${range['start']}&end_date=${range['end']}',
      );

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
          setState(() {
            _summary = result['data']['summary'] ?? {};
            _chartData = result['data']['chartData'] ?? [];
            _topProducts = result['data']['topProducts'] ?? [];
            _isLoading = false;
          });
        } else {
          throw Exception(result['error']);
        }
      } else {
        throw Exception("API Error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _errorMessage = "ไม่สามารถดึงข้อมูลแดชบอร์ดได้: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _checkOfflineData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sync_queue WHERE type = 'PAYMENT' AND status = 'pending'",
      );
      int count = Sqflite.firstIntValue(result) ?? 0;

      setState(() {
        _unsyncedCount = count;
        _showSyncBanner = count > 0;
      });

      if (count > 0 && !_hasShownSyncDialog && mounted) {
        _hasShownSyncDialog = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showOfflineSyncModal();
        });
      }
    } catch (e) {
      debugPrint("❌ Error checking offline queue: $e");
    }
  }

  Future<void> _handleSyncNow({BuildContext? dialogContext}) async {
    if (_unsyncedCount == 0) return;
    setState(() => _isSyncing = true);

    try {
      final syncManager = SyncManager();
      await syncManager.runSyncWorker();
      await _checkOfflineData();
      await _fetchDashboardData();
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เกิดข้อผิดพลาดในการซิงค์ กรุณาลองใหม่'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // 🌟 Modal แบบล้ำๆ ตามดีไซน์
  Future<void> _showOfflineSyncModal() async {
    if (!mounted || _unsyncedCount <= 0) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // บังคับให้ต้องเลือกกดปุ่ม
      builder: (dialogContext) {
        bool modalSyncing = _isSyncing;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              elevation: 0,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- ก้อนไอคอนเมฆ ---
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFEF3C7,
                            ), // พื้นหลังสีเหลือง/ส้มอ่อน
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: modalSyncing
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFD97706),
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_off_rounded,
                                  color: Color(0xFFD97706),
                                  size: 40,
                                ), // สีส้มทอง
                        ),
                        // Badge เครื่องหมายตกใจ
                        if (!modalSyncing)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444), // สีแดง
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  '!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // --- Text หลัก ---
                    const Text(
                      'มีบิลรอซิงค์ข้อมูล',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // --- Subtitle เล่นสีเน้นข้อความ ---
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          fontFamily: 'Kanit',
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          const TextSpan(text: 'มียอดขาย '),
                          TextSpan(
                            text: '$_unsyncedCount รายการ ',
                            style: const TextStyle(
                              color: Color(0xFFD97706),
                              fontWeight: FontWeight.w800,
                            ), // ไฮไลท์สีส้มทอง
                          ),
                          const TextSpan(
                            text:
                                'ที่บันทึกแบบออฟไลน์ไว้ กรุณากดซิงค์เพื่อให้ข้อมูลรวมในกราฟ',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- ปุ่มหลัก (อัปเดตยอดขาย) แบบ Gradient ---
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFF59E0B),
                            Color(0xFFF97316),
                          ], // ส้ม-เหลือง
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF97316).withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: modalSyncing
                            ? null
                            : () async {
                                setModalState(() => modalSyncing = true);
                                await _handleSyncNow(
                                  dialogContext: dialogContext,
                                );
                                if (dialogContext.mounted) {
                                  setModalState(() => modalSyncing = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors
                              .transparent, // โปร่งใสเพื่อให้เห็น Gradient กล่องหลัง
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: modalSyncing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'อัปเดตยอดขายเดี๋ยวนี้ 🚀',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // --- ปุ่มรอง (ข้ามไปก่อน) ---
                    TextButton(
                      onPressed: modalSyncing
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'ข้ามไปก่อน (ไว้ทำทีหลัง)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange:
          _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0F172A),
            onPrimary: Colors.white,
            onSurface: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _viewMode = 'custom';
        _customDateRange = picked;
      });
      _fetchDashboardData();
    }
  }

  String _formatCurrency(dynamic amount) {
    double val = double.tryParse(amount?.toString() ?? '0') ?? 0.0;
    return NumberFormat.currency(
      locale: 'th_TH',
      symbol: '฿',
      decimalDigits: 2,
    ).format(val); // ใส่ .2 ตามดีไซน์
  }

  String _formatNumber(dynamic amount) {
    int val = int.tryParse(amount?.toString() ?? '0') ?? 0;
    return NumberFormat('#,###').format(val);
  }

  String _formatDateShort() {
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
    final yearStr = DateFormat(
      'yy',
    ).format(_currentDate); // Format ปี 2 หลัก เช่น "26"

    if (_viewMode == 'day')
      return "${_currentDate.day} ${thMonths[_currentDate.month - 1]} $yearStr";
    if (_viewMode == 'month')
      return "เดือน ${thMonths[_currentDate.month - 1]} $yearStr";
    if (_viewMode == 'year') return "ปี ${_currentDate.year + 543}";
    if (_customDateRange != null) {
      final s = _customDateRange!.start;
      final e = _customDateRange!.end;
      return "${s.day} - ${e.day} ${thMonths[e.month - 1]}";
    }
    return "ช่วงเวลานี้";
  }

  @override
  Widget build(BuildContext context) {
    double totalRev =
        double.tryParse(_summary['totalRevenue']?.toString() ?? '0') ?? 0;
    int totalOrders =
        int.tryParse(_summary['totalOrders']?.toString() ?? '0') ?? 0;
    double aov = totalOrders > 0 ? totalRev / totalOrders : 0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(
        0xFFF4F7FA,
      ), // สีพื้นหลังเทาอมฟ้าสว่างๆ แบบแอป Modern
      drawer: const AppSidebar(activeMenu: 'dashboard'),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const SuparPosLoading(fullScreen: false)
                  : _errorMessage.isNotEmpty
                  ? Center(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchDashboardData,
                      color: const Color(0xFF4F46E5),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // --- Top Grid Cards ---
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricCard(
                                    title: 'ยอดขาย',
                                    value: _formatCurrency(totalRev),
                                    subtitle: _formatDateShort(),
                                    icon: Icons.trending_up_rounded,
                                    iconBgColor: const Color(
                                      0xFF4F46E5,
                                    ), // ฟ้าม่วง
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildMetricCard(
                                    title: 'ออเดอร์',
                                    value: '${_formatNumber(totalOrders)} บิล',
                                    subtitle: 'สำเร็จ',
                                    icon: Icons
                                        .camera_alt_outlined, // ไอคอนคล้ายๆ รูปกล้องในเรฟ
                                    iconBgColor: const Color(
                                      0xFFDB2777,
                                    ), // ชมพูบานเย็น
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // --- Bottom Full Card ---
                            SizedBox(
                              width: double.infinity,
                              child: _buildMetricCard(
                                title: 'ยอดต่อบิล (AOV)',
                                value: _formatCurrency(aov),
                                subtitle: 'เฉลี่ยต่อลูกค้า',
                                icon: Icons.pie_chart_outline_rounded,
                                iconBgColor: const Color(0xFF10B981), // เขียวสด
                              ),
                            ),

                            const SizedBox(height: 24),

                            // --- Tabs Toggle ---
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildToggleButton(
                                      'กราฟรายได้',
                                      0,
                                      Icons.show_chart_rounded,
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildToggleButton(
                                      'เมนูขายดี',
                                      1,
                                      Icons.workspace_premium_rounded,
                                      iconColor: const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // --- Dynamic Content Section ---
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _selectedBottomTab == 0
                                  ? _buildChartSection()
                                  : _buildTopProductsList(),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Header ตามดีไซน์รูปภาพ ---
  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _scaffoldKey.currentState
                ?.openDrawer(), // เปิด Sidebar ได้เหมือนเดิม
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9), // สีเทาอ่อนๆ
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.bar_chart_rounded,
                color: Color(0xFF0F172A),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ภาพรวมร้าน',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Text(
                      'ช่วงเวลา: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF), // สีฟ้าอ่อน
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatDateShort(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _selectCustomDateRange(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              foregroundColor: const Color(0xFF475569),
            ),
            child: const Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16),
                SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Card ข้อมูลตามดีไซน์รูปภาพ ---
  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -1.0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }

  // --- ปุ่ม Toggle กราฟ/เมนูขายดี ---
  Widget _buildToggleButton(
    String title,
    int index,
    IconData icon, {
    Color? iconColor,
  }) {
    final bool isActive = _selectedBottomTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedBottomTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF0F172A)
              : Colors.transparent, // สีดำตอน Active
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? Colors.white
                  : (iconColor ?? const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- กราฟ Smooth Line ---
  Widget _buildChartSection() {
    List<double> values = [];
    if (_chartData.isNotEmpty) {
      for (var day in _chartData) {
        values.add(
          double.tryParse(day['total_revenue']?.toString() ?? '0') ?? 0,
        );
      }
    } else {
      // Dummy data if empty so the UI doesn't look blank
      values = [0, 0, 0, 200, 1800, 400, 2200, 800, 0, 0, 0, 0];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      key: const ValueKey('chart_section'),
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: CustomPaint(painter: SmoothLineChartPainter(values: values)),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '1',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              '16',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${DateTime(_currentDate.year, _currentDate.month + 1, 0).day}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- รายการเมนูขายดี ---
  Widget _buildTopProductsList() {
    if (_topProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'ยังไม่มีข้อมูลเมนูขายดี',
            style: TextStyle(
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('products_section'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topProducts.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 24, color: Color(0xFFF1F5F9)),
        itemBuilder: (context, index) {
          final product = _topProducts[index];
          double pRev =
              double.tryParse(product['revenue']?.toString() ?? '0') ?? 0;
          return Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: index == 0
                      ? const Color(0xFFFEF08A)
                      : index == 1
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: index == 0
                          ? const Color(0xFFCA8A04)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  product['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(pRev),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    '${product['qty']} ชิ้น',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// 🎨 Custom Painter สำหรับวาดกราฟเส้นโค้ง (Smooth Spline Chart) คล้ายในดีไซน์
class SmoothLineChartPainter extends CustomPainter {
  final List<double> values;

  SmoothLineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    double maxVal = values.reduce(math.max);
    if (maxVal == 0) maxVal = 1;

    final stepX = size.width / (values.length > 1 ? values.length - 1 : 1);
    final topPadding = 20.0; // เว้นข้างบนไว้หน่อย

    // หาแกน Y แต่ละจุด
    List<Offset> points = [];
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      // ให้สัดส่วนความสูงสัมพันธ์กับกราฟ
      final y =
          size.height - ((values[i] / maxVal) * (size.height - topPadding));
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    // คำนวณเส้นโค้งสมูทๆ แบบ Cubic Bezier
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p1.dx,
        p1.dy,
      );
    }

    // วาดพื้นหลัง Gradient ใต้เส้นกราฟ
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6366F1).withOpacity(0.3),
          const Color(0xFF6366F1).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // วาดเส้นกราฟสีม่วงๆ คมๆ
    final linePaint = Paint()
      ..color =
          const Color(0xFF6366F1) // สีม่วงอมฟ้าตามดีไซน์
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // --- วาดเส้นไกด์แนวนอน ---
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      double y = size.height - (i * (size.height / 4));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      // 🌟 ใช้ ui.TextDirection.ltr เพื่อกันชื่อคลาสชนกับแพ็กเกจ intl
      final span = TextSpan(
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        text: _formatYLabel((maxVal / 4) * i),
      );
      final tp = TextPainter(
        text: span,
        textAlign: TextAlign.left,
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-25, y - 6));
    }
  }

  String _formatYLabel(double val) {
    if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(1)}k';
    }
    return val.toInt().toString();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
