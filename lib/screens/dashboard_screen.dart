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
import 'store_settings_screen.dart';

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

  // Advanced Dashboard Stats (Pro Plan required)
  String _effectivePlan = 'free';
  List<dynamic> _hourlySales = [];
  List<dynamic> _paymentStats = [];
  List<dynamic> _tableStats = [];
  List<dynamic> _cashierStats = [];
  int _selectedAdvancedTab = 0; // 0 = Hourly, 1 = Payment, 2 = Table, 3 = Staff

  // Offline Sync States
  int _unsyncedCount = 0;
  bool _isSyncing = false;
  bool _showSyncBanner = false;
  bool _hasShownSyncDialog = false;

  // Filter & UI States
  String _viewMode = 'last7days'; // เปลี่ยน default ให้เป็น 7 วัน
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
    final now = DateTime.now();
    
    if (_viewMode == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_viewMode == 'yesterday') {
      final y = now.subtract(const Duration(days: 1));
      start = DateTime(y.year, y.month, y.day);
      end = DateTime(y.year, y.month, y.day, 23, 59, 59);
    } else if (_viewMode == 'last7days') {
      start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_viewMode == 'last30days') {
      start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_viewMode == 'thisMonth') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (_viewMode == 'lastMonth') {
      start = DateTime(now.year, now.month - 1, 1);
      end = DateTime(now.year, now.month, 0, 23, 59, 59);
    } else {
      // custom
      start = _customDateRange?.start ?? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      end = _customDateRange?.end ?? now;
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
            _effectivePlan = result['data']['effectivePlan'] ?? 'free';
            _hourlySales = result['data']['hourlySales'] ?? [];
            _paymentStats = result['data']['paymentStats'] ?? [];
            _tableStats = result['data']['tableStats'] ?? [];
            _cashierStats = result['data']['cashierStats'] ?? [];
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
      await SyncManager().cleanupCompletedQueue();
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

  Future<void> _handleSyncNow({
    BuildContext? dialogContext,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_unsyncedCount == 0) return;
    setState(() => _isSyncing = true);

    try {
      final syncManager = SyncManager();
      await syncManager.runSyncWorker(onProgress: onProgress);
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
        double modalProgress = 0;

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
                              ? Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: CircularProgressIndicator(
                                        value: modalProgress,
                                        color: const Color(0xFFD97706),
                                        backgroundColor: const Color(
                                          0xFFFDE68A,
                                        ),
                                        strokeWidth: 4,
                                      ),
                                    ),
                                    Text(
                                      '${(modalProgress * 100).round()}%',
                                      style: const TextStyle(
                                        color: Color(0xFF92400E),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
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
                                  onProgress: (completed, total) {
                                    if (!dialogContext.mounted) return;
                                    setModalState(() {
                                      modalProgress = total == 0
                                          ? 1
                                          : completed / total;
                                    });
                                  },
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
    final now = DateTime.now();
    final isFreePlan = _effectivePlan == 'free';
    final firstAllowedDate = isFreePlan
        ? DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29))
        : DateTime(2020);
        
    final initialRange = _customDateRange ?? DateTimeRange(
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstAllowedDate,
      lastDate: now,
      initialDateRange: initialRange,
      helpText: isFreePlan
          ? 'เลือกช่วงเวลา (Free ดูย้อนหลังได้ 30 วัน)'
          : 'เลือกช่วงเวลารายงาน',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1E293B), // เปลี่ยนสีหลักให้เข้ากับตีม
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

  // 🌟 โมดูลสำหรับเลือกวันที่แบบละเอียด สวยงาม และใช้งานง่าย
  void _showAdvancedDatePicker() {
    final isFreePlan = _effectivePlan == 'free';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9E3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: Color(0xFF1E293B), size: 22),
                    SizedBox(width: 10),
                    Text(
                      'เลือกช่วงเวลา',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildDateOption('วันนี้', 'today', Icons.today_rounded),
                      _buildDateOption('เมื่อวาน', 'yesterday', Icons.turn_left_rounded),
                      _buildDateOption('7 วันล่าสุด', 'last7days', Icons.view_week_rounded),
                      _buildDateOption('30 วันล่าสุด', 'last30days', Icons.date_range_rounded),
                      const Divider(color: Color(0xFFFAF9F6), height: 24, thickness: 1.5),
                      _buildDateOption('เดือนนี้', 'thisMonth', Icons.calendar_view_month_rounded),
                      _buildDateOption('เดือนที่แล้ว', 'lastMonth', Icons.history_rounded, isLocked: isFreePlan),
                      const Divider(color: Color(0xFFFAF9F6), height: 24, thickness: 1.5),
                      ListTile(
                        onTap: () {
                          Navigator.pop(context);
                          _selectCustomDateRange();
                        },
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF9F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_calendar_rounded, size: 20, color: Color(0xFF475569)),
                        ),
                        title: const Text(
                          'เลือกตามช่วงเวลา (Custom)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF334155),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateOption(String title, String value, IconData icon, {bool isLocked = false}) {
    final bool isSelected = _viewMode == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () {
          if (isLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('กรุณาอัปเกรดเป็น PRO เพื่อดูข้อมูลย้อนหลังเกิน 30 วัน'))
            );
            return;
          }
          Navigator.pop(context); // ปิด Modal
          if (_viewMode != value) {
            setState(() {
              _viewMode = value;
            });
            _fetchDashboardData();
          }
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isSelected ? const Color(0xFFFAF9F6) : Colors.transparent,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E293B) : (isLocked ? const Color(0xFFFAF9F6) : const Color(0xFFFAF9F6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isLocked ? Icons.lock_outline_rounded : icon,
            size: 20,
            color: isSelected ? Colors.white : (isLocked ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
            color: isSelected ? const Color(0xFF1E293B) : (isLocked ? const Color(0xFF94A3B8) : const Color(0xFF334155)),
          ),
        ),
        trailing: isLocked 
          ? const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B), size: 18) 
          : (isSelected
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1E293B))
            : null),
      ),
    );
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
    if (_viewMode == 'today') return 'วันนี้';
    if (_viewMode == 'yesterday') return 'เมื่อวาน';
    if (_viewMode == 'last7days') return '7 วันล่าสุด';
    if (_viewMode == 'last30days') return '30 วันล่าสุด';
    if (_viewMode == 'thisMonth') return 'เดือนนี้';
    if (_viewMode == 'lastMonth') return 'เดือนที่แล้ว';

    const thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
    if (_customDateRange != null) {
      final s = _customDateRange!.start;
      final e = _customDateRange!.end;
      // ถ้าเลือกวันเดียวกัน
      if (s.year == e.year && s.month == e.month && s.day == e.day) {
        return "${s.day} ${thMonths[s.month - 1]} ${(s.year + 543).toString().substring(2)}";
      }
      // ถ้าเลือกข้ามวัน
      return "${s.day} ${thMonths[s.month - 1]} - ${e.day} ${thMonths[e.month - 1]}";
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
        0xFFFAF9F6,
      ), // สีพื้นหลังขาวไข่
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
                      color: const Color(0xFF1E293B),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildMetricsOverview(
                              totalRevenue: totalRev,
                              totalOrders: totalOrders,
                              averageOrderValue: aov,
                            ),

                            const SizedBox(height: 18),

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

                            const SizedBox(height: 24),

                            // --- Advanced Reports Section ---
                            _buildAdvancedReportsSection(),
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
                color: const Color(0xFFFAF9F6), // สีเทาอ่อนๆ
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
                        color: const Color(0xFFFAF9F6), // สีฟ้าอ่อน
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatDateShort(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _showAdvancedDatePicker(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: const BorderSide(color: Color(0xFFEDE9E3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              foregroundColor: const Color(0xFF475569),
            ),
            child: const Row(
              children: [
                Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF1E293B)),
                SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsOverview({
    required double totalRevenue,
    required int totalOrders,
    required double averageOrderValue,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFAF9F6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _unsyncedCount > 0 ? _showOfflineSyncModal : null,
              behavior: HitTestBehavior.opaque,
              child: _buildCompactMetric(
                title: 'ยอดขาย',
                value: _formatCurrency(totalRevenue),
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF1E293B),
                isAnimating: _unsyncedCount > 0,
              ),
            ),
          ),
          _buildMetricDivider(),
          Expanded(
            child: _buildCompactMetric(
              title: 'ออเดอร์',
              value: _formatNumber(totalOrders),
              icon: Icons.receipt_long_rounded,
              color: const Color(0xFFEC4899),
            ),
          ),
          _buildMetricDivider(),
          Expanded(
            child: _buildCompactMetric(
              title: 'ต่อบิล',
              value: _formatCurrency(averageOrderValue),
              icon: Icons.stacked_line_chart_rounded,
              color: const Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDivider() {
    return Container(
      width: 1,
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFFAF9F6),
    );
  }

  Widget _buildCompactMetric({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isAnimating = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: isAnimating
              ? WigglingSyncIcon(icon: icon, color: color)
              : Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: double.infinity,
          height: 22,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.35,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedTabs() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final buttons = [
          _buildAdvancedTabButton(
            'รายชั่วโมง',
            0,
            Icons.access_time_filled_rounded,
            compact: isCompact,
          ),
          _buildAdvancedTabButton(
            'การชำระเงิน',
            1,
            Icons.payments_rounded,
            compact: isCompact,
          ),
          _buildAdvancedTabButton(
            'โต๊ะ/ออเดอร์',
            2,
            Icons.table_restaurant_rounded,
            compact: isCompact,
          ),
          _buildAdvancedTabButton(
            'พนักงาน',
            3,
            Icons.people_alt_rounded,
            compact: isCompact,
          ),
        ];

        final content = isCompact
            ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: buttons[0]),
                      const SizedBox(width: 4),
                      Expanded(child: buttons[1]),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: buttons[2]),
                      const SizedBox(width: 4),
                      Expanded(child: buttons[3]),
                    ],
                  ),
                ],
              )
            : Row(children: buttons);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFAF9F6)),
          ),
          child: content,
        );
      },
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
        padding: const EdgeInsets.symmetric(vertical: 10),
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
              size: 16,
              color: isActive
                  ? Colors.white
                  : (iconColor ?? const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int? _selectedChartIndex;

  String _formatDateFriendly(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      final thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
      return '${d.day} ${thMonths[d.month - 1]} ${d.year + 543}';
    } catch (e) {
      return dateStr;
    }
  }

  void _updateChartSelection(double dx, double width, int length) {
    if (length <= 1) return;
    final stepX = width / (length - 1);
    int index = (dx / stepX).round();
    if (index < 0) index = 0;
    if (index >= length) index = length - 1;
    if (_selectedChartIndex != index) {
      setState(() {
        _selectedChartIndex = index;
      });
    }
  }

  // --- กราฟ Smooth Line ---
  Widget _buildChartSection() {
    List<double> values = [];
    List<String> dates = [];
    if (_chartData.isNotEmpty) {
      for (var day in _chartData) {
        values.add(
          double.tryParse(day['total_revenue']?.toString() ?? '0') ?? 0,
        );
        dates.add(day['report_date']?.toString() ?? day['date']?.toString() ?? day['day']?.toString() ?? day['created_at']?.toString() ?? 'Keys: ${day.keys.join(', ')}');
      }
    } else {
      // Dummy data if empty so the UI doesn't look blank
      values = [0, 0, 0, 200, 1800, 400, 2200, 800, 0, 0, 0, 0];
      dates = List.generate(12, (index) => '2023-01-${(index + 1).toString().padLeft(2, '0')}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      key: const ValueKey('chart_section'),
      children: [
        if (_selectedChartIndex != null && _selectedChartIndex! < values.length)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF9F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0E7FF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF1E293B)),
                    const SizedBox(width: 6),
                    Text(
                      _formatDateFriendly(dates[_selectedChartIndex!]),
                      style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Text(
                  _formatCurrency(values[_selectedChartIndex!]),
                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onPanUpdate: (details) => _updateChartSelection(details.localPosition.dx, constraints.maxWidth, values.length),
              onTapDown: (details) => _updateChartSelection(details.localPosition.dx, constraints.maxWidth, values.length),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: SmoothLineChartPainter(
                    values: values,
                    selectedIndex: _selectedChartIndex,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '1',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              '15',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${DateTime(_currentDate.year, _currentDate.month + 1, 0).day}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
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
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'ยังไม่มีข้อมูลเมนูขายดี',
            style: TextStyle(
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('products_section'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFAF9F6)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topProducts.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 16, color: Color(0xFFFAF9F6)),
        itemBuilder: (context, index) {
          final product = _topProducts[index];
          double pRev =
              double.tryParse(product['revenue']?.toString() ?? '0') ?? 0;
          return Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: index == 0
                      ? const Color(0xFFFEF08A)
                      : index == 1
                      ? const Color(0xFFEDE9E3)
                      : const Color(0xFFFAF9F6),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: index == 0
                          ? const Color(0xFFCA8A04)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  product['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
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
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    '${product['qty']} ชิ้น',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
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

  // --- ส่วนรายงานขั้นสูง (Pro Feature) ---
  Widget _buildAdvancedReportsSection() {
    final bool isUnlocked =
        _effectivePlan == 'pro' || _effectivePlan == 'ultimate';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF), // สีม่วงอ่อน
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.insights_rounded,
                color: Color(0xFF7E22CE),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'รายงานขั้นสูง',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // Premium Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF15803D), Color(0xFF16A34A)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tabs
        _buildAdvancedTabs(),
        const SizedBox(height: 16),

        // Body Content
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: !isUnlocked
              ? _buildLockedOverlay()
              : _selectedAdvancedTab == 0
              ? _buildHourlySalesSection()
              : _selectedAdvancedTab == 1
              ? _buildPaymentStatsSection()
              : _selectedAdvancedTab == 2
              ? _buildTableStatsSection()
              : _buildCashierStatsSection(),
        ),
      ],
    );
  }

  Widget _buildAdvancedTabButton(
    String title,
    int index,
    IconData icon, {
    bool compact = false,
  }) {
    final bool isActive = _selectedAdvancedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedAdvancedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          vertical: compact ? 9 : 10,
          horizontal: compact ? 8 : 16,
        ),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F172A) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: compact ? 13 : 14,
              color: isActive ? Colors.white : const Color(0xFF64748B),
            ),
            SizedBox(width: compact ? 5 : 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedOverlay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDE9E3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ก้อนไอคอนล็อกแบบพรีเมียม
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF), // สีม่วงอ่อนมากๆ
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC084FC).withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.lock_person_rounded,
              color: Color(0xFF7E22CE), // สีม่วงเข้ม
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'วิเคราะห์ข้อมูลเชิงลึกเฉพาะลูกค้าแผน PRO 🚀',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ยกระดับร้านค้าของคุณด้วยการวิเคราะห์ยอดขายรายชั่วโมง วิธีการชำระเงินที่นิยมใช้ และสถิติโต๊ะ/ประเภทออเดอร์เพื่อวางแผนการขายให้มีประสิทธิภาพสูงสุด',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          // ปุ่มอัปเกรดแบบไล่เฉดสีไล่ระดับ
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF15803D), // ม่วงเข้ม
                  Color(0xFF1E293B), // ฟ้าม่วง
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF15803D).withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () async {
                final brandId = await StorageService.getBrandId();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StoreSettingsScreen(
                        brandId: brandId,
                        initialTab: 1, // เปิดที่แท็บแพ็กเกจ
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'อัปเกรดเป็นแผน PRO เลย',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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

  Widget _buildHourlySalesSection() {
    if (_hourlySales.isEmpty) {
      return _buildEmptySection('ไม่มีข้อมูลยอดขายรายชั่วโมงในช่วงเวลานี้');
    }

    double maxRevenue = 0.0;
    for (var h in _hourlySales) {
      double rev = double.tryParse(h['revenue']?.toString() ?? '0') ?? 0.0;
      if (rev > maxRevenue) maxRevenue = rev;
    }
    if (maxRevenue == 0) maxRevenue = 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'การกระจายตัวยอดขายรายชั่วโมง',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'วิเคราะห์ช่วงเวลาที่ยอดขายสูงสุดของวัน (หน่วย: บาท)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _hourlySales.map((h) {
                  final int hour =
                      int.tryParse(h['hour']?.toString() ?? '0') ?? 0;
                  final double revenue =
                      double.tryParse(h['revenue']?.toString() ?? '0') ?? 0.0;
                  final int orders =
                      int.tryParse(h['orders']?.toString() ?? '0') ?? 0;
                  final double barHeight =
                      (revenue / maxRevenue) *
                      110; // ความสูงสูงสุดของแท่งคือ 110

                  final hourStr = hour < 10 ? '0$hour:00' : '$hour:00';

                  return GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).removeCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '$hourStr น. | ยอดขาย: ${_formatCurrency(revenue)} ($orders บิล)',
                          ),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      width: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (revenue > 0)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatShortLabel(revenue),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          // ตัวแท่งกราฟ
                          Container(
                            height: math.max(barHeight, 4.0),
                            width: 14,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: revenue > 0
                                    ? [
                                        const Color(0xFF818CF8),
                                        const Color(0xFF1E293B),
                                      ]
                                    : [
                                        const Color(0xFFEDE9E3),
                                        const Color(0xFFCBD5E1),
                                      ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hour < 10 ? '0$hour' : '$hour',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortLabel(double val) {
    if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(1)}k';
    }
    return val.toInt().toString();
  }

  Widget _buildPaymentStatsSection() {
    if (_paymentStats.isEmpty) {
      return _buildEmptySection('ไม่มีข้อมูลช่องทางการชำระเงินในช่วงเวลานี้');
    }

    double totalPaymentRevenue = 0.0;
    for (var p in _paymentStats) {
      totalPaymentRevenue +=
          double.tryParse(p['revenue']?.toString() ?? '0') ?? 0.0;
    }
    if (totalPaymentRevenue == 0) totalPaymentRevenue = 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สัดส่วนช่องทางการชำระเงิน',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _paymentStats.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 24, color: Color(0xFFFAF9F6)),
            itemBuilder: (context, index) {
              final item = _paymentStats[index];
              final String rawMethod = item['method']?.toString() ?? 'other';
              final double revenue =
                  double.tryParse(item['revenue']?.toString() ?? '0') ?? 0.0;
              final int orders =
                  int.tryParse(item['orders']?.toString() ?? '0') ?? 0;
              final double ratio = revenue / totalPaymentRevenue;

              // หาไอคอนและสีที่เหมาะสมตามช่องทางการชำระเงิน
              IconData methodIcon = Icons.payment_rounded;
              Color methodColor = const Color(0xFF16A34A);
              String displayName = rawMethod.toUpperCase();

              if (rawMethod.toLowerCase() == 'cash') {
                methodIcon = Icons.money_rounded;
                methodColor = const Color(0xFF10B981);
                displayName = 'เงินสด (Cash)';
              } else if (rawMethod.toLowerCase() == 'promptpay') {
                methodIcon = Icons.qr_code_scanner_rounded;
                methodColor = const Color(0xFF0EA5E9);
                displayName = 'พร้อมเพย์ (PromptPay)';
              } else if (rawMethod.toLowerCase() == 'transfer') {
                methodIcon = Icons.account_balance_rounded;
                methodColor = const Color(0xFF15803D);
                displayName = 'โอนเงิน (Transfer)';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: methodColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(methodIcon, color: methodColor, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '$orders บิล',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatCurrency(revenue),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '${(ratio * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFFAF9F6),
                      valueColor: AlwaysStoppedAnimation<Color>(methodColor),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTableStatsSection() {
    if (_tableStats.isEmpty) {
      return _buildEmptySection('ไม่มีข้อมูลยอดขายรายโต๊ะในช่วงเวลานี้');
    }

    final List<dynamic> sortedTables = List.from(_tableStats)
      ..sort((a, b) {
        double revA = double.tryParse(a['revenue']?.toString() ?? '0') ?? 0.0;
        double revB = double.tryParse(b['revenue']?.toString() ?? '0') ?? 0.0;
        return revB.compareTo(revA);
      });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สถิติตามโต๊ะและประเภทออเดอร์',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedTables.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 20, color: Color(0xFFFAF9F6)),
            itemBuilder: (context, index) {
              final item = sortedTables[index];
              final String label = item['table']?.toString() ?? 'Walk-in';
              final String type = item['type']?.toString() ?? 'takeaway';
              final double revenue =
                  double.tryParse(item['revenue']?.toString() ?? '0') ?? 0.0;
              final int orders =
                  int.tryParse(item['orders']?.toString() ?? '0') ?? 0;

              final bool isTakeaway = type.toLowerCase() == 'takeaway';

              return Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isTakeaway
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isTakeaway
                          ? Icons.shopping_bag_rounded
                          : Icons.table_restaurant_rounded,
                      color: isTakeaway
                          ? const Color(0xFFD97706)
                          : const Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isTakeaway ? 'ซื้อกลับบ้าน' : 'โต๊ะ $label',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          isTakeaway ? 'Takeaway' : 'ทานที่ร้าน',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(revenue),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$orders บิล',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySection(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCashierStatsSection() {
    if (_cashierStats.isEmpty) {
      return _buildEmptySection('ไม่มีข้อมูลยอดขายรายบุคคลในช่วงเวลานี้');
    }

    // เรียงลำดับพนักงานตามยอดขายจากมากไปน้อย
    final List<dynamic> sortedCashiers = List.from(_cashierStats)
      ..sort((a, b) {
        double revA = double.tryParse(a['revenue']?.toString() ?? '0') ?? 0.0;
        double revB = double.tryParse(b['revenue']?.toString() ?? '0') ?? 0.0;
        return revB.compareTo(revA);
      });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ประสิทธิภาพและยอดขายรายบุคคล',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedCashiers.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 20, color: Color(0xFFFAF9F6)),
            itemBuilder: (context, index) {
              final item = sortedCashiers[index];
              final String name = item['name']?.toString() ?? 'พนักงาน';
              final String avatarUrl = item['avatarUrl']?.toString() ?? '';
              final double revenue =
                  double.tryParse(item['revenue']?.toString() ?? '0') ?? 0.0;
              final int orders =
                  int.tryParse(item['orders']?.toString() ?? '0') ?? 0;

              return Row(
                children: [
                  // อันดับ
                  Container(
                    width: 24,
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: index == 0
                            ? const Color(0xFFCA8A04) // ทอง
                            : index == 1
                            ? const Color(0xFF64748B) // เงิน
                            : const Color(0xFFCBD5E1),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // รูปโปรไฟล์พนักงาน
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFFAF9F6),
                    backgroundImage:
                        avatarUrl.isNotEmpty && avatarUrl.startsWith('http')
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl.isEmpty || !avatarUrl.startsWith('http')
                        ? Text(
                            name.isNotEmpty
                                ? name.substring(0, 1).toUpperCase()
                                : 'P',
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'บทบาท: ผู้ขาย/แคชเชียร์',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(revenue),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$orders บิล',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// 🎨 Custom Painter สำหรับวาดกราฟเส้นโค้ง (Smooth Spline Chart) คล้ายในดีไซน์
class SmoothLineChartPainter extends CustomPainter {
  final List<double> values;
  final int? selectedIndex;

  SmoothLineChartPainter({required this.values, this.selectedIndex});

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
          const Color(0xFF16A34A).withOpacity(0.3),
          const Color(0xFF16A34A).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // วาดเส้นกราฟสีม่วงๆ คมๆ
    final linePaint = Paint()
      ..color = const Color(0xFF16A34A) // สีม่วงอมฟ้าตามดีไซน์
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 // ปรับให้บางลง
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // วาดจุดที่เลือก (Selected Point)
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < points.length) {
      final p = points[selectedIndex!];
      
      final vLinePaint = Paint()
        ..color = const Color(0xFF16A34A).withOpacity(0.3)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height), vLinePaint);

      final dotPaint = Paint()..color = Colors.white;
      final dotBorderPaint = Paint()
        ..color = const Color(0xFF16A34A)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(p, 5, dotPaint);
      canvas.drawCircle(p, 5, dotBorderPaint);
    }

    // --- วาดเส้นไกด์แนวนอน ---
    final gridPaint = Paint()
      ..color = const Color(0xFFEDE9E3).withOpacity(0.5)
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

class WigglingSyncIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const WigglingSyncIcon({super.key, required this.icon, required this.color});

  @override
  State<WigglingSyncIcon> createState() => _WigglingSyncIconState();
}

class _WigglingSyncIconState extends State<WigglingSyncIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // วิ่งๆ หยุดๆ: 0-0.2: สั่น, 0.2-1.0: หยุด
        double angle = 0.0;
        if (_controller.value < 0.2) {
          angle = math.sin(_controller.value * 100) * 0.4;
        }
        return Transform.rotate(
          angle: angle,
          child: child,
        );
      },
      child: Icon(widget.icon, size: 16, color: widget.color),
    );
  }
}





