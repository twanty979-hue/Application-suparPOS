// lib/screens/receipt_settings_screen.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blue_thermal_printer/blue_thermal_printer.dart' as bt;
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';

class ReceiptSettingsScreen extends StatefulWidget {
  final String brandId;

  const ReceiptSettingsScreen({super.key, required this.brandId});

  @override
  State<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends State<ReceiptSettingsScreen> {
  final bt.BlueThermalPrinter bluetooth = bt.BlueThermalPrinter.instance;
  final TextEditingController _ipController = TextEditingController();

  List<bt.BluetoothDevice> _devices = [];
  bt.BluetoothDevice? _selectedDevice;

  bool _isPermissionGranted = false;
  int _activeConnection = 0;
  int _receiptCopies = 1;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInit();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionsAndInit() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothConnect]?.isGranted == true) {
      setState(() => _isPermissionGranted = true);
      await _getBluetoothDevices();
      await _loadSavedSettings();
    } else {
      _showSnackBar('กรุณาอนุญาตสิทธิ์บลูทูธเพื่อใช้งาน', Colors.orange);
    }
  }

  Future<void> _getBluetoothDevices() async {
    try {
      final devices = await bluetooth.getBondedDevices();
      setState(() => _devices = devices);
    } catch (e) {
      debugPrint('Error loading bluetooth devices: $e');
    }
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final dbSettings = await DatabaseHelper.instance.getPrinterSettings(
      widget.brandId,
    );
    setState(() {
      _ipController.text =
          dbSettings?['ip']?.toString().trim().isNotEmpty == true
          ? dbSettings!['ip'].toString().trim()
          : (prefs.getString('printer_ip_${widget.brandId}') ?? '');
      final savedCopies =
          int.tryParse(dbSettings?['copies']?.toString() ?? '') ??
          prefs.getInt('receipt_copies_${widget.brandId}') ??
          1;
      _receiptCopies = savedCopies <= 1 ? 1 : 2;
      final savedMac = dbSettings?['mac']?.toString().trim().isNotEmpty == true
          ? dbSettings!['mac'].toString().trim()
          : prefs.getString('printer_mac_${widget.brandId}');

      if (savedMac != null && _devices.isNotEmpty) {
        try {
          _selectedDevice = _devices.whereType<bt.BluetoothDevice>().firstWhere(
            (d) => (d.address ?? '') == savedMac,
          );
        } catch (e) {
          _selectedDevice = null;
        }
      }
    });
  }

  Future<void> _persistPrinterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac =
        _selectedDevice?.address ??
        prefs.getString('printer_mac_${widget.brandId}') ??
        '';

    await prefs.setString(
      'printer_ip_${widget.brandId}',
      _ipController.text.trim(),
    );
    await prefs.setInt('receipt_copies_${widget.brandId}', _receiptCopies);

    if (savedMac.isNotEmpty) {
      await prefs.setString('printer_mac_${widget.brandId}', savedMac);
    }

    await DatabaseHelper.instance.savePrinterSettings(
      brandId: widget.brandId,
      ip: _ipController.text.trim(),
      mac: savedMac,
      copies: _receiptCopies,
    );
  }

  Future<void> _saveSettings() async {
    await _persistPrinterSettings();
    _showSnackBar('บันทึกการตั้งค่าเครื่องพิมพ์เรียบร้อยแล้ว', Colors.green);
  }

  Future<List<int>> _generateReceiptImageBytes() async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];

    const double baseWidth = 384.0;
    const double baseHeight = 400.0;
    const double scale = 2.0;

    const double width = baseWidth * scale;
    const double height = baseHeight * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );

    void drawText(
      String text,
      double y, {
      double fontSize = 20,
      bool isBold = true,
      TextAlign align = TextAlign.left,
    }) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize * scale,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
            fontFamily: 'Kanit',
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      );
      textPainter.layout(maxWidth: width);

      double x = 0;
      if (align == TextAlign.center) {
        x = (width - textPainter.width) / 2;
      } else if (align == TextAlign.right) {
        x = width - textPainter.width;
      }
      textPainter.paint(canvas, Offset(x, y * scale));
    }

    drawText('SuparPOS', 15, fontSize: 28, align: TextAlign.center);
    drawText(
      'ใบเสร็จรับเงินอย่างย่อ',
      55,
      fontSize: 18,
      align: TextAlign.center,
    );
    drawText(
      '------------------------------------------',
      85,
      fontSize: 16,
      align: TextAlign.center,
    );
    drawText('วันที่: 24 พ.ค. 2026 12:30', 110, fontSize: 18);
    drawText('พนักงาน: แอดมินร้าน', 135, fontSize: 18);
    drawText(
      '------------------------------------------',
      160,
      fontSize: 16,
      align: TextAlign.center,
    );
    drawText('1x ข้าวมันไก่ต้ม', 185, fontSize: 18);
    drawText('50.00', 185, fontSize: 18, align: TextAlign.right);
    drawText('1x กะเพราหมูสับไข่ดาว', 215, fontSize: 18);
    drawText('65.00', 215, fontSize: 18, align: TextAlign.right);
    drawText('2x น้ำแข็งเปล่า', 245, fontSize: 18);
    drawText('4.00', 245, fontSize: 18, align: TextAlign.right);
    drawText(
      '------------------------------------------',
      275,
      fontSize: 16,
      align: TextAlign.center,
    );
    drawText('รวมทั้งสิ้น (Total):', 305, fontSize: 21);
    drawText('119.00 บาท', 305, fontSize: 21, align: TextAlign.right);
    drawText(
      '------------------------------------------',
      335,
      fontSize: 16,
      align: TextAlign.center,
    );
    drawText('ขอบคุณที่ใช้บริการ', 365, fontSize: 18, align: TextAlign.center);
    drawText('Powered by FoodScan', 395, fontSize: 16, align: TextAlign.center);

    final picture = recorder.endRecording();
    final imageUi = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await imageUi.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final largeImage = img.decodeImage(pngBytes);
    if (largeImage != null) {
      final resizedImage = img.copyResize(
        largeImage,
        width: baseWidth.toInt(),
        height: baseHeight.toInt(),
        interpolation: img.Interpolation.nearest,
      );

      for (int y = 0; y < resizedImage.height; y++) {
        for (int x = 0; x < resizedImage.width; x++) {
          final colorValue = resizedImage.getPixel(x, y);
          final r = img.getRed(colorValue);
          final g = img.getGreen(colorValue);
          final b = img.getBlue(colorValue);
          final luminance = (0.299 * r) + (0.587 * g) + (0.114 * b);

          if (luminance < 200) {
            resizedImage.setPixel(x, y, img.getColor(0, 0, 0));
          } else {
            resizedImage.setPixel(x, y, img.getColor(255, 255, 255));
          }
        }
      }

      bytes.addAll(generator.image(resizedImage));
    }

    bytes.addAll(generator.feed(0));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<void> _printTestBluetooth() async {
    if (_selectedDevice == null) return;

    await _persistPrinterSettings();

    try {
      final isConnected = await bluetooth.isConnected.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (isConnected == false) {
        await bluetooth
            .connect(_selectedDevice!)
            .timeout(const Duration(seconds: 8));
        await Future.delayed(const Duration(seconds: 1));
      }

      final receiptBytes = await _generateReceiptImageBytes();
      await bluetooth
          .writeBytes(Uint8List.fromList(receiptBytes))
          .timeout(const Duration(seconds: 8));

      _showSnackBar('ส่งข้อมูลพิมพ์ Bluetooth สำเร็จ', Colors.green);
    } catch (e) {
      _showSnackBar('พิมพ์ Bluetooth ล้มเหลว: $e', Colors.red);
    }
  }

  Future<void> _printTestWifi() async {
    if (_ipController.text.trim().isEmpty) {
      _showSnackBar('กรุณากรอก IP Address ของเครื่องพิมพ์', Colors.orange);
      return;
    }

    await _persistPrinterSettings();

    try {
      final receiptBytes = await _generateReceiptImageBytes();
      final socket = await Socket.connect(
        _ipController.text.trim(),
        9100,
        timeout: const Duration(seconds: 5),
      );
      socket.add(receiptBytes);
      await socket.flush();
      await socket.close();

      _showSnackBar('พิมพ์ทดสอบผ่าน Wi-Fi สำเร็จ', Colors.green);
    } catch (e) {
      _showSnackBar('พิมพ์ผ่าน Wi-Fi ล้มเหลว: $e', Colors.red);
    }
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Kanit')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
                            _buildStatusOverview(),
                            const SizedBox(height: 18),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _activeConnection == 0
                                  ? _buildBluetoothCard()
                                  : _buildWifiCard(),
                            ),
                            const SizedBox(height: 18),
                            _buildPreviewCard(),
                            const SizedBox(height: 18),
                            _buildSaveButton(),
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
                Icons.receipt_long_outlined,
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
                  'ตั้งค่าใบเสร็จ',
                  style: TextStyle(
                    color: AppColors.slate900,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'จัดการเครื่องพิมพ์และตัวอย่างใบเสร็จ',
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text(
                'บันทึก',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.slate900,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: AppColors.slate900.withOpacity(0.22),
                padding: const EdgeInsets.symmetric(horizontal: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOverview() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            index: 0,
            icon: Icons.bluetooth_rounded,
            title: 'Bluetooth',
            value: _isPermissionGranted
                ? '${_devices.length} อุปกรณ์'
                : 'รอสิทธิ์',
            color: AppColors.blue600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            index: 1,
            icon: Icons.wifi_rounded,
            title: 'Wi-Fi / LAN',
            value: _ipController.text.isEmpty
                ? 'ยังไม่ตั้งค่า'
                : _ipController.text,
            color: AppColors.emerald500,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required int index,
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final isActive = _activeConnection == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _activeConnection = index),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 96,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.07) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive ? color : AppColors.slate200,
              width: isActive ? 1.7 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isActive
                    ? color.withOpacity(0.14)
                    : AppColors.slate900.withOpacity(0.04),
                blurRadius: isActive ? 18 : 12,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(isActive ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.slate900,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(
                            Icons.check_circle_rounded,
                            color: color,
                            size: 17,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive ? color : AppColors.slate400,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive ? 'กำลังเลือกอยู่' : 'แตะเพื่อเลือก',
                      style: TextStyle(
                        color: isActive ? color : AppColors.slate400,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildReceiptBehaviorCard() {
    return _buildSettingsCard(
      icon: Icons.tune_rounded,
      iconColor: const Color(0xFF7C3AED),
      iconBg: const Color(0xFFF3E8FF),
      title: 'จำนวนใบเสร็จ',
      subtitle: 'เลือกจำนวนใบที่พิมพ์ต่อครั้ง',
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'จำนวนใบต่อครั้ง',
                  style: TextStyle(
                    color: AppColors.slate900,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _buildCopyButton(1),
              const SizedBox(width: 8),
              _buildCopyButton(2),
            ],
          ),
          /*
          if (false) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.room_service_outlined,
                  color: AppColors.slate600,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'พิมพ์เมื่อออเดอร์เข้า',
                        style: TextStyle(
                          color: AppColors.slate900,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'ใช้กับออเดอร์ใหม่จากโต๊ะ/QR',
                        style: TextStyle(
                          color: AppColors.slate400,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: false,
                  activeColor: AppColors.emerald500,
                  onChanged: null,
                ),
              ],
            ),
          ),
          ],
          */
        ],
      ),
    );
  }

  Widget _buildCopyButton(int copies) {
    final isActive = _receiptCopies == copies;
    return SizedBox(
      height: 38,
      child: OutlinedButton(
        onPressed: () => setState(() => _receiptCopies = copies),
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive ? AppColors.slate900 : Colors.white,
          foregroundColor: isActive ? Colors.white : AppColors.slate700,
          side: BorderSide(
            color: isActive ? AppColors.slate900 : AppColors.slate200,
            width: 1.2,
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

  Widget _buildBluetoothCard() {
    return _buildSettingsCard(
      key: const ValueKey('bluetooth'),
      icon: Icons.bluetooth_rounded,
      iconColor: AppColors.blue600,
      iconBg: AppColors.blue50,
      title: 'ระบบ Bluetooth',
      subtitle: 'เลือกเครื่องพิมพ์ที่จับคู่ไว้กับเครื่องนี้',
      child: Column(
        children: [
          _buildPermissionBanner(),
          const SizedBox(height: 14),
          DropdownButtonFormField<bt.BluetoothDevice>(
            value: _selectedDevice,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.slate400,
            ),
            isExpanded: true,
            items: _devices
                .whereType<bt.BluetoothDevice>()
                .map(
                  (d) => DropdownMenuItem<bt.BluetoothDevice>(
                    value: d,
                    child: Text(
                      d.name ?? 'Unknown printer',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate800,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) async {
              setState(() => _selectedDevice = val);
              if (val != null) {
                await _persistPrinterSettings();
              }
            },
            decoration: _inputDecoration('เลือกอุปกรณ์บลูทูธ'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSecondaryButton(
                  icon: Icons.refresh_rounded,
                  label: 'รีเฟรช',
                  onPressed: () => _getBluetoothDevices(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPrimaryButton(
                  icon: Icons.print_rounded,
                  label: 'ทดสอบพิมพ์',
                  onPressed: _selectedDevice != null
                      ? _printTestBluetooth
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWifiCard() {
    return _buildSettingsCard(
      key: const ValueKey('wifi'),
      icon: Icons.wifi_rounded,
      iconColor: AppColors.emerald500,
      iconBg: AppColors.emerald50,
      title: 'ระบบ Wi-Fi / LAN',
      subtitle: 'เหมาะกับเครื่องพิมพ์ที่ต่อเครือข่ายเดียวกับแอป',
      child: Column(
        children: [
          TextField(
            controller: _ipController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              color: AppColors.slate900,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            decoration: _inputDecoration(
              'IP Address',
              hintText: 'เช่น 192.168.0.131',
              prefixIcon: Icons.router_outlined,
            ),
          ),
          const SizedBox(height: 14),
          _buildPrimaryButton(
            icon: Icons.print_rounded,
            label: 'ทดสอบพิมพ์ผ่าน Wi-Fi',
            onPressed: _printTestWifi,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner() {
    final granted = _isPermissionGranted;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: granted ? AppColors.emerald50 : AppColors.orange50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted ? const Color(0xFFA7F3D0) : AppColors.orange100,
        ),
      ),
      child: Row(
        children: [
          Icon(
            granted ? Icons.verified_user_outlined : Icons.lock_outline_rounded,
            color: granted ? AppColors.emerald500 : AppColors.orange600,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              granted
                  ? 'อนุญาต Bluetooth แล้ว พร้อมเลือกเครื่องพิมพ์'
                  : 'ยังไม่ได้อนุญาต Bluetooth กรุณาอนุญาตเพื่อใช้งาน',
              style: TextStyle(
                color: granted ? const Color(0xFF047857) : AppColors.orange600,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    return _buildSettingsCard(
      icon: Icons.article_outlined,
      iconColor: const Color(0xFF7C3AED),
      iconBg: const Color(0xFFF3E8FF),
      title: 'ตัวอย่างใบเสร็จ',
      subtitle: 'ตัวอย่างรูปแบบที่จะส่งไปยังเครื่องพิมพ์',
      child: Center(
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate200),
            boxShadow: [
              BoxShadow(
                color: AppColors.slate900.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              const Text(
                'SuparPOS',
                style: TextStyle(
                  color: AppColors.slate900,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'ใบเสร็จรับเงินอย่างย่อ',
                style: TextStyle(
                  color: AppColors.slate500,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildDashedLine(),
              const SizedBox(height: 12),
              _buildReceiptRow('ข้าวมันไก่ต้ม', '50.00'),
              _buildReceiptRow('กะเพราหมูสับ', '65.00'),
              _buildReceiptRow('น้ำแข็งเปล่า x2', '4.00'),
              const SizedBox(height: 8),
              _buildDashedLine(),
              const SizedBox(height: 10),
              _buildReceiptRow('Total', '119.00', bold: true),
              const SizedBox(height: 12),
              const Text(
                'ขอบคุณที่ใช้บริการ',
                style: TextStyle(
                  color: AppColors.slate500,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String name, String amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.slate800,
                fontSize: 11,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: AppColors.slate900,
              fontSize: 11,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashedLine() {
    return Row(
      children: List.generate(
        18,
        (index) => Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: AppColors.slate200,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    Key? key,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
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
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.slate900,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.slate200,
          disabledForegroundColor: AppColors.slate400,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.slate700,
          side: const BorderSide(color: AppColors.slate200, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _saveSettings,
        icon: const Icon(Icons.save_outlined, size: 19),
        label: const Text(
          'บันทึกการตั้งค่า',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.slate900,
          foregroundColor: Colors.white,
          elevation: 10,
          shadowColor: AppColors.slate900.withOpacity(0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({double radius = 24}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFFEAF0F7)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF64748B).withOpacity(0.08),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hintText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: const TextStyle(
        color: AppColors.slate400,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: const TextStyle(
        color: AppColors.slate300,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: AppColors.slate400, size: 19),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.slate200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.slate200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.slate900, width: 1.4),
      ),
    );
  }
}
