import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../db/database_helper.dart';
import '../login.dart';
import '../services/storage_service.dart';
import '../services/profile_cache_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _dialogShown =
      false; // เอาไว้เช็คว่าเคยแสดง Dialog คำเชิญไปหรือยังในรอบนี้

  // กำหนดชุดสีหลักตาม Design
  final Color _bgColor = const Color(0xFFF4F7F9);
  final Color _primaryBlue = const Color(0xFF4361EE);
  final Color _darkNavy = const Color(0xFF0F172A);
  final Color _textSecondary = const Color(0xFF8A94A6);
  final Color _inputBgColor = const Color(0xFFF8FAFC);

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<Map<String, String>> _authHeaders() async => {
    ..._headers,
    'Authorization': 'Bearer ${await StorageService.getToken()}',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final brandId = await StorageService.getBrandId();
    try {
      final cached = await ProfileCacheService.load(brandId);
      if (cached != null && mounted) {
        _name.text = cached['full_name']?.toString() ?? '';
        _phone.text = cached['phone']?.toString() ?? '';
        setState(() {
          _profile = cached;
          _loading = false;
        });
      }
      final response = await http.get(
        Uri.parse(ApiService.profile),
        headers: await _authHeaders(),
      );
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || result['success'] != true) {
        throw result['error'] ?? 'โหลดโปรไฟล์ไม่สำเร็จ';
      }
      final profile = Map<String, dynamic>.from(result['profile']);
      final cachedProfile = await ProfileCacheService.save(brandId, profile);
      _name.text = profile['full_name']?.toString() ?? '';
      _phone.text = profile['phone']?.toString() ?? '';

      if (mounted) {
        setState(() => _profile = cachedProfile);
        // ถ้ามีคำเชิญ และยังไม่เคยโชว์ Dialog ในการโหลดครั้งนี้ ให้โชว์เลย
        if (profile['invited_brand'] != null && !_dialogShown) {
          _dialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showInvitationDialog();
          });
        }
      }
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) return;

    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    try {
      await _patch({
        'action': 'update',
        'full_name': _name.text,
        'phone': _phone.text,
        'avatar_url': _profile?['avatar_url'],
      });
      _message('บันทึกโปรไฟล์เรียบร้อยแล้ว');
      await _load();
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>> _patch(Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse(ApiService.profile),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 300 || result['success'] != true) {
      throw result['error'] ?? 'ทำรายการไม่สำเร็จ';
    }
    return result;
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (image == null) return;
    setState(() => _saving = true);
    try {
      final token = await StorageService.getToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiService.upload),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      final streamed = await request.send();
      final result =
          jsonDecode(await streamed.stream.bytesToString())
              as Map<String, dynamic>;
      if (streamed.statusCode >= 300 || result['success'] != true) {
        throw result['error'] ?? 'อัปโหลดรูปไม่สำเร็จ';
      }
      final url = result['url']?.toString();
      if (url == null || url.isEmpty) throw 'เซิร์ฟเวอร์ไม่ส่ง URL รูปกลับมา';
      await _patch({
        'action': 'update',
        'full_name': _name.text,
        'phone': _phone.text,
        'avatar_url': url,
      });
      await _load();
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _invitation(String action) async {
    Navigator.of(context).pop(); // ปิด Dialog ก่อน
    try {
      final result = await _patch({'action': action});
      if (result['requiresRelogin'] == true) {
        await _forceLogin(
          'เข้าร่วมร้านสำเร็จ กรุณาเข้าสู่ระบบใหม่เพื่อโหลดข้อมูลร้านค้า',
        );
      } else {
        _message(
          action == 'reject_invitation' ? 'ปฏิเสธคำเชิญแล้ว' : 'ทำรายการสำเร็จ',
        );
        await _load();
      }
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _leaveStore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ออกจากร้านนี้?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'แอปจะล้างข้อมูลออฟไลน์ทั้งหมด แล้วให้คุณเข้าสู่ระบบใหม่เพื่อความปลอดภัย',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกจากร้าน'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _patch({'action': 'leave_store'});
      await _forceLogin('ออกจากร้านแล้ว กรุณาเข้าสู่ระบบใหม่');
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _forceLogin(String message) async {
    await DatabaseHelper.instance.deleteLocalDatabase();
    await StorageService.clearAll();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: error ? Colors.redAccent : Colors.green.shade700,
      ),
    );
  }

  void _showInvitationDialog() {
    final invitedBrand = _profile?['invited_brand'] as Map<String, dynamic>?;
    if (invitedBrand == null) return;

    showDialog(
      context: context,
      barrierDismissible: false, // บังคับให้ต้องกดปุ่มหรือกด X
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header ของ Dialog: ปุ่ม X ปิด
                Align(
                  alignment: Alignment.topRight,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                // ไอคอนกระดิ่งตรงกลาง
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _primaryBlue,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryBlue.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'คำเชิญใหม่!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                      height: 1.5,
                      fontFamily: 'Kanit',
                    ),
                    children: [
                      const TextSpan(
                        text: 'คุณได้รับคำเชิญให้เข้าร่วมทำงานกับทีมร้าน\n',
                      ),
                      TextSpan(
                        text: '${invitedBrand['name']}\n',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          fontSize: 18,
                        ),
                      ),
                      const TextSpan(text: 'ในตำแหน่ง '),
                      TextSpan(
                        text: '${_profile?['invited_role'] ?? 'พนักงาน'}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // กล่องข้อมูลสรุป
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _inputBgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ร้านที่เชิญ',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          invitedBrand['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'สถานะ',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'รอการตอบรับ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // ปุ่มกด ปฏิเสธ / ยอมรับ
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _invitation('reject_invitation'),
                        child: Text(
                          'ปฏิเสธ',
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _invitation('accept_invitation'),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'ยอมรับ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: _textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    TextInputType type,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _textSecondary, size: 20),
        filled: true,
        fillColor: _inputBgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final avatar = profile?['avatar_url']?.toString();
    final localAvatarPath = profile?['local_avatar_path']?.toString();
    final localAvatar = localAvatarPath == null || localAvatarPath.isEmpty
        ? null
        : File(localAvatarPath);
    final invitedBrand = profile?['invited_brand'] as Map<String, dynamic>?;
    final ownBrand = profile?['own_brand'] as Map<String, dynamic>?;
    final currentBrand = profile?['current_brand'] as Map<String, dynamic>?;
    final String role = profile?['role']?.toString().toUpperCase() ?? 'OWNER';

    return Scaffold(
      backgroundColor: _bgColor,
      drawer: const AppSidebar(activeMenu: 'profile'),
      body: SafeArea(
        child: _loading
            ? const SuparPosLoading()
            : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Custom Header Area
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                // ไอคอนปุ่มเมนู (รูปคน) พร้อมแอนิเมชันกดและเปิด Sidebar
                                Builder(
                                  builder: (context) {
                                    return Material(
                                      color: _primaryBlue,
                                      borderRadius: BorderRadius.circular(12),
                                      clipBehavior: Clip
                                          .antiAlias, // ทำให้แอนิเมชันไม่ทะลุกรอบโค้ง
                                      child: InkWell(
                                        onTap: () {
                                          // เรียกเปิด Sidebar (Drawer)
                                          Scaffold.of(context).openDrawer();
                                        },
                                        splashColor: Colors.white.withOpacity(
                                          0.3,
                                        ), // สีตอนกด (Ripple)
                                        highlightColor: Colors.white
                                            .withOpacity(0.1), // สีตอนแตะค้าง
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          child: const Icon(
                                            Icons.person_outline,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'โปรไฟล์ของฉัน',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'จัดการข้อมูลส่วนตัว',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // ไอคอนกระดิ่งแจ้งเตือน
                            GestureDetector(
                              onTap: () {
                                if (invitedBrand != null) {
                                  _showInvitationDialog();
                                } else {
                                  _message('ไม่มีการแจ้งเตือนใหม่');
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      Icons.notifications_none,
                                      color: _darkNavy,
                                      size: 24,
                                    ),
                                    if (invitedBrand != null)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 30),

                        // Card ที่ 1: ข้อมูลโปรไฟล์ด้านบน
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // พื้นหลังส่วนบนของการ์ด
                              Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F4FA),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                              ),
                              // รูปโปรไฟล์
                              Transform.translate(
                                offset: const Offset(0, -45),
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: _saving ? null : _pickAvatar,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            child: CircleAvatar(
                                              radius: 45,
                                              backgroundColor:
                                                  Colors.grey.shade100,
                                              backgroundImage:
                                                  localAvatar != null &&
                                                      localAvatar.existsSync()
                                                  ? FileImage(localAvatar)
                                                  : avatar != null &&
                                                        avatar.isNotEmpty
                                                  ? NetworkImage(avatar)
                                                  : null,
                                              child:
                                                  (localAvatar == null ||
                                                          !localAvatar
                                                              .existsSync()) &&
                                                      (avatar == null ||
                                                          avatar.isEmpty)
                                                  ? Icon(
                                                      Icons.person,
                                                      size: 40,
                                                      color:
                                                          Colors.grey.shade400,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          // ถ้ากำลังโหลดให้แสดงหมุนๆ
                                          if (_saving)
                                            Container(
                                              width: 90,
                                              height: 90,
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  0.3,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Center(
                                                child:
                                                    CupertinoActivityIndicator(
                                                      color: Colors.white,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // ชื่อ
                                    Text(
                                      profile?['full_name']
                                                  ?.toString()
                                                  .isNotEmpty ==
                                              true
                                          ? profile!['full_name'].toString()
                                          : 'ผู้ใช้งาน',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // ป้าย Role
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFE0E7FF,
                                        ), // พื้นหลังป้ายสีฟ้าอ่อน
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          color: _primaryBlue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // อีเมล
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.mail_outline,
                                          size: 16,
                                          color: _textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          profile?['email']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Card ที่ 2: ฟอร์มแก้ไขข้อมูล
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTextFieldLabel('ชื่อ-นามสกุล'),
                              _buildTextField(
                                _name,
                                TextInputType.name,
                                Icons.person_outline,
                              ),

                              const SizedBox(height: 20),

                              _buildTextFieldLabel('เบอร์โทรศัพท์'),
                              _buildTextField(
                                _phone,
                                TextInputType.phone,
                                Icons.phone_outlined,
                              ),

                              const SizedBox(height: 32),

                              // ปุ่มบันทึกการเปลี่ยนแปลง (สีเข้ม Dark Navy)
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _darkNavy,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: _saving ? null : _save,
                                  child: _saving
                                      ? const CupertinoActivityIndicator(
                                          color: Colors.white,
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.save_outlined, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'บันทึกการเปลี่ยนแปลง',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ปุ่มออกจากร้าน (ถ้าจำเป็นต้องแสดง)
                        if (ownBrand != null &&
                            profile?['brand_id'] !=
                                profile?['own_brand_id']) ...[
                          const SizedBox(height: 30),
                          Center(
                            child: TextButton.icon(
                              onPressed: _leaveStore,
                              icon: const Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              label: Text(
                                'ออกจากร้าน ${currentBrand?['name'] ?? ''}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
