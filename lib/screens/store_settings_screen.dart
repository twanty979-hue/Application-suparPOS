// lib/screens/store_settings_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:confetti/confetti.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 ใช้ตู้เซฟ
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_navigation_loader.dart';
import '../widgets/suparpos_loading.dart';
import 'pos_options_settings_screen.dart';
import 'receipt_settings_screen.dart';
import 'payment_history_screen.dart';
import 'staff_management_screen.dart';
import '../widgets/store_settings/package_tab.dart';

class StoreSettingsScreen extends StatefulWidget {
  final String brandId;
  final int initialTab;

  const StoreSettingsScreen({super.key, required this.brandId, this.initialTab = 0});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  static const _ink = Color(0xFF292524); // ดำอมน้ำตาล
  static const _surface = Color(0xFFFAF9F6); // ขาวไข่
  static const _bg = Color(0xFFEDE9E3); // พื้นหลังขาวไข่เข้ม

  // สีสดใสสำหรับ Icon และ Glow Effect
  static const _vibrantBlue = Color(0xFF3B82F6);
  static const _vibrantOrange = Color(0xFFF59E0B);
  static const _vibrantGreen = Color(0xFF10B981);
  static const _vibrantViolet = Color(0xFF6366F1);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  Uint8List? _pendingLogoBytes;
  bool _isOwner = false;
  int _activeTab = 0;
  String _currentPlan = 'FREE';
  DateTime? _planExpiryDate;
  int _coins = 0;

  String? _accessToken;
  String? _logoUrl;
  String? _localLogoPath;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _promptpayController = TextEditingController();

  String _initialName = '';
  String _initialPhone = '';
  String _initialPromptpay = '';
  String? _initialLogoUrl;

  bool get _hasUnsavedChanges => _pendingLogoBytes != null || 
      _nameController.text != _initialName ||
      _phoneController.text != _initialPhone ||
      _promptpayController.text != _initialPromptpay ||
      _logoUrl != _initialLogoUrl;

  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _loadSessionAndFetch();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _promptpayController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionAndFetch() async {
    try {
      _accessToken = await StorageService.getToken(); // ดึงจากตู้เซฟ

      if (_accessToken != null) {
        await _fetchSettings();
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่พบการล็อกอิน กรุณาเข้าสู่ระบบใหม่'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSettings() async {
    try {
      final url = ApiService.settings;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      );

      
      // Upload pending logo if exists
      if (_pendingLogoBytes != null) {
        setState(() => _isUploadingLogo = true);
        final request = http.MultipartRequest('POST', Uri.parse('/logo'))
          ..headers['Authorization'] = 'Bearer '
          ..files.add(http.MultipartFile.fromBytes('file', _pendingLogoBytes!, filename: 'logo.webp'));
          
        final streamedResponse = await request.send();
        final responseBody = await streamedResponse.stream.bytesToString();
        final responseData = responseBody.isNotEmpty ? jsonDecode(responseBody) as Map<String, dynamic> : <String, dynamic>{};
        
        if (streamedResponse.statusCode == 200 && responseData['success'] == true) {
          // Delete old cache and save new one
          await _saveLocalLogoBytes(_pendingLogoBytes!);
          if (mounted) {
            setState(() {
              _logoUrl = responseData['logo_url']?.toString();
              _initialLogoUrl = _logoUrl;
              _pendingLogoBytes = null;
            });
          }
        } else {
          throw responseData['error'] ?? 'อัปโหลดโลโก้ไม่สำเร็จ';
        }
        setState(() => _isUploadingLogo = false);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final brand = data['brand'];
          if (mounted) {
            setState(() {
              _nameController.text = brand['name'] ?? '';
              _phoneController.text = brand['phone'] ?? '';
              _promptpayController.text = brand['promptpay_number'] ?? '';
              _logoUrl = brand['logo_url']?.toString();
              _isOwner = data['isOwner'] ?? false;
              _currentPlan = brand['plan'] ?? 'free';
              _coins = brand['coins'] ?? 0;

              String? expiryString;
              switch (_currentPlan.toLowerCase()) {
                case 'ultimate':
                  expiryString = brand['expiry_ultimate'];
                  break;
                case 'pro':
                  expiryString = brand['expiry_pro'];
                  break;
                case 'basic':
                  expiryString = brand['expiry_basic'];
                  break;
              }

              if (expiryString != null) {
                _planExpiryDate = DateTime.tryParse(expiryString);
              }
              
              _initialName = _nameController.text;
              _initialPhone = _phoneController.text;
              _initialPromptpay = _promptpayController.text;
              _initialLogoUrl = _logoUrl;
              
              _isLoading = false;
            });
            unawaited(_cacheLogoFromUrl(_logoUrl));
          }
        }
      } else if (response.statusCode == 401) {
        throw "เซสชันหมดอายุ กรุณาล็อกอินใหม่ (401)";
      } else {
        throw "Server ตอบกลับ: ${response.statusCode}";
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ดึงข้อมูลล้มเหลว: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onUpgradeSuccess() async {
    await _fetchSettings();
    _confettiController.play();
  }

  Future<File> _localLogoFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final logoDir = Directory(
      '${appDir.path}${Platform.pathSeparator}brand_assets',
    );
    if (!await logoDir.exists()) {
      await logoDir.create(recursive: true);
    }
    return File(
      '${logoDir.path}${Platform.pathSeparator}logo_${widget.brandId}.webp',
    );
  }

  Future<void> _saveLocalLogoBytes(List<int> bytes) async {
    if (bytes.isEmpty) return;
    final file = await _localLogoFile();
    await file.writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_logo_path_${widget.brandId}', file.path);
    if (mounted) setState(() => _localLogoPath = file.path);
  }

  Future<void> _cacheLogoFromUrl(String? logoUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedPath = prefs.getString('store_logo_path_${widget.brandId}');
    if (cachedPath != null && await File(cachedPath).exists()) {
      if (mounted) setState(() => _localLogoPath = cachedPath);
      return;
    }

    final cleanUrl = logoUrl?.trim() ?? '';
    if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) return;

    try {
      final response = await http
          .get(Uri.parse(cleanUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
      await _saveLocalLogoBytes(response.bodyBytes);
    } catch (_) {}
  }

  Future<CroppedFile?> _cropLogoImage(String sourcePath) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'ครอปโลโก้ร้าน (1:1)',
          toolbarColor: _ink,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: _vibrantBlue,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'ครอปโลโก้ร้าน (1:1)',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 520, height: 520),
        ),
      ],
    );
  }

  
  Future<void> _pickLogo() async {
    if (!_isOwner || _isUploadingLogo) return;

    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null) return;

      final croppedFile = await _cropLogoImage(pickedFile.path);
      if (croppedFile == null) return;

      final webpBytes = await FlutterImageCompress.compressWithFile(
        croppedFile.path,
        format: CompressFormat.webp,
        quality: 85,
        minWidth: 1024,
        minHeight: 1024,
      );
      if (webpBytes == null || webpBytes.isEmpty) {
        throw 'แปลงโลโก้เป็น WebP ไม่สำเร็จ';
      }

      if (mounted) {
        setState(() {
          _pendingLogoBytes = webpBytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ: '),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

Future<void> _saveSettings() async {
    if (!_isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('คุณไม่มีสิทธิ์แก้ไขข้อมูลร้าน'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final url = ApiService.settings;
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'name': _nameController.text,
          'phone': _phoneController.text,
          'promptpay_number': _promptpayController.text,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _initialName = _nameController.text;
            _initialPhone = _phoneController.text;
            _initialPromptpay = _promptpayController.text;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกข้อมูลเรียบร้อย'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw "บันทึกข้อมูลล้มเหลว Status: ${response.statusCode}";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("เกิดข้อผิดพลาด: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        // 🌟 เพิ่มเงาฟุ้งๆ นุ่มๆ แบบ Modern Web ให้ดูแพง
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.02),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCardTitle({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    bool enabled = true,
    String? hintText,
    IconData? prefixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8), // ลดระยะห่างให้ชิดขึ้นอีก
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11, // เล็กลงอีก
              fontWeight: FontWeight.w800,
              color: Color(0xFF292524),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: enabled ? _surface : const Color(0xFFEDE9E3),
              borderRadius: BorderRadius.circular(8), // โค้งน้อยลงอีก
              border: Border.all(
                color: const Color(0xFFDCD6CB),
                width: 1,
              ),
            ),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              enabled: enabled,
              style: const TextStyle(
                color: Color(0xFF292524),
                fontSize: 12, // เล็กลงอีก
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true, // ทำให้ช่องกรอกเล็กลงได้อีก
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                prefixIcon: prefixIcon == null
                    ? null
                    : Icon(
                        prefixIcon,
                        color: const Color(0xFF64748B),
                        size: 14, // เล็กลงอีก
                      ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8, // บีบให้บางลง
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFEDE9E3),
        border: Border(bottom: BorderSide(color: Color(0xFFDCD6CB))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A0B1730),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Material(
              color: const Color(0xFF292524),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => Scaffold.of(context).openDrawer(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A0B1730),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.menu,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ตั้งค่า',
                style: TextStyle(
                  color: Color(0xFF292524),
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  height: 0.95,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 35,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFF8D986)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0FF59E0B),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'lib/assets/cion.png',
                    width: 19,
                    height: 19,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.monetization_on,
                      color: Color(0xFFF59E0B),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    NumberFormat('#,###').format(_coins),
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0xFF292524),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: _isSaving ? null : _saveSettings,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9E3), // สีเทาอ่อนๆ (เข้มขึ้นจากเดิม)
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _buildTabButton(0, Icons.storefront_outlined, 'ข้อมูลร้าน'),
          _buildTabButton(1, Icons.workspace_premium_outlined, 'แพ็กเกจ'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: double.infinity,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF292524) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            // 🌟 แท็บที่ถูกเลือกจะลอยขึ้นมาอย่างสวยงาม
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : const Color(0xFF64748B),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWithLargeLoader(Widget page) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => SuparPosNavigationLoader(child: page),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        transitionsBuilder: (_, animation, __, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.025, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickActionMenu() {
    final plan = _currentPlan.trim().toLowerCase();
    final isPro = plan == 'pro' || plan == 'ultimate';

    return Row(
      children: [
        Expanded(
          child: _buildMenuButton(
            icon: Icons.point_of_sale_rounded,
            color: const Color(0xFF1E293B), // น้ำเงินหม่นเข้ม (Slate)
            bgColor: Colors.white, // พื้นหลังขาวสะอาด
            title: 'คิดเงิน',
            onTap: () => _openWithLargeLoader(
              PosOptionsSettingsScreen(brandId: widget.brandId),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMenuButton(
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF78350F), // ส้มน้ำตาลเข้ม (Amber/Brown)
            bgColor: Colors.white,
            title: 'ใบเสร็จ',
            onTap: () => _openWithLargeLoader(
              ReceiptSettingsScreen(brandId: widget.brandId),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMenuButton(
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF14532D), // เขียวหม่นเข้ม (Forest Green)
            bgColor: Colors.white,
            title: 'ชำระเงิน',
            onTap: () => _openWithLargeLoader(const PaymentHistoryScreen()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMenuButton(
            icon: Icons.groups_rounded,
            color: const Color(0xFF312E81), // ม่วงหม่นเข้ม (Indigo)
            bgColor: Colors.white,
            title: 'พนักงาน',
            onTap: _openStaffManagement,
            isLocked: !isPro,
          ),
        ),
      ],
    );
  }

  Future<void> _openStaffManagement() async {
    final plan = _currentPlan.trim().toLowerCase();
    if (plan == 'pro' || plan == 'ultimate') {
      await _openWithLargeLoader(const StaffManagementScreen());
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.workspace_premium_rounded,
          color: Color(0xFF7C3AED),
          size: 42,
        ),
        title: const Text(
          'สำหรับแพลน Pro ขึ้นไป',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'ฟีเจอร์จัดการพนักงานใช้ได้กับแพลน Pro และ Ultimate ส่วนแพลน Free และ Basic ยังไม่รองรับครับ',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'เข้าใจแล้ว',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required VoidCallback onTap,
    bool isLocked = false,
  }) {
    final activeColor = isLocked ? const Color(0xFF94A3B8) : color;
    final activeBg = isLocked ? const Color(0xFFE2E8F0) : bgColor;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9E3), // ขาวไข่เข้ม
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCD6CB)),
        // 🌟 เงาบางๆ สะอาดๆ แบบมินิมอล เข้ากับตีม
        boxShadow: isLocked ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: activeBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, color: activeColor, size: 20),
                    ),
                    if (isLocked)
                      Positioned(
                        bottom: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF292524),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFEDE9E3), width: 1.5),
                          ),
                          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  style: TextStyle(
                    color: isLocked ? const Color(0xFF94A3B8) : _ink,
                    fontSize: 10.5,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreTab() {
    return Column(
      key: const ValueKey('store-tab'),
      children: [
        _buildQuickActionMenu(),
        const SizedBox(height: 24),
        _buildStoreInfoCard(),
      ],
    );
  }

  Widget _buildStoreInfoCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardTitle(
            icon: Icons.storefront_outlined,
            iconColor: const Color(0xFF292524), // ดำอมน้ำตาล
            iconBg: const Color(0xFFE8E4DD),
            title: 'ข้อมูลร้านค้า',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogoPicker(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _buildTextField('ชื่อร้านค้า *', _nameController, enabled: _isOwner),
                    _buildTextField(
                      'เบอร์โทรศัพท์ติดต่อ',
                      _phoneController,
                      hintText: '08x-xxx-xxxx',
                      prefixIcon: Icons.phone_outlined,
                      enabled: _isOwner,
                    ),
                    _buildTextField(
                      'PromptPay ID (เบอร์โทร / เลขบัตร)',
                      _promptpayController,
                      enabled: _isOwner,
                      prefixIcon: Icons.credit_card_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoPicker() {
    final localLogo = _localLogoPath == null ? null : File(_localLogoPath!);
    final hasLocalLogo = localLogo != null && localLogo.existsSync();
    final hasLogo =
        hasLocalLogo || (_logoUrl != null && _logoUrl!.trim().isNotEmpty);

    return GestureDetector(
      onTap: _isOwner && !_isUploadingLogo ? _pickLogo : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9E3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCD6CB)),
            ),
            child: _isUploadingLogo
                ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF292524))))
                : _pendingLogoBytes != null
                    ? Image.memory(_pendingLogoBytes!, fit: BoxFit.cover)
                    : hasLogo
                        ? hasLocalLogo
                              ? Image.file(localLogo, fit: BoxFit.cover)
                              : Image.network(
                                  _logoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'lib/assets/app_logo.png',
                                    fit: BoxFit.cover,
                                  ),
                                )
                        : Image.asset(
                            'lib/assets/app_logo.png',
                            fit: BoxFit.cover,
                          ),
          ),
          if (_isOwner)
            Positioned(
              bottom: -4,
              left: -4, // ดินสอตรงมุมล่างซ้ายตามที่ขอ
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF292524),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFAF9F6), width: 1.5),
                ),
                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hasUnsavedChanges) {
          Navigator.of(context).pop();
          return;
        }
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ยังไม่ได้บันทึกข้อมูล', style: TextStyle(fontWeight: FontWeight.bold, color: _ink)),
            content: const Text('คุณมีการเปลี่ยนแปลงที่ยังไม่ได้บันทึก ต้องการบันทึกก่อนออกจากหน้านี้หรือไม่?', style: TextStyle(color: _ink)),
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('ทิ้งการเปลี่ยนแปลง', style: TextStyle(color: Colors.red)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('บันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _saveSettings();
          if (mounted) Navigator.of(context).pop();
        } else if (confirm == false) {
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: _bg, // ใช้สีเทาขาว เพื่อดันให้การ์ดสีขาวดูลอยเด่น
      drawer: const AppSidebar(activeMenu: 'settings'),
      body: Stack(
        children: [
          SafeArea(
            child: Builder(
              builder: (context) {
                return Column(
                  children: [
                    _buildHeader(context),
                    Expanded(
                      child: _isLoading
                          ? const SuparPosLoading(fullScreen: false)
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                24,
                                16,
                                40,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 620,
                                  ),
                                  child: Column(
                                    children: [
                                      _buildTabs(),
                                      const SizedBox(height: 24),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        child: _activeTab == 0
                                            ? _buildStoreTab()
                                            : PackageTab(
                                                currentPlan: _currentPlan,
                                                planExpiryDate: _planExpiryDate,
                                                onUpgradeSuccess:
                                                    _onUpgradeSuccess,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.amber, Colors.orange, Colors.yellow],
              createParticlePath: drawStar,
              gravity: 0.3,
              emissionFrequency: 0.05,
              numberOfParticles: 40,
            ),
          ),
        ],
      ),
    ));
  }

  Path drawStar(Size size) {
    double degToRad(double deg) => deg * (3.1415926535897932 / 180.0);
    const numberOfPoints = 5;
    final halfWidth = size.width / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(360);
    path.moveTo(size.width, halfWidth);
    for (double step = 0; step < fullAngle; step += degreesPerStep) {
      path.lineTo(
        halfWidth + externalRadius * 1.0,
        halfWidth + externalRadius * 0,
      );
      path.addOval(
        Rect.fromCircle(
          center: Offset(halfWidth, halfWidth),
          radius: halfWidth,
        ),
      );
    }
    path.close();
    return path;
  }
}

