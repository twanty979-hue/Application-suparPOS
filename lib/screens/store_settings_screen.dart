// lib/screens/store_settings_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
  static const _ink = Color(0xFF0F172A); // Slate 900
  static const _surface = Colors.white;
  static const _bg = Color(
    0xFFF8FAFC,
  ); // พื้นหลังรวมสีเทาขาวสว่างๆ ให้การ์ดสีขาวดูลอย

  // สีสดใสสำหรับ Icon และ Glow Effect
  static const _vibrantBlue = Color(0xFF3B82F6);
  static const _vibrantOrange = Color(0xFFF59E0B);
  static const _vibrantGreen = Color(0xFF10B981);
  static const _vibrantViolet = Color(0xFF6366F1);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
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

  Future<void> _pickAndUploadLogo() async {
    if (!_isOwner || _isUploadingLogo) return;

    setState(() => _isUploadingLogo = true);
    var localLogoSaved = false;
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

      await _saveLocalLogoBytes(webpBytes);
      localLogoSaved = true;

      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('${ApiService.settings}/logo'),
            )
            ..headers['Authorization'] = 'Bearer $_accessToken'
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                webpBytes,
                filename: 'logo.webp',
              ),
            );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = responseBody.isNotEmpty
          ? jsonDecode(responseBody) as Map<String, dynamic>
          : <String, dynamic>{};

      if (streamedResponse.statusCode != 200 ||
          responseData['success'] != true) {
        debugPrint(
          '[Store Logo] Cloud upload failed status=${streamedResponse.statusCode} body=$responseBody',
        );
        throw responseData['error'] ??
            'อัปโหลดโลโก้ไม่สำเร็จ (${streamedResponse.statusCode})';
      }

      if (mounted) {
        setState(() => _logoUrl = responseData['logo_url']?.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตโลโก้ร้านเรียบร้อยแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (localLogoSaved) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'บันทึกโลโก้ในเครื่องแล้ว แต่ซิงก์ขึ้น Cloud ยังไม่สำเร็จ: $e',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('อัปโหลดโลโก้ไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
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
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          // 🌟 ใส่เงาให้ช่องกรอกข้อความ เพื่อให้ดูมีมิติ ไม่แบนราบ
          Container(
            decoration: BoxDecoration(
              color: enabled ? Colors.white : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              enabled: enabled,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: prefixIcon == null
                    ? null
                    : Icon(
                        prefixIcon,
                        color: const Color(0xFF64748B),
                        size: 22,
                      ),
                filled: true,
                fillColor: Colors
                    .transparent, // ใช้สีโปร่งใส เพราะเราใช้สีจาก Container แทน
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                // 🌟 เส้นขอบบางเฉียบ เพื่อความพรีเมียม
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFFE2E8F0),
                    width: 0.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFFE2E8F0),
                    width: 0.5,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: _vibrantBlue, width: 2.0),
                ),
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
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        12,
        compact ? 12 : 16,
        12,
      ),
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Scaffold.of(context).openDrawer(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 14),
          const Expanded(
            child: Text(
              '',
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: compact ? 92 : 150),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 9 : 14,
                vertical: 8,
              ),
              margin: EdgeInsets.only(right: compact ? 8 : 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.paid_rounded,
                      color: Color(0xFFF59E0B),
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      NumberFormat('#,###').format(_coins),
                      style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: compact ? 42 : null,
            height: 42,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                elevation: 3,
                shadowColor: _ink.withOpacity(0.25),
                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded, size: 19),
                        if (!compact) ...[
                          const SizedBox(width: 7),
                          const Text(
                            'บันทึก',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // สีเทาอ่อนๆ
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
            color: isActive ? Colors.white : Colors.transparent,
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
                color: isActive ? _vibrantBlue : const Color(0xFF64748B),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? _ink : const Color(0xFF64748B),
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
    return Row(
      children: [
        Expanded(
          child: _buildMenuButton(
            icon: Icons.point_of_sale_rounded,
            color: _vibrantBlue,
            bgColor: const Color(0xFFEFF6FF),
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
            color: _vibrantOrange,
            bgColor: const Color(0xFFFEF3C7),
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
            color: _vibrantGreen,
            bgColor: const Color(0xFFD1FAE5),
            title: 'ชำระเงิน',
            onTap: () => _openWithLargeLoader(const PaymentHistoryScreen()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMenuButton(
            icon: Icons.groups_rounded,
            color: _vibrantViolet,
            bgColor: const Color(0xFFEEF2FF),
            title: 'พนักงาน',
            onTap: _openStaffManagement,
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        // 🌟 Glowing Shadow! เงาสะท้อนสีเดียวกับปุ่มแบบบางๆ (สไตล์เว็บ Vercel/Stripe)
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 6),
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
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
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
            iconColor: _vibrantBlue,
            iconBg: const Color(0xFFEFF6FF),
            title: 'ข้อมูลร้านค้า',
          ),
          const SizedBox(height: 24),
          _buildLogoPicker(),
          const SizedBox(height: 24),
          _buildTextField('ชื่อร้านค้า *', _nameController, enabled: _isOwner),
          _buildTextField(
            'เบอร์โทรศัพท์ติดต่อ',
            _phoneController,
            hintText: '08x-xxx-xxxx',
            prefixIcon: Icons.phone_outlined,
            enabled: _isOwner,
          ),

          const Divider(color: Color(0xFFF1F5F9), height: 40, thickness: 1.5),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'รับชำระเงิน (PromptPay)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF6EE7B7),
                    width: 1.5,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF059669),
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'ปลอดภัย',
                      style: TextStyle(
                        color: Color(0xFF059669),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField(
            'PromptPay ID (เบอร์โทร / เลขบัตร)',
            _promptpayController,
            enabled: _isOwner,
            prefixIcon: Icons.credit_card_outlined,
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: hasLogo
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
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'โลโก้ร้าน',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'รองรับ JPG, PNG และ WebP ขนาดไม่เกิน 5 MB',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isOwner && !_isUploadingLogo
                    ? _pickAndUploadLogo
                    : null,
                icon: _isUploadingLogo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined, size: 18),
                label: Text(
                  _isUploadingLogo
                      ? 'กำลังอัปโหลด...'
                      : hasLogo
                      ? 'เปลี่ยนโลโก้'
                      : 'เลือกรูปโลโก้',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
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
