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
import '../widgets/bouncing_card.dart';

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
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'N',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Arial',
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'รอรับสัญญาณ NFC',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'นำโทรศัพท์ไปแตะที่สติ๊กเกอร์\nสำหรับโต๊ะ ${table['label'] ?? '-'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      await _nfcChannel.invokeMethod<bool>('cancelNfcWrite');
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'ยกเลิก',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    final String initialLabel = initialTableData == null ? '' : initialTableData['label'] ?? '';
    final labelController = TextEditingController(text: initialLabel);

    bool hasUnsavedChanges() {
      return labelController.text.trim() != initialLabel.trim();
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        Future<void> requestClose() async {
          if (!hasUnsavedChanges()) {
            Navigator.pop(dialogContext);
            return;
          }
          
          final choice = await showDialog<String>(
            context: dialogContext,
            barrierColor: Colors.black.withOpacity(0.35),
            builder: (ctx) => Dialog(
              elevation: 0,
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade600,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ละทิ้งการแก้ไข?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ข้อมูลที่คุณกรอกไว้จะไม่ถูกบันทึก\nคุณแน่ใจหรือไม่ที่จะละทิ้งการแก้ไขนี้?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx, 'cancel'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'แก้ไขต่อ',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, 'discard'),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: Colors.red.shade500,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'ละทิ้ง',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          if (choice == 'discard' && dialogContext.mounted) {
            Navigator.pop(dialogContext);
          }
        }

        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (!didPop) requestClose();
          },
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    initialTableData == null
                        ? 'เพิ่มโต๊ะอาหารใหม่'
                        : 'แก้ไขข้อมูลโต๊ะ',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'ชื่อเบอร์โต๊ะ *',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: labelController,
                    decoration: InputDecoration(
                      hintText: 'เช่น T-1, PP',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      if (initialTableData != null) ...[
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFFFEE2E2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _confirmDelete(initialTableData);
                            },
                            child: const Text(
                              'ลบโต๊ะ',
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: const Color(0xFF0F172A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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
                            Navigator.pop(dialogContext);
                          },
                          child: Text(
                            initialTableData == null ? 'บันทึกโต๊ะ' : 'บันทึกการแก้ไข',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
      floatingActionButton: SizedBox(
        width: 44,
        height: 44,
        child: FloatingActionButton(
          heroTag: 'add_table',
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onPressed: _openTableFormModal,
          child: const Icon(Icons.add_rounded, size: 26),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              // แถบค้นหาตามดีไซน์ master_product_screen
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Color(0xFF94A3B8), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (val) => setState(() => searchQuery = val),
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                            hintText: 'ค้นหาเบอร์โต๊ะ...',
                            hintStyle: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
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
                  Text(
                    'N',
                    style: TextStyle(
                      color: Color(0xFF059669),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Arial',
                    ),
                  ),
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
        maxCrossAxisExtent: 150, // โมดูลเล็กเป็นสี่เหลี่ยมจัตุรัส
        mainAxisExtent: _canUseNfc && _nfcWriteMode ? 120 : 96, // ปรับความสูงลงเมื่อไม่มีปุ่ม
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
    return Container(
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
      child: BouncingCard(
        onTap: _canUseNfc && _nfcWriteMode
            ? () => _writeTableToNfc(table)
            : () => _openTableFormModal(initialTableData: table),
        glowColor: _nfcWriteMode ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _canUseNfc && _nfcWriteMode
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildTableNumber(table),
                        _buildNfcBadge(),
                      ],
                    ),
                    _buildTapToWriteHint(),
                  ],
                )
              : Center(
                  child: _buildTableNumber(table, large: true),
                ),
        ),
      ),
    );
  }

  Widget _buildTableListTile(dynamic table) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: BouncingCard(
        onTap: _canUseNfc && _nfcWriteMode
            ? () => _writeTableToNfc(table)
            : () => _openTableFormModal(initialTableData: table),
        glowColor: _nfcWriteMode ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildTableNumber(table),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    if (_canUseNfc && _nfcWriteMode) ...[
                      const SizedBox(height: 8),
                      _buildTapToWriteHint(),
                    ],
                  ],
                ),
              ),
              if (_canUseNfc && _nfcWriteMode) ...[
                const SizedBox(width: 12),
                _buildNfcBadge(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTapToWriteHint() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, color: Color(0xFF059669), size: 14),
            SizedBox(width: 4),
            Text(
              'แตะเขียน NFC',
              style: TextStyle(
                color: Color(0xFF059669),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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
      child: const Text(
        'N',
        style: TextStyle(
          color: Color(0xFF059669),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          fontFamily: 'Arial',
        ),
      ),
    );
  }

  // _buildTableIdentity removed

  Widget _buildTableNumber(dynamic table, {bool large = false}) {
    return Container(
      width: large ? 60 : 42,
      height: large ? 60 : 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(large ? 20 : 12),
      ),
      child: Text(
        table['label']?.toString() ?? '-',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: large ? 20 : 16,
        ),
      ),
    );
  }

  Widget _buildInlineViewToggle() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!_canUseNfc) return;
          setState(() => _nfcWriteMode = !_nfcWriteMode);
        },
        child: Container(
          height: 38,
          width: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _nfcWriteMode
                  ? const Color(0xFF10B981)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'N',
            style: TextStyle(
              color: _nfcWriteMode ? Colors.white : const Color(0xFF64748B),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontFamily: 'Arial',
            ),
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
