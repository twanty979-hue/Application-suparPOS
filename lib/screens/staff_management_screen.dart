import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import '../api_service.dart';
import '../services/storage_service.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<dynamic> _staff = [];
  bool _loading = true;
  String _brandId = '';

  // กำหนดชุดสีหลักตาม Design เดียวกับ Profile
  final Color _bgColor = const Color(0xFFF4F7F9);
  final Color _primaryBlue = const Color(0xFF4361EE);
  final Color _textSecondary = const Color(0xFF8A94A6);

  Future<Map<String, String>> _headers() async => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await StorageService.getToken()}',
  };

  @override
  void initState() {
    super.initState();
    _verifyPlanAccess();
  }

  Future<void> _verifyPlanAccess() async {
    try {
      final response = await http.get(
        Uri.parse(ApiService.settings),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        await _denyAccess(
          'ไม่สามารถตรวจสอบแพลนของร้านได้ กรุณาลองใหม่อีกครั้ง',
        );
        return;
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final brand = result['brand'] is Map
          ? Map<String, dynamic>.from(result['brand'] as Map)
          : result;
      final plan = (brand['plan'] ?? 'free').toString().trim().toLowerCase();
      if (plan != 'pro' && plan != 'ultimate') {
        await _denyAccess(
          'ฟีเจอร์จัดการพนักงานใช้ได้กับแพลน Pro และ Ultimate ส่วนแพลน Free และ Basic ยังไม่รองรับครับ',
        );
        return;
      }

      await _load();
    } catch (_) {
      await _denyAccess('ไม่สามารถตรวจสอบแพลนของร้านได้ กรุณาลองใหม่อีกครั้ง');
    }
  }

  Future<void> _denyAccess(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
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
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.5),
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
              'กลับหน้าตั้งค่า',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final currentBrandId = await StorageService.getBrandId();
      final response = await http.get(
        Uri.parse(ApiService.staff),
        headers: await _headers(),
      );
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || result['success'] != true) {
        throw result['error'] ?? 'โหลดรายชื่อไม่สำเร็จ';
      }
      if (mounted) {
        setState(() {
          _brandId = currentBrandId;
          _staff = result['data'] ?? [];
        });
      }
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasStoreAccess(Map<String, dynamic> member) {
    if (member['has_store_access'] == true) return true;

    final status = member['status']?.toString().trim().toLowerCase();
    if (status == 'active' || status == 'accepted' || status == 'joined') {
      return true;
    }

    // รองรับ API รุ่นเดิมและข้อมูลสมาชิกเก่าที่ is_joined อาจยังไม่ได้อัปเดต
    final memberBrandId = member['brand_id']?.toString() ?? '';
    final invitedBrandId = member['invited_brand_id']?.toString() ?? '';
    return _brandId.isNotEmpty &&
        memberBrandId == _brandId &&
        invitedBrandId != _brandId;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(ApiService.staff),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 300 || result['success'] != true) {
      throw result['error'] ?? 'ทำรายการไม่สำเร็จ';
    }
    return result;
  }

  Future<void> _inviteDialog() async {
    final email = TextEditingController();
    String role = 'staff';
    Map<String, dynamic>? found;
    bool busy = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'เชิญพนักงาน',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(dialogContext),
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
                  ],
                ),
                const SizedBox(height: 20),

                // ช่องค้นหา
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ใส่อีเมลพนักงาน',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: _textSecondary,
                      size: 20,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),

                // ปุ่มค้นหา
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: _primaryBlue.withOpacity(0.3)),
                    ),
                    onPressed: busy
                        ? null
                        : () async {
                            setDialogState(() => busy = true);
                            try {
                              final result = await _post({
                                'action': 'search',
                                'email': email.text.trim(),
                              });
                              setDialogState(
                                () => found = Map<String, dynamic>.from(
                                  result['profile'],
                                ),
                              );
                            } catch (error) {
                              _message(error.toString(), error: true);
                            } finally {
                              setDialogState(() => busy = false);
                            }
                          },
                    icon: Icon(Icons.search, size: 18, color: _primaryBlue),
                    label: Text(
                      'ค้นหาบัญชี',
                      style: TextStyle(
                        color: _primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                if (found != null) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ข้อมูลที่ค้นพบ
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          backgroundImage: found!['avatar_url'] != null
                              ? NetworkImage(found!['avatar_url'])
                              : null,
                          child: found!['avatar_url'] == null
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                found!['full_name'] ?? 'ยังไม่ระบุชื่อ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                found!['email'] ?? '',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // เลือกตำแหน่ง
                  Text(
                    'ระบุตำแหน่ง',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: _textSecondary,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'staff',
                        child: Text(
                          'พนักงานทั่วไป',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'cashier',
                        child: Text(
                          'แคชเชียร์',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'chef',
                        child: Text(
                          'พ่อครัว / แม่ครัว',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => role = value ?? 'staff'),
                  ),
                  const SizedBox(height: 24),

                  // ปุ่มยืนยันส่งคำเชิญ
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: busy
                          ? null
                          : () async {
                              setDialogState(() => busy = true);
                              try {
                                await _post({
                                  'action': 'invite',
                                  'email': email.text.trim(),
                                  'role': role,
                                });
                                if (dialogContext.mounted)
                                  Navigator.pop(dialogContext);
                                _message('ส่งคำเชิญเรียบร้อยแล้ว');
                                await _load();
                              } catch (error) {
                                _message(error.toString(), error: true);
                                setDialogState(() => busy = false);
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CupertinoActivityIndicator(
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'ส่งคำเชิญเข้าร่วมร้าน',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    email.dispose();
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final isPending = !_hasStoreAccess(member);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isPending ? 'ยกเลิกคำเชิญ?' : 'นำพนักงานออก?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${member['full_name'] ?? member['email']}\nจะไม่สามารถเข้าถึงข้อมูลร้านนี้ได้อีก',
          style: const TextStyle(height: 1.5),
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
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final request = http.Request('DELETE', Uri.parse(ApiService.staff));
      request.headers.addAll(await _headers());
      request.body = jsonEncode({'employeeId': member['id']});
      final response = await http.Response.fromStream(await request.send());
      final result = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 300 || result['success'] != true) {
        throw result['error'] ?? 'ลบไม่สำเร็จ';
      }
      _message(isPending ? 'ยกเลิกคำเชิญแล้ว' : 'นำพนักงานออกแล้ว');
      await _load();
    } catch (error) {
      _message(error.toString(), error: true);
    }
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

  String _role(String? role) => role == 'cashier'
      ? 'แคชเชียร์'
      : role == 'chef'
      ? 'ครัว'
      : 'พนักงาน';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header แบบเดียวกับ Profile
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Material(
                        color: _primaryBlue,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          splashColor: Colors.white.withOpacity(0.3),
                          highlightColor: Colors.white.withOpacity(0.1),
                          child: const SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(
                              Icons.grid_view_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'จัดการพนักงาน',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'ทีมงานของร้านคุณ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // ปุ่ม Refresh ด้านขวา
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _loading ? null : _load,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.refresh, color: _textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // เนื้อหาหลัก (List พนักงาน)
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator(radius: 16))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _staff.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 120),
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.groups_outlined,
                                    size: 64,
                                    color: Colors.blue.shade300,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Center(
                                  child: Text(
                                    'ยังไม่มีพนักงานในร้าน',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: Text(
                                    'กดปุ่มด้านล่างเพื่อเชิญทีมงานเข้าร่วม',
                                    style: TextStyle(color: _textSecondary),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              itemCount: _staff.length,
                              itemBuilder: (context, index) {
                                final member = Map<String, dynamic>.from(
                                  _staff[index],
                                );
                                final pending = !_hasStoreAccess(member);
                                final avatar = member['avatar_url']?.toString();
                                final roleName = _role(
                                  member['invitation']?['role'] ??
                                      member['role'],
                                );

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.02),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    leading: CircleAvatar(
                                      radius: 24,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      backgroundImage:
                                          avatar != null && avatar.isNotEmpty
                                          ? NetworkImage(avatar)
                                          : null,
                                      child: avatar == null || avatar.isEmpty
                                          ? Icon(
                                              Icons.person,
                                              color: Colors.grey.shade400,
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      member['full_name'] ??
                                          member['email'] ??
                                          'พนักงาน',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      // ใช้ Wrap แทน Row เพื่อแก้ปัญหา Overflow
                                      child: Wrap(
                                        spacing:
                                            8.0, // ระยะห่างแนวนอนระหว่าง Badge
                                        runSpacing:
                                            8.0, // ระยะห่างแนวตั้งเมื่อขึ้นบรรทัดใหม่
                                        children: [
                                          // Badge บอกตำแหน่ง
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _bgColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              roleName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _textSecondary,
                                              ),
                                            ),
                                          ),
                                          // Badge บอกสถานะ
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: pending
                                                  ? Colors.orange.shade50
                                                  : Colors.green.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  pending
                                                      ? Icons.access_time
                                                      : Icons.check_circle,
                                                  size: 12,
                                                  color: pending
                                                      ? Colors.orange.shade700
                                                      : Colors.green.shade700,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  pending
                                                      ? 'รอตอบรับ'
                                                      : 'ใช้งานอยู่',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: pending
                                                        ? Colors.orange.shade700
                                                        : Colors.green.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: pending
                                          ? 'ยกเลิกคำเชิญ'
                                          : 'นำออกจากร้าน',
                                      onPressed: () => _remove(member),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.red.shade50,
                                        foregroundColor: Colors.redAccent,
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
      // ปุ่มลอย (Floating Action Button) แบบทันสมัย
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _primaryBlue,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _inviteDialog,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'เพิ่มพนักงาน',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
