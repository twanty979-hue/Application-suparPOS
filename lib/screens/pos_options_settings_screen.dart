// lib/screens/pos_options_settings_screen.dart

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import '../db/database_helper.dart';
import '../services/app_notification_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';

class PosOptionsSettingsScreen extends StatefulWidget {
  final String brandId;

  const PosOptionsSettingsScreen({super.key, required this.brandId});

  @override
  State<PosOptionsSettingsScreen> createState() =>
      _PosOptionsSettingsScreenState();
}

class _PosOptionsSettingsScreenState extends State<PosOptionsSettingsScreen> {
  bool _showProductImages = true;
  bool _showBarcodeProducts = true;
  bool _autoPrintIncomingOrders = false;
  bool _showReceiptLogo = false;
  bool _notificationVoiceEnabled = true;
  bool _notificationSoundEnabled = true;
  String? _notificationSoundPath;
  int _receiptCopies = 1;
  String _tableQrMode = 'rotating';
  bool _enableShiftMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showProductImages =
          prefs.getBool('pos_show_product_images_${widget.brandId}') ?? true;
      _showBarcodeProducts =
          prefs.getBool('pos_show_barcode_products_${widget.brandId}') ?? true;
      _autoPrintIncomingOrders =
          prefs.getBool('auto_print_new_order_${widget.brandId}') ?? false;
      _showReceiptLogo =
          prefs.getBool('show_receipt_logo_${widget.brandId}') ?? false;
      _notificationVoiceEnabled =
          prefs.getBool('notification_voice_enabled_${widget.brandId}') ?? true;
      _notificationSoundEnabled =
          prefs.getBool('notification_sound_enabled_${widget.brandId}') ?? true;
      _notificationSoundPath = prefs.getString(
        'notification_sound_path_${widget.brandId}',
      );
      _receiptCopies = 1;
      _tableQrMode =
          prefs.getString('table_qr_mode_${widget.brandId}') ?? 'rotating';
      _enableShiftMode =
          prefs.getBool('pos_enable_shift_mode_${widget.brandId}') ?? false;
    });

    final dbSettings = await DatabaseHelper.instance.getPrinterSettings(
      widget.brandId,
    );
    final savedCopies =
        int.tryParse(dbSettings?['copies']?.toString() ?? '') ??
        prefs.getInt('receipt_copies_${widget.brandId}') ??
        1;
    if (!mounted) return;
    setState(() => _receiptCopies = savedCopies <= 1 ? 1 : 2);
    await _fetchTableQrMode();
  }

  Future<void> _setEnableShiftMode(bool value) async {
    setState(() => _enableShiftMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pos_enable_shift_mode_${widget.brandId}', value);
  }

  Future<void> _fetchTableQrMode() async {
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) return;
      final response = await http.get(
        Uri.parse(ApiService.settings),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final brand = data['brand'] ?? data;
      final mode =
          (brand['table_qr_mode'] ?? brand['config']?['qr_mode'] ?? 'rotating')
              .toString();
      if (mode != 'static' && mode != 'rotating') return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('table_qr_mode_${widget.brandId}', mode);
      if (mounted) setState(() => _tableQrMode = mode);
    } catch (_) {}
  }

  Future<void> _setShowProductImages(bool value) async {
    setState(() => _showProductImages = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pos_show_product_images_${widget.brandId}', value);
  }

  Future<void> _setShowBarcodeProducts(bool value) async {
    setState(() => _showBarcodeProducts = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pos_show_barcode_products_${widget.brandId}', value);
  }

  Future<void> _setAutoPrintIncomingOrders(bool value) async {
    setState(() => _autoPrintIncomingOrders = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_print_new_order_${widget.brandId}', value);
  }

  Future<void> _setShowReceiptLogo(bool value) async {
    setState(() => _showReceiptLogo = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_receipt_logo_${widget.brandId}', value);
  }

  Future<void> _setTableQrMode(String mode) async {
    if (mode != 'static' && mode != 'rotating') return;
    setState(() => _tableQrMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('table_qr_mode_${widget.brandId}', mode);

    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) return;
      final response = await http.post(
        Uri.parse(ApiService.settings),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'table_qr_mode': mode}),
      );
      if (response.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกโหมด QR บนระบบไม่สำเร็จ: ${response.body}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกโหมด QR ไม่สำเร็จ: $e')));
    }
  }

  Future<void> _setNotificationVoiceEnabled(bool value) async {
    setState(() => _notificationVoiceEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_voice_enabled_${widget.brandId}', value);
  }

  Future<void> _setNotificationSoundEnabled(bool value) async {
    setState(() => _notificationSoundEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sound_enabled_${widget.brandId}', value);
  }

  Future<void> _pickNotificationSound() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
      allowMultiple: false,
    );
    final selectedPath = result?.files.single.path;
    if (selectedPath == null) return;

    final sourceFile = File(selectedPath);
    final appDir = await getApplicationDocumentsDirectory();
    final soundsDir = Directory(p.join(appDir.path, 'notification_sounds'));
    if (!await soundsDir.exists()) {
      await soundsDir.create(recursive: true);
    }

    final extension = p.extension(sourceFile.path).toLowerCase();
    final destinationPath = p.join(
      soundsDir.path,
      'order_${widget.brandId}$extension',
    );
    await sourceFile.copy(destinationPath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'notification_sound_path_${widget.brandId}',
      destinationPath,
    );
    await prefs.setBool('notification_sound_enabled_${widget.brandId}', true);

    if (!mounted) return;
    setState(() {
      _notificationSoundPath = destinationPath;
      _notificationSoundEnabled = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกเสียงแจ้งเตือนไว้ในเครื่องแล้ว')),
    );
  }

  Future<void> _clearNotificationSound() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_sound_path_${widget.brandId}');
    if (mounted) {
      setState(() => _notificationSoundPath = null);
    }
  }

  Future<void> _setReceiptCopies(int copies) async {
    final normalizedCopies = copies <= 1 ? 1 : 2;
    setState(() => _receiptCopies = normalizedCopies);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('receipt_copies_${widget.brandId}', normalizedCopies);

    final dbSettings = await DatabaseHelper.instance.getPrinterSettings(
      widget.brandId,
    );
    await DatabaseHelper.instance.savePrinterSettings(
      brandId: widget.brandId,
      ip: dbSettings?['ip']?.toString() ?? '',
      mac: dbSettings?['mac']?.toString() ?? '',
      copies: normalizedCopies,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      drawer: const AppSidebar(activeMenu: 'settings'),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            return Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Column(
                          children: [
                            _buildOptionCard(
                              icon: Icons.image_outlined,
                              iconColor: AppColors.blue600,
                              iconBg: AppColors.blue50,
                              title: 'แสดงรูปอาหาร',
                              subtitle: 'เปิด/ปิดรูปสินค้าในหน้าคิดเงิน',
                              value: _showProductImages,
                              onChanged: _setShowProductImages,
                            ),
                            const SizedBox(height: 14),
                            _buildOptionCard(
                              icon: Icons.qr_code_2_rounded,
                              iconColor: const Color(0xFF7C3AED),
                              iconBg: const Color(0xFFF5F3FF),
                              title: 'แสดงสินค้าที่มีบาร์โค้ด',
                              subtitle:
                                  'เปิดเพื่อแสดง หรือปิดเพื่อซ่อนสินค้าบาร์โค้ดในหน้าคิดเงิน',
                              value: _showBarcodeProducts,
                              onChanged: _setShowBarcodeProducts,
                            ),
                            const SizedBox(height: 14),
                            _buildOptionCard(
                              icon: Icons.room_service_outlined,
                              iconColor: AppColors.emerald500,
                              iconBg: AppColors.emerald50,
                              title: 'พิมพ์เมื่อออเดอร์เข้า',
                              subtitle: 'ใช้กับออเดอร์ใหม่จากโต๊ะ/QR',
                              value: _autoPrintIncomingOrders,
                              onChanged: _setAutoPrintIncomingOrders,
                            ),
                            const SizedBox(height: 14),
                            _buildTableQrModeCard(),
                            const SizedBox(height: 14),
                            _buildReceiptCopiesCard(),
                            const SizedBox(height: 14),
                            _buildOptionCard(
                              icon: Icons.account_balance_wallet_outlined,
                              iconColor: Colors.deepOrange,
                              iconBg: const Color(0xFFFFF3E0),
                              title: 'โหมดเปิด-ปิดกะ (Shift Control)',
                              subtitle:
                                  'เปิดเพื่อบันทึกกะทำงานของพนักงาน ตรวจสอบเงินทอนเริ่มต้น และกระทบยอดปิดเครื่องเงินสด',
                              value: _enableShiftMode,
                              onChanged: _setEnableShiftMode,
                            ),
                            const SizedBox(height: 14),
                            _buildOptionCard(
                              icon: Icons.storefront_rounded,
                              iconColor: const Color(0xFF0891B2),
                              iconBg: const Color(0xFFE0F7FA),
                              title: 'แสดงโลโก้บนใบเสร็จ',
                              subtitle:
                                  'ถ้าไม่มีโลโก้ร้าน ระบบจะใช้โลโก้แอป SuparPOS แทน',
                              value: _showReceiptLogo,
                              onChanged: _setShowReceiptLogo,
                            ),
                            const SizedBox(height: 14),
                            _buildNotificationSettingsCard(),
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EEF6))),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Scaffold.of(context).openDrawer();
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.slate900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.point_of_sale_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ตั้งค่าหน้าคิดเงิน',
                  style: TextStyle(
                    color: AppColors.slate900,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'ตั้งค่าการแสดงผลและงานอัตโนมัติของ POS',
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.slate900,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: iconColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSettingsCard() {
    final soundName = _notificationSoundPath == null
        ? 'ยังไม่ได้เลือกไฟล์เสียง'
        : p.basename(_notificationSoundPath!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildNotificationSwitch(
            icon: Icons.record_voice_over_outlined,
            title: 'อ่านเสียงภาษาไทย',
            subtitle: 'พูดแจ้งเตือนตอนแอปเปิดอยู่และมีออเดอร์เข้า',
            value: _notificationVoiceEnabled,
            onChanged: _setNotificationVoiceEnabled,
          ),
          const SizedBox(height: 12),
          _buildNotificationSwitch(
            icon: Icons.music_note_outlined,
            title: 'เสียงแจ้งเตือนที่ตั้งเอง',
            subtitle: soundName,
            value: _notificationSoundEnabled,
            onChanged: _setNotificationSoundEnabled,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _pickNotificationSound,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('เลือก MP3'),
              ),
              OutlinedButton.icon(
                onPressed: _notificationSoundPath == null
                    ? null
                    : () => AppNotificationService.previewNotificationSound(
                        _notificationSoundPath!,
                      ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('ทดสอบเสียง'),
              ),
              OutlinedButton.icon(
                onPressed: AppNotificationService.previewThaiVoice,
                icon: const Icon(Icons.volume_up_outlined, size: 18),
                label: const Text('ทดสอบเสียงอ่าน'),
              ),
              if (_notificationSoundPath != null)
                OutlinedButton.icon(
                  onPressed: _clearNotificationSound,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ล้างเสียง'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableQrModeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.blue50,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppColors.blue600,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'โหมด QR โต๊ะ',
                      style: TextStyle(
                        color: AppColors.slate900,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'เลือก QR ติดโต๊ะ หรือ QR เปลี่ยนเมื่อคิดเงิน',
                      style: TextStyle(
                        color: AppColors.slate400,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildQrModeButton('rotating', 'เปลี่ยนทุกรอบ')),
              const SizedBox(width: 8),
              Expanded(child: _buildQrModeButton('static', 'ติดโต๊ะ')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrModeButton(String mode, String label) {
    final isActive = _tableQrMode == mode;
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: () => _setTableQrMode(mode),
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive ? AppColors.slate900 : Colors.white,
          foregroundColor: isActive ? Colors.white : AppColors.slate700,
          side: BorderSide(
            color: isActive ? AppColors.slate900 : AppColors.slate200,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildReceiptCopiesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Color(0xFF7C3AED),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'จำนวนใบเสร็จ',
                  style: TextStyle(
                    color: AppColors.slate900,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'เลือกจำนวนใบที่พิมพ์ต่อครั้ง',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _buildCopyButton(1),
          const SizedBox(width: 8),
          _buildCopyButton(2),
        ],
      ),
    );
  }

  Widget _buildCopyButton(int copies) {
    final isActive = _receiptCopies == copies;
    return SizedBox(
      height: 38,
      child: OutlinedButton(
        onPressed: () => _setReceiptCopies(copies),
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive ? AppColors.slate900 : Colors.white,
          foregroundColor: isActive ? Colors.white : AppColors.slate700,
          side: BorderSide(
            color: isActive ? AppColors.slate900 : AppColors.slate200,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          '$copies ใบ',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildNotificationSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.orange50,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.orange600, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.slate900,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.slate400,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeColor: AppColors.orange600,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
