// lib/screens/table_management_screen.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 🌟 เก็บไว้ใช้จำค่า List/Grid View (ถูกต้องแล้ว)
import 'package:flutter/services.dart';

import '../api_service.dart'; // 🌟 นำเข้า ApiService ที่ฉลาดๆ ของเรา
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 ใช้ตู้เซฟดิจิทัล
import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../widgets/products/products_top_bar.dart';

class TableManagementScreen extends StatefulWidget {
  final bool showTopBar;
  final bool isListView;

  const TableManagementScreen({
    super.key,
    this.showTopBar = true,
    this.isListView = false,
  });

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const String _viewModePrefKey = 'products_management_is_list_view';
  static const MethodChannel _nfcChannel = MethodChannel(
    'pos_foodscan/nfc_writer',
  );

  List<dynamic> tables = [];
  bool isLoading = true;
  String errorMessage = '';
  String? accessToken;
  String? _brandId;
  String searchQuery = '';
  late bool _isListView;
  bool _nfcWriteMode = false;
  bool _isWritingNfc = false;
  String _tableQrMode = 'rotating';

  bool get _canUseNfc => _tableQrMode == 'static';

  @override
  void initState() {
    super.initState();
    _isListView = widget.isListView;
    _loadSavedViewMode();
    _loadSessionAndFetch();
  }

  @override
  void didUpdateWidget(covariant TableManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isListView != widget.isListView) {
      _isListView = widget.isListView;
    }
  }

  // 🌟 SharedPreferences ใช้สำหรับจำการตั้งค่าจุกจิกแบบนี้ ถูกต้องที่สุดแล้วครับ!
  Future<void> _loadSavedViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool(_viewModePrefKey);
    if (!mounted || savedValue == null) return;
    setState(() => _isListView = savedValue);
  }

  Future<void> _setListView(bool value) async {
    setState(() => _isListView = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_viewModePrefKey, value);
  }

  Future<void> _loadTableQrMode() async {
    final brandId = _brandId;
    final prefs = await SharedPreferences.getInstance();
    if (brandId != null && brandId.isNotEmpty) {
      final cachedMode = prefs.getString('table_qr_mode_$brandId');
      if (cachedMode == 'static' || cachedMode == 'rotating') {
        _applyTableQrMode(cachedMode!);
      }
    }

    try {
      if (accessToken == null || accessToken!.isEmpty) return;
      final response = await http.get(
        Uri.parse(ApiService.settings),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final brand = data['brand'] ?? data;
      final mode =
          (brand['table_qr_mode'] ?? brand['config']?['qr_mode'] ?? 'rotating')
              .toString();
      if (mode != 'static' && mode != 'rotating') return;

      if (brandId != null && brandId.isNotEmpty) {
        await prefs.setString('table_qr_mode_$brandId', mode);
      }
      _applyTableQrMode(mode);
    } catch (_) {}
  }

  void _applyTableQrMode(String mode) {
    if (!mounted || (mode != 'static' && mode != 'rotating')) return;
    setState(() {
      _tableQrMode = mode;
      if (mode != 'static') _nfcWriteMode = false;
    });
  }

  Future<void> _writeTableToNfc(dynamic table) async {
    if (!_canUseNfc || _isWritingNfc) return;

    final bool isAvailable =
        await _nfcChannel.invokeMethod<bool>('isNfcAvailable') ?? false;
    if (!isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เครื่องนี้ยังใช้ NFC ไม่ได้ หรือยังไม่ได้เปิด NFC'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final payload = _buildTableNfcPayload(table);
    setState(() => _isWritingNfc = true);

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.nfc_rounded,
                  color: Color(0xFF10B981),
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'แตะแท็ก NFC สำหรับโต๊ะ ${table['label']?.toString() ?? '-'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'เอาแท็ก NFC แตะหลังเครื่อง รอจนขึ้นว่าเขียนสำเร็จ',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () async {
                  await _nfcChannel.invokeMethod<bool>('cancelNfcWrite');
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        );
      },
    );

    try {
      await _nfcChannel.invokeMethod<String>('writeNfcTag', {
        'payload': payload,
      });
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เขียน NFC โต๊ะ ${table['label'] ?? '-'} สำเร็จแล้ว'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code != 'CANCELLED') {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'เขียน NFC ไม่สำเร็จ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isWritingNfc = false);
    }
  }

  String _buildTableNfcPayload(dynamic table) {
    final tableId = table['id']?.toString() ?? '';
    final passcode = table['access_token']?.toString() ?? '';
    final label = table['label']?.toString() ?? '';
    final brand =
        table['brand_id'] ??
        table['brandId'] ??
        (table['brand'] is Map ? table['brand']['id'] : null);
    final brandId = brand?.toString() ?? _brandId ?? '';

    if (brandId.isNotEmpty && tableId.isNotEmpty && passcode.isNotEmpty) {
      return 'https://pos-foodscan.com/shop/$brandId/table/$tableId$passcode';
    }

    return Uri(
      scheme: 'foodscan',
      host: 'table',
      path: tableId,
      queryParameters: {
        if (passcode.isNotEmpty) 'token': passcode,
        if (label.isNotEmpty) 'label': label,
      },
    ).toString();
  }

  // 🌟 เคลียร์ลิ้นชักขยะทิ้ง ดึงเฉพาะบัตร VIP จากตู้เซฟ
  Future<void> _loadSessionAndFetch() async {
    try {
      final savedToken = await StorageService.getToken();
      final savedBrandId = await StorageService.getBrandId();

      if (savedToken != null && savedToken.isNotEmpty) {
        setState(() {
          accessToken = savedToken;
          _brandId = savedBrandId.isNotEmpty ? savedBrandId : null;
        });
        await _loadTableQrMode();
        await _fetchTablesData();
      } else {
        setState(() {
          errorMessage = 'ไม่พบเซสชัน กรุณาล็อกอินใหม่อีกครั้ง';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'ข้อผิดพลาดคลังเครื่อง: $e';
        isLoading = false;
      });
    }
  }

  // 🚀 ดึง API แบบ Auto-switch Environment
  Future<void> _fetchTablesData() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      final response = await http.get(
        Uri.parse(
          "${ApiService.baseUrl}/tables",
        ), // 🚀 ใช้ ApiService แทน dotenv
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['success'] == true) {
          setState(() {
            tables = resData['data'] ?? [];
            isLoading = false;
          });
        } else {
          throw resData['error'] ?? 'เกิดข้อผิดพลาดในการดึงข้อมูล';
        }
      } else {
        throw 'การเชื่อมต่อผิดพลาด (Status Code: ${response.statusCode})';
      }
    } catch (e) {
      setState(() {
        errorMessage = '$e';
        isLoading = false;
      });
    }
  }

  // 🚀 บันทึกข้อมูลโต๊ะแบบ Auto-switch Environment
  Future<void> _saveTableData(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${ApiService.baseUrl}/tables",
        ), // 🚀 ใช้ ApiService แทน dotenv
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกข้อมูลโต๊ะสำเร็จ! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchTablesData();
      } else {
        throw resData['error'] ?? 'บันทึกข้อมูลล้มเหลว';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ผิดพลาด: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // 🚀 ลบข้อมูลโต๊ะแบบ Auto-switch Environment
  Future<void> _deleteTable(String tableId) async {
    try {
      final response = await http.delete(
        Uri.parse(
          "${ApiService.baseUrl}/tables?id=$tableId",
        ), // 🚀 ใช้ ApiService แทน dotenv
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบโต๊ะเรียบร้อยแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchTablesData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบล้มเหลว: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _generatePasscode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  void _openTableFormModal({Map<String, dynamic>? initialTableData}) {
    final labelController = TextEditingController(
      text: initialTableData == null ? '' : initialTableData['label'] ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                initialTableData == null
                    ? 'เพิ่มโต๊ะอาหารใหม่'
                    : 'แก้ไขข้อมูลโต๊ะ',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ชื่อเบอร์โต๊ะ *',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  hintText: 'เช่น T-1, PP',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (labelController.text.trim().isEmpty) return;
                    final data = {
                      'label': labelController.text.trim(),
                      'access_token': initialTableData == null
                          ? _generatePasscode()
                          : initialTableData['access_token'],
                    };
                    if (initialTableData != null) {
                      data['id'] = initialTableData['id'];
                    }
                    _saveTableData(data);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'บันทึก',
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
    final filteredTables = tables.where((t) {
      final String label = t['label']?.toString().toLowerCase() ?? '';
      return label.contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgLight,
      drawer: const AppSidebar(activeMenu: 'menu_management'),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_table',
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: _openTableFormModal,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.showTopBar)
              ProductsTopBar(
                activeTab: 'table',
                onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                onTabSelected: (tabId) {},
              ),
            _buildHeader(),
            Expanded(
              child: isLoading
                  ? const SuparPosLoading(fullScreen: false)
                  : errorMessage.isNotEmpty
                  ? Center(
                      child: Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : filteredTables.isEmpty
                  ? const Center(
                      child: Text(
                        'ไม่พบข้อมูลโต๊ะ',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : _isListView
                  ? _buildTableList(filteredTables)
                  : _buildTableGrid(filteredTables),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.table_restaurant_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'จัดการโต๊ะ',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          onChanged: (val) => setState(() => searchQuery = val),
                          decoration: const InputDecoration(
                            hintText: 'ค้นหาเบอร์โต๊ะ...',
                            hintStyle: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildInlineViewToggle(),
              if (_canUseNfc) ...[
                const SizedBox(width: 8),
                _buildNfcModeButton(),
              ],
            ],
          ),
          if (_canUseNfc && _nfcWriteMode) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.nfc_rounded, color: Color(0xFF059669), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'โหมดเขียน NFC เปิดอยู่: กดโต๊ะที่ต้องการ แล้วแตะแท็ก NFC',
                      style: TextStyle(
                        color: Color(0xFF047857),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableGrid(List<dynamic> filteredTables) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: _canUseNfc && _nfcWriteMode ? 178 : 166,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filteredTables.length,
      itemBuilder: (context, index) => _buildTableCard(filteredTables[index]),
    );
  }

  Widget _buildTableList(List<dynamic> filteredTables) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
      itemCount: filteredTables.length,
      itemBuilder: (context, index) =>
          _buildTableListTile(filteredTables[index]),
    );
  }

  Widget _buildTableCard(dynamic table) {
    final bool isAvailable = table['status'] == 'available';
    final String passcode = table['access_token'] ?? '----';

    return GestureDetector(
      onTap: _canUseNfc && _nfcWriteMode ? () => _writeTableToNfc(table) : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _nfcWriteMode
                ? const Color(0xFF10B981)
                : const Color(0xFFE2E8F0),
            width: _nfcWriteMode ? 1.4 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTableIdentity(table, isAvailable),
                _nfcWriteMode ? _buildNfcBadge() : _buildDeleteButton(table),
              ],
            ),
            Column(
              children: [
                const Text(
                  'PASSCODE',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  passcode,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
            _nfcWriteMode ? _buildTapToWriteHint() : _buildTableActions(table),
          ],
        ),
      ),
    );
  }

  Widget _buildTableListTile(dynamic table) {
    final bool isAvailable = table['status'] == 'available';
    final String passcode = table['access_token'] ?? '----';

    return GestureDetector(
      onTap: _canUseNfc && _nfcWriteMode ? () => _writeTableToNfc(table) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _nfcWriteMode
                ? const Color(0xFF10B981)
                : const Color(0xFFE2E8F0),
            width: _nfcWriteMode ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            _buildTableNumber(table),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'โต๊ะ ${table['label']?.toString() ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusText(isAvailable),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'PASSCODE',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        passcode,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),
                  if (_canUseNfc && _nfcWriteMode) ...[
                    const SizedBox(height: 8),
                    _buildTapToWriteHint(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _nfcWriteMode
                ? _buildNfcBadge()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRoundAction(
                        icon: Icons.refresh_rounded,
                        color: const Color(0xFF64748B),
                        onTap: () => _refreshPasscode(table),
                      ),
                      const SizedBox(height: 8),
                      _buildRoundAction(
                        icon: Icons.delete_outline,
                        color: const Color(0xFFEF4444),
                        onTap: () => _confirmDelete(table),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTapToWriteHint() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded, color: Color(0xFF059669), size: 15),
          SizedBox(width: 5),
          Text(
            'กดเพื่อเขียน NFC',
            style: TextStyle(
              color: Color(0xFF059669),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNfcBadge() {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: const BoxDecoration(
        color: Color(0xFFECFDF5),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.nfc_rounded, color: Color(0xFF059669), size: 18),
    );
  }

  Widget _buildTableIdentity(dynamic table, bool isAvailable) {
    return Row(
      children: [
        _buildTableNumber(table),
        const SizedBox(width: 8),
        _buildStatusText(isAvailable),
      ],
    );
  }

  Widget _buildTableNumber(dynamic table) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        table['label']?.toString() ?? '-',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildStatusText(bool isAvailable) {
    final color = isAvailable ? const Color(0xFF10B981) : Colors.red;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(
          isAvailable ? 'ว่าง' : 'ไม่ว่าง',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteButton(dynamic table) {
    return GestureDetector(
      onTap: () => _confirmDelete(table),
      child: const Icon(
        Icons.delete_outline,
        color: Color(0xFFCBD5E1),
        size: 20,
      ),
    );
  }

  Widget _buildTableActions(dynamic table) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('กำลังพัฒนาฟีเจอร์สแกน QR 🔜')),
              );
            },
            icon: const Icon(
              Icons.qr_code_2_rounded,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'QR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildRoundAction(
          icon: Icons.refresh_rounded,
          color: const Color(0xFF94A3B8),
          onTap: () => _refreshPasscode(table),
        ),
      ],
    );
  }

  Widget _buildRoundAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _buildInlineViewToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewToggleButton(
            icon: Icons.grid_view_rounded,
            selected: !_isListView,
            onTap: () => _setListView(false),
          ),
          _buildViewToggleButton(
            icon: Icons.view_agenda_rounded,
            selected: _isListView,
            onTap: () => _setListView(true),
          ),
        ],
      ),
    );
  }

  Widget _buildNfcModeButton() {
    if (!_canUseNfc) return const SizedBox.shrink();
    return Material(
      color: _nfcWriteMode ? const Color(0xFF10B981) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!_canUseNfc) return;
          setState(() => _nfcWriteMode = !_nfcWriteMode);
        },
        child: Container(
          height: 48,
          width: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _nfcWriteMode
                  ? const Color(0xFF10B981)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Icon(
            Icons.nfc_rounded,
            color: _nfcWriteMode ? Colors.white : const Color(0xFF64748B),
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildViewToggleButton({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFF0F172A) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 40,
          child: Icon(
            icon,
            color: selected ? Colors.white : const Color(0xFF64748B),
            size: 20,
          ),
        ),
      ),
    );
  }

  void _refreshPasscode(dynamic table) {
    final newData = {
      'id': table['id'],
      'label': table['label'],
      'access_token': _generatePasscode(),
    };
    _saveTableData(newData);
  }

  void _confirmDelete(dynamic table) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบโต๊ะ'),
        content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบโต๊ะนี้?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteTable(table['id'].toString());
            },
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
