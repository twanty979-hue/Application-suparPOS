// lib/screens/pos_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as bt;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/printer_service.dart';

import '../widgets/modals/cash_modal.dart';
import '../widgets/modals/variant_modal.dart';
import '../widgets/modals/table_qr_modal.dart';
import '../widgets/modals/promptpay_modal.dart';
import '../widgets/modals/table_selector_modal.dart';
import '../widgets/modals/completed_receipt_modal.dart';
import '../widgets/modals/barcode_scanner_modal.dart';
import '../widgets/pos/cart_panel.dart';
import '../widgets/pos/product_grid.dart';
import '../widgets/pos/table_list.dart';
import '../widgets/pos/pos_top_bar.dart';
import '../widgets/pos/mobile_bottom_cart.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../db/payment_repository.dart';
import '../db/database_helper.dart';
import 'receipt_settings_screen.dart';

class PosScreen extends StatefulWidget {
  final String brandId;

  const PosScreen({super.key, required this.brandId});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen>
    with SingleTickerProviderStateMixin {
  final bt.BlueThermalPrinter _printerBluetooth =
      bt.BlueThermalPrinter.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final GlobalKey _desktopCartKey = GlobalKey();
  final GlobalKey _mobileCartKey = GlobalKey();

  bool _isCartBouncing = false;
  bool _isPrintingReceipt = false;
  bool _isPrinterFailureModalOpen = false;
  bool _suppressPrinterFailureModalForSession = false;
  int _printerFailureModalShownCount = 0;
  bool _hasShownQuotaLimitWarning = false;
  bool _isQuotaLimitWarningOpen = false;

  String _activeTab = 'tables';
  String _selectedCategory = 'ALL';
  String _paymentMethod = 'cash';
  bool _isLoadingAPI = false;
  bool _showProductImages = true;
  bool _showBarcodeProducts = true;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _discounts = [];
  List<Map<String, dynamic>> _cart = [];
  final List<Map<String, dynamic>> _cancelledCartItems = [];
  String? _walkInDraftOrderId;
  List<Map<String, dynamic>> _unpaidOrders = [];

  int _orderUsage = 0;
  int _orderLimit = 0;
  bool _isLocked = false;
  String _currentPlan = 'free';
  Map<String, dynamic> _brandSettings = {};
  Map<String, dynamic>? _selectedOrder;
  final TextEditingController _barcodeController = TextEditingController();
  OverlayEntry? _topNotificationEntry;
  Timer? _topNotificationTimer;

  String? _accessToken;

  @override
  void initState() {
    super.initState();
    _loadSessionAndInit();
  }

  Future<void> _loadSessionAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    _showProductImages =
        prefs.getBool('pos_show_product_images_${widget.brandId}') ?? true;
    _showBarcodeProducts =
        prefs.getBool('pos_show_barcode_products_${widget.brandId}') ?? true;

    await _loadCachedPosData();
    await _restoreWalkInDraftOrder();
    _accessToken = await StorageService.getToken();

    await Future.wait([
      _fetchPosData(),
      _fetchBrandSettings(),
      _fetchOrderQuota(),
    ]);

    _setupFCM();
  }

  // =========================================================================
  // 🔔 ระบบ FIREBASE CLOUD MESSAGING (FCM)
  // =========================================================================
  Future<void> _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print("✅ [FCM] ได้รับอนุญาตให้ส่งแจ้งเตือนแล้ว");

      String? fcmToken = await messaging.getToken();
      if (fcmToken != null) {
        print("🔑 [FCM Token] $fcmToken");
        _saveFcmTokenToServer(fcmToken);
      }

      messaging.onTokenRefresh.listen((newToken) {
        _saveFcmTokenToServer(newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        print("📩 [FCM Foreground] ได้รับข้อความ: ${message.data}");

        final type = message.data['type'];
        final alertTitle = message.data['title'] ?? 'อัปเดต';
        final alertBody = message.data['body'] ?? 'มีการอัปเดตข้อมูลโต๊ะ';

        if (type == 'SILENT_UPDATE' ||
            type == 'NEW_ORDER' ||
            type == 'ORDER_PAID') {
          print(
            "🔄 [SYNC] ข้อมูลมีการเปลี่ยนแปลง สั่งรีเฟรชหน้า POS อัตโนมัติ!",
          );
          _fetchPosData();
          _fetchOrderQuota();
        }

        if (mounted && (type == 'NEW_ORDER' || type == 'ORDER_PAID')) {
          print("[FCM] App-level notification shown: $alertTitle - $alertBody");
        }
      });
    }
  }

  // 📡 ส่ง FCM Token ไปเซฟหลังบ้าน (Next.js)
  Future<void> _saveFcmTokenToServer(String token) async {
    try {
      // 🌟 แก้ไข: ใช้ ApiService.baseUrl ตรงๆ ไร้ซอย Scheme/Port ให้ซ้ำซ้อน
      final url = "${ApiService.baseUrl}/update-fcm";

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'fcm_token': token,
          'platform': _devicePlatform(),
          'device_label': _deviceLabel(),
        }),
      );
      if (response.statusCode == 200) {
        print("☁️ [FCM] นำ Token ไปผูกกับพนักงานใน Database สำเร็จ!");
      }
    } catch (e) {
      print("❌ [FCM Error] ส่ง Token ขึ้น Server ล้มเหลว: $e");
    }
  }

  String _devicePlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  String? _deviceLabel() {
    final label = Platform.localHostname.trim();
    return label.isEmpty ? null : label;
  }

  String? _nonEmptyText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  String? _messageOrderId(Map<String, dynamic> data) {
    const keys = ['order_id', 'orderId', 'id'];
    for (final key in keys) {
      final value = _nonEmptyText(data[key]);
      if (value != null) return value;
    }
    final orderData = _messageOrderData(data);
    if (orderData != null) {
      for (final key in keys) {
        final value = _nonEmptyText(orderData[key]);
        if (value != null) return value;
      }
    }
    return null;
  }

  Map<String, dynamic>? _messageOrderData(Map<String, dynamic> data) {
    final rawOrderData = data['orderData'] ?? data['order_data'];
    if (rawOrderData is Map) {
      return Map<String, dynamic>.from(rawOrderData);
    }
    if (rawOrderData is String && rawOrderData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawOrderData);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic>? _receiptDataFromMessageOrderData(
    Map<String, dynamic> messageData,
  ) {
    final orderData = _messageOrderData(messageData);
    if (orderData == null) return null;

    final rawItems = orderData['items'];
    if (rawItems is! List || rawItems.isEmpty) return null;

    final items = rawItems.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      return {
        'product_name':
            item['product_name'] ?? item['productName'] ?? item['name'],
        'quantity': item['quantity'] ?? item['qty'] ?? 1,
        'variant': item['variant'],
        'note': item['note'],
        'price': item['price'] ?? 0,
      };
    }).toList();

    return {
      'brand_name': _brandSettings['name'] ?? 'เธฃเนเธฒเธเธเธญเธเธเธธเธ“',
      'table_label':
          orderData['table_label'] ??
          orderData['tableLabel'] ??
          orderData['tableName'] ??
          messageData['table_label'] ??
          'Walk-in',
      'order_id':
          orderData['order_id'] ??
          orderData['orderId'] ??
          messageData['order_id'] ??
          messageData['orderId'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'items': items,
      'total_amount': orderData['total_amount'] ?? orderData['totalPrice'] ?? 0,
      'is_kitchen_ticket': true,
    };
  }

  Map<String, dynamic>? _findOrderById(String orderId) {
    for (final order in _unpaidOrders) {
      final id = _nonEmptyText(order['id']);
      if (id == orderId) return order;
    }
    return null;
  }

  Map<String, dynamic>? _findIncomingOrder(
    String? messageOrderId,
    Set<String> knownOrderIds,
  ) {
    if (messageOrderId != null) {
      final matchedOrder = _findOrderById(messageOrderId);
      if (matchedOrder != null) return matchedOrder;
    }

    final newOrders = _unpaidOrders.where((order) {
      final id = _nonEmptyText(order['id']);
      return id != null && !knownOrderIds.contains(id);
    }).toList();
    if (newOrders.isEmpty) return null;

    newOrders.sort((a, b) {
      final aDate =
          DateTime.tryParse(_nonEmptyText(a['created_at']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse(_nonEmptyText(b['created_at']) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return newOrders.first;
  }

  Future<void> _refreshAndMaybePrintIncomingOrder(
    Map<String, dynamic> messageData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final shouldPrint =
        prefs.getBool('auto_print_new_order_${widget.brandId}') ?? false;

    final knownOrderIds = _unpaidOrders
        .map((order) => _nonEmptyText(order['id']))
        .whereType<String>()
        .toSet();
    final messageOrderId = _messageOrderId(messageData);

    Map<String, dynamic>? incomingOrder;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
      await _fetchPosData();
      incomingOrder = _findIncomingOrder(messageOrderId, knownOrderIds);
      if (incomingOrder != null) break;
    }

    if (!shouldPrint) return;

    if (incomingOrder == null) {
      final fallbackReceiptData = _receiptDataFromMessageOrderData(messageData);
      if (fallbackReceiptData == null) return;

      final fallbackOrderId = _nonEmptyText(fallbackReceiptData['order_id']);
      final printedKey = 'auto_printed_orders_${widget.brandId}';
      final printedIds = prefs.getStringList(printedKey) ?? <String>[];
      if (fallbackOrderId != null && printedIds.contains(fallbackOrderId)) {
        return;
      }

      final success = await _printReceiptFromPos(fallbackReceiptData);
      if (!success || fallbackOrderId == null) return;

      await prefs.setStringList(
        printedKey,
        [
          fallbackOrderId,
          ...printedIds.where((id) => id != fallbackOrderId),
        ].take(80).toList(),
      );
      return;
    }

    final orderId = _nonEmptyText(incomingOrder['id']);
    if (orderId == null) return;

    final printedKey = 'auto_printed_orders_${widget.brandId}';
    final printedIds = prefs.getStringList(printedKey) ?? <String>[];
    if (printedIds.contains(orderId)) return;

    final items = List<dynamic>.from(
      incomingOrder['order_items'] as List? ?? const [],
    );
    final receiptData = {
      'brand_name': _brandSettings['name'] ?? 'ร้านของคุณ',
      'table_label': incomingOrder['table_label'] ?? 'Walk-in',
      'order_id': orderId,
      'items': items,
      'total_amount': _orderTotal(incomingOrder),
      'is_kitchen_ticket': true,
    };

    final success = await _printReceiptFromPos(receiptData);
    if (!success) return;

    final updatedPrintedIds = <String>[
      orderId,
      ...printedIds.where((id) => id != orderId),
    ].take(80).toList();
    await prefs.setStringList(printedKey, updatedPrintedIds);
  }

  void _openReceiptSettings() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    Future<void>.delayed(Duration.zero, () {
      if (!mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.popUntil((route) => route is PageRoute);
      navigator.push(
        MaterialPageRoute(
          builder: (context) => ReceiptSettingsScreen(brandId: widget.brandId),
        ),
      );
    });
  }

  Future<void> _showPrinterSettingsAction(
    Map<String, dynamic> receiptData,
  ) async {
    if (!mounted) return;
    if (_suppressPrinterFailureModalForSession || _isPrinterFailureModalOpen) {
      return;
    }

    _printerFailureModalShownCount++;
    _isPrinterFailureModalOpen = true;
    ScaffoldMessenger.of(context).clearSnackBars();

    final prefs = await SharedPreferences.getInstance();
    final dbSettings = await DatabaseHelper.instance.getPrinterSettings(
      widget.brandId,
    );
    final ipController = TextEditingController(
      text: dbSettings?['ip']?.toString().trim().isNotEmpty == true
          ? dbSettings!['ip'].toString().trim()
          : (prefs.getString('printer_ip_${widget.brandId}') ?? ''),
    );
    final savedMac = dbSettings?['mac']?.toString().trim().isNotEmpty == true
        ? dbSettings!['mac'].toString().trim()
        : prefs.getString('printer_mac_${widget.brandId}');
    var receiptCopies =
        int.tryParse(dbSettings?['copies']?.toString() ?? '') ??
        prefs.getInt('receipt_copies_${widget.brandId}') ??
        1;
    receiptCopies = receiptCopies <= 1 ? 1 : 2;

    var devices = <bt.BluetoothDevice>[];
    try {
      devices = await _printerBluetooth.getBondedDevices().timeout(
        const Duration(seconds: 4),
        onTimeout: () => <bt.BluetoothDevice>[],
      );
    } catch (e) {
      debugPrint('POS load bluetooth printers failed: $e');
    }

    bt.BluetoothDevice? selectedDevice;
    if (savedMac != null && savedMac.isNotEmpty) {
      for (final device in devices.whereType<bt.BluetoothDevice>()) {
        if ((device.address ?? '') == savedMac) {
          selectedDevice = device;
          break;
        }
      }
    }

    if (!mounted) {
      ipController.dispose();
      _isPrinterFailureModalOpen = false;
      return;
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          var modalDevices = devices;
          var modalSelectedDevice = selectedDevice;
          var modalCopies = receiptCopies;
          var isSaving = false;
          var isConnectingPrinter = false;
          var isRetryingPrint = false;
          String? statusText;

          Future<bool> saveQuickSettings(StateSetter setModalState) async {
            setModalState(() {
              isSaving = true;
              statusText = null;
            });

            final macToSave = modalSelectedDevice?.address ?? savedMac ?? '';
            await prefs.setString(
              'printer_ip_${widget.brandId}',
              ipController.text.trim(),
            );
            await prefs.setInt('receipt_copies_${widget.brandId}', modalCopies);
            if (macToSave.isNotEmpty) {
              await prefs.setString('printer_mac_${widget.brandId}', macToSave);
            }
            await DatabaseHelper.instance.savePrinterSettings(
              brandId: widget.brandId,
              ip: ipController.text.trim(),
              mac: macToSave,
              copies: modalCopies,
            );

            if (!dialogContext.mounted) return false;
            setModalState(() {
              isSaving = false;
              statusText = 'บันทึกเครื่องพิมพ์แล้ว ลองพิมพ์อีกครั้งได้เลย';
            });
            return true;
          }

          Future<void> connectBluetoothPrinter(
            bt.BluetoothDevice device,
            StateSetter setModalState,
          ) async {
            setModalState(() {
              isConnectingPrinter = true;
              statusText = 'กำลังเชื่อมต่อ Bluetooth...';
            });

            try {
              final deviceMac = device.address ?? '';
              if (deviceMac.isNotEmpty) {
                await prefs.setString(
                  'printer_mac_${widget.brandId}',
                  deviceMac,
                );
                await DatabaseHelper.instance.savePrinterSettings(
                  brandId: widget.brandId,
                  ip: ipController.text.trim(),
                  mac: deviceMac,
                  copies: modalCopies,
                );
              }

              final isConnected = await _printerBluetooth.isConnected.timeout(
                const Duration(seconds: 2),
                onTimeout: () => false,
              );
              if (isConnected == true) {
                try {
                  await _printerBluetooth.disconnect().timeout(
                    const Duration(seconds: 2),
                  );
                } catch (_) {}
              }
              await _printerBluetooth
                  .connect(device)
                  .timeout(const Duration(seconds: 8));
              await Future.delayed(const Duration(milliseconds: 700));

              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText = 'เชื่อมต่อ Bluetooth สำเร็จ';
              });
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText =
                    'เชื่อมต่อ Bluetooth ไม่สำเร็จ ตรวจสอบว่าเปิดเครื่องและจับคู่ไว้แล้ว';
              });
            }
          }

          Future<void> connectWifiPrinter(StateSetter setModalState) async {
            final printerIp = ipController.text.trim();
            if (printerIp.isEmpty) {
              setModalState(() {
                statusText = 'กรุณากรอก IP เครื่องพิมพ์ Wi-Fi / LAN';
              });
              return;
            }

            setModalState(() {
              isConnectingPrinter = true;
              statusText = 'กำลังเชื่อมต่อ Wi-Fi / LAN...';
            });

            try {
              await prefs.setString('printer_ip_${widget.brandId}', printerIp);
              await DatabaseHelper.instance.savePrinterSettings(
                brandId: widget.brandId,
                ip: printerIp,
                mac: modalSelectedDevice?.address ?? savedMac ?? '',
                copies: modalCopies,
              );

              final socket = await Socket.connect(
                printerIp,
                9100,
                timeout: const Duration(seconds: 5),
              );
              await socket.close();

              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText = 'เชื่อมต่อ Wi-Fi / LAN สำเร็จ';
              });
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText =
                    'เชื่อมต่อ Wi-Fi / LAN ไม่สำเร็จ ตรวจสอบ IP และเครือข่าย';
              });
            }
          }

          Future<void> retryPrint(StateSetter setModalState) async {
            setModalState(() {
              isRetryingPrint = true;
              statusText = null;
            });

            final saved = await saveQuickSettings(setModalState);
            if (!saved || !dialogContext.mounted) return;

            setModalState(() {
              statusText = 'กำลังพิมพ์ใบเสร็จอีกครั้ง...';
            });

            final success = await _printReceiptFromPos(
              receiptData,
              showSuccess: true,
            );
            if (!dialogContext.mounted) return;

            if (success) {
              Navigator.of(dialogContext).pop();
              return;
            }

            setModalState(() {
              isRetryingPrint = false;
              statusText =
                  'ยังพิมพ์ไม่สำเร็จ ตรวจสอบเครื่องพิมพ์แล้วลองอีกครั้ง';
            });
          }

          Future<void> refreshPrinters(StateSetter setModalState) async {
            setModalState(() => statusText = 'กำลังค้นหาเครื่องพิมพ์...');
            try {
              final latest = await _printerBluetooth.getBondedDevices().timeout(
                const Duration(seconds: 4),
                onTimeout: () => <bt.BluetoothDevice>[],
              );
              setModalState(() {
                modalDevices = latest;
                if (modalSelectedDevice != null) {
                  final selectedAddress = modalSelectedDevice?.address ?? '';
                  modalSelectedDevice = latest
                      .whereType<bt.BluetoothDevice>()
                      .cast<bt.BluetoothDevice?>()
                      .firstWhere(
                        (device) => device?.address == selectedAddress,
                        orElse: () => null,
                      );
                }
                statusText = latest.isEmpty
                    ? 'ไม่พบเครื่อง Bluetooth ที่จับคู่ไว้'
                    : 'พบเครื่องพิมพ์ ${latest.length} เครื่อง';
              });
            } catch (e) {
              setModalState(() {
                statusText = 'ค้นหาเครื่องพิมพ์ไม่สำเร็จ';
              });
            }
          }

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Dialog(
                elevation: 0,
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.rose500.withOpacity(0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPrinterFailureHeader(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                            child: Column(
                              children: [
                                _buildPrinterFailureNotice(),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.print_rounded,
                                            color: AppColors.slate700,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'เลือกเครื่องพิมพ์',
                                            style: TextStyle(
                                              color: AppColors.slate900,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<
                                        bt.BluetoothDevice
                                      >(
                                        initialValue: modalSelectedDevice,
                                        isExpanded: true,
                                        items: modalDevices
                                            .whereType<bt.BluetoothDevice>()
                                            .map(
                                              (device) =>
                                                  DropdownMenuItem<
                                                    bt.BluetoothDevice
                                                  >(
                                                    value: device,
                                                    child: Text(
                                                      device.name ??
                                                          device.address ??
                                                          'Unknown printer',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? null
                                            : (device) async {
                                                if (device == null) return;
                                                setModalState(() {
                                                  modalSelectedDevice = device;
                                                });
                                                await connectBluetoothPrinter(
                                                  device,
                                                  setModalState,
                                                );
                                              },
                                        decoration:
                                            _printerModalInputDecoration(
                                              'Bluetooth',
                                              Icons.bluetooth_rounded,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: ipController,
                                        keyboardType: TextInputType.number,
                                        onSubmitted: (_) =>
                                            connectWifiPrinter(setModalState),
                                        decoration:
                                            _printerModalInputDecoration(
                                              'IP เครื่องพิมพ์ Wi-Fi / LAN',
                                              Icons.router_outlined,
                                              hintText: 'เช่น 192.168.0.131',
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'จำนวนสำเนาใบเสร็จ',
                                              style: TextStyle(
                                                color: AppColors.slate600,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          _buildCopyChoice(
                                            copies: 1,
                                            selectedCopies: modalCopies,
                                            onTap: () => setModalState(
                                              () => modalCopies = 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildCopyChoice(
                                            copies: 2,
                                            selectedCopies: modalCopies,
                                            onTap: () => setModalState(
                                              () => modalCopies = 2,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (statusText != null) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          statusText!,
                                          style: const TextStyle(
                                            color: AppColors.slate600,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    IconButton.outlined(
                                      onPressed:
                                          isSaving ||
                                              isConnectingPrinter ||
                                              isRetryingPrint
                                          ? null
                                          : () =>
                                                refreshPrinters(setModalState),
                                      icon: const Icon(Icons.refresh_rounded),
                                      tooltip: 'ค้นหาเครื่องพิมพ์ใหม่',
                                      style: IconButton.styleFrom(
                                        foregroundColor: AppColors.slate700,
                                        side: const BorderSide(
                                          color: Color(0xFFE2E8F0),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? null
                                            : () {
                                                _suppressPrinterFailureModalForSession =
                                                    true;
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF64748B,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 13,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'ไม่ต้องแสดงอีก',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? null
                                            : () => retryPrint(setModalState),
                                        icon:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.print_rounded,
                                                size: 19,
                                              ),
                                        label: Text(
                                          isConnectingPrinter
                                              ? 'กำลังเชื่อมต่อ...'
                                              : isRetryingPrint
                                              ? 'กำลังพิมพ์...'
                                              : isSaving
                                              ? 'กำลังบันทึก...'
                                              : 'พิมพ์อีกครั้ง',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.rose500,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 13,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        isSaving ||
                                            isConnectingPrinter ||
                                            isRetryingPrint
                                        ? null
                                        : () =>
                                              saveQuickSettings(setModalState),
                                    icon: const Icon(
                                      Icons.save_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('บันทึกเครื่องพิมพ์'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.slate700,
                                      side: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed:
                                      isSaving ||
                                          isConnectingPrinter ||
                                          isRetryingPrint
                                      ? null
                                      : () {
                                          Navigator.of(dialogContext).pop();
                                          _openReceiptSettings();
                                        },
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('เปิดหน้าตั้งค่าเต็ม'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.slate600,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _isPrinterFailureModalOpen = false;
    }
  }

  Widget _buildPrinterFailureHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF1F2), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE4E6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.print_disabled_rounded,
              color: AppColors.rose500,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'พิมพ์ใบเสร็จไม่สำเร็จ',
                  style: TextStyle(
                    color: Color(0xFF7F1D1D),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'เลือกเครื่องพิมพ์ในกล่องนี้ แล้วบันทึกเพื่อใช้กับ POS ทันที',
                  style: TextStyle(
                    color: Color(0xFF9F1239),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterFailureNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFEA580C),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _printerFailureModalShownCount >= 2
                  ? 'ถ้าไม่อยากให้เด้งอีกในรอบนี้ กด "ไม่ต้องแสดงอีก" ได้เลย'
                  : 'เลือก Wi-Fi หรือ Bluetooth แล้วกดพิมพ์อีกครั้งได้ทันที',
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _printerModalInputDecoration(
    String label,
    IconData icon, {
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppColors.slate400, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.rose500, width: 1.4),
      ),
    );
  }

  Widget _buildCopyChoice({
    required int copies,
    required int selectedCopies,
    required VoidCallback onTap,
  }) {
    final isActive = copies == selectedCopies;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColors.rose500 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.rose500 : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          '$copies',
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.slate700,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Future<bool> _printReceiptFromPos(
    Map<String, dynamic> receiptData, {
    bool showSuccess = false,
  }) async {
    if (_isPrintingReceipt) {
      if (mounted && showSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('กำลังพิมพ์อยู่ กรุณารอสักครู่'),
            backgroundColor: AppColors.slate800,
          ),
        );
      }
      return false;
    }

    _isPrintingReceipt = true;
    var success = false;
    try {
      success = await PrinterService.printReceipt(
        receiptData,
        widget.brandId,
      ).timeout(const Duration(seconds: 14), onTimeout: () => false);
    } catch (e) {
      debugPrint('POS print receipt failed: $e');
    } finally {
      _isPrintingReceipt = false;
    }

    if (!mounted) return success;

    if (success) {
      if (showSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('พิมพ์ใบเสร็จสำเร็จ'),
            backgroundColor: AppColors.emerald500,
          ),
        );
      }
      return true;
    }

    await _showPrinterSettingsAction(receiptData);
    return false;
  }

  void _hideTopNotification() {
    _topNotificationTimer?.cancel();
    _topNotificationTimer = null;
    _topNotificationEntry?.remove();
    _topNotificationEntry = null;
  }

  void _showTopNotification({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _hideTopNotification();
    _topNotificationEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.topCenter,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, -18 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _hideTopNotification,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  icon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.92),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_topNotificationEntry!);
    _topNotificationTimer = Timer(
      const Duration(seconds: 4),
      _hideTopNotification,
    );
  }

  @override
  void dispose() {
    _hideTopNotification();
    _barcodeController.dispose();
    super.dispose();
  }

  String _generateTableToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<void> _fetchOrderQuota() async {
    try {
      // 🌟 แก้ไข: ใช้ ApiService.baseUrl ตรงๆ โค้ดสะอาดขึ้น 10 เท่า
      final url = "${ApiService.baseUrl}/pos/quota";

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          final isLocked = data['isLocked'] ?? false;
          setState(() {
            _orderUsage = data['usage'] ?? 0;
            _orderLimit =
                data['limit'] == double.infinity || data['limit'] == null
                ? -1
                : (data['limit'] as num).toInt();
            _isLocked = isLocked;
            _currentPlan = data['plan'] ?? 'free';
          });
          if (isLocked) {
            _scheduleQuotaLimitWarning();
          }
        }
      }
    } catch (e) {
      print("โหลดข้อมูลโควต้าออเดอร์ผิดพลาด: $e");
    }
  }

  void _scheduleQuotaLimitWarning({bool force = false}) {
    if (!mounted || !_isLocked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showQuotaLimitWarning(force: force);
    });
  }

  Future<void> _showQuotaLimitWarning({bool force = false}) async {
    if (!mounted || !_isLocked || _isQuotaLimitWarningOpen) return;
    if (!force && _hasShownQuotaLimitWarning) return;

    _hasShownQuotaLimitWarning = true;
    _isQuotaLimitWarningOpen = true;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final quotaText = _orderLimit == -1
              ? 'ไม่จำกัด'
              : '$_orderUsage/$_orderLimit ออเดอร์';

          return Dialog(
            elevation: 0,
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.orange500.withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.orange50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: AppColors.orange600,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ถึงลิมิตสแกนสั่งอาหารแล้ว',
                                  style: TextStyle(
                                    color: AppColors.slate900,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    height: 1.15,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'ยังสามารถคิดเงินและปิดบิลใน POS ต่อได้ตามปกติ แต่ระบบสแกน QR สั่งอาหารอาจใช้งานไม่ได้ชั่วคราว',
                                  style: TextStyle(
                                    color: AppColors.slate600,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.orange600,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'โควตาปัจจุบัน: $quotaText',
                                style: const TextStyle(
                                  color: AppColors.slate700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.slate900,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'ปิด',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _isQuotaLimitWarningOpen = false;
    }
  }

  Future<void> _fetchBrandSettings() async {
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
        final brand = Map<String, dynamic>.from(data['brand'] ?? data ?? {});
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'cached_brand_settings_${widget.brandId}',
          jsonEncode(brand),
        );
        if (!mounted) return;
        setState(() {
          _brandSettings = brand;
        });
      }
    } catch (e) {
      print("โหลดข้อมูลร้านค้าล้มเหลว: $e");
    }
  }

  Future<void> _loadCachedPosData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final categories = await db.query(
        'categories',
        where: 'brand_id = ?',
        whereArgs: [widget.brandId],
        orderBy: 'sort_order ASC',
      );
      final products = await db.query(
        'products',
        where: 'brand_id = ?',
        whereArgs: [widget.brandId],
      );
      if (products.isEmpty) return;
      final discounts = await db.query(
        'discounts',
        where: 'brand_id = ?',
        whereArgs: [widget.brandId],
      );
      final cachedDiscounts = <Map<String, dynamic>>[];
      for (final row in discounts) {
        final discount = Map<String, dynamic>.from(row);
        discount['discount_products'] = await db.query(
          'discount_products',
          where: 'discount_id = ?',
          whereArgs: [discount['id']],
        );
        cachedDiscounts.add(discount);
      }
      final cachedCategories = categories
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      cachedCategories.insert(0, {'id': 'ALL', 'name': 'ทั้งหมด'});
      final prefs = await SharedPreferences.getInstance();
      final brandJson = prefs.getString(
        'cached_brand_settings_${widget.brandId}',
      );
      if (!mounted) return;
      setState(() {
        _categories = cachedCategories;
        _products = products
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _discounts = cachedDiscounts;
        if (brandJson != null) {
          _brandSettings = Map<String, dynamic>.from(jsonDecode(brandJson));
        }
        _isLoadingAPI = false;
      });
    } catch (error) {
      debugPrint('[OFFLINE POS] Cannot read local cache: $error');
    }
  }

  String? _productImageUrl(Map<String, dynamic> product) {
    const baseUrl =
        'https://xvhibjejvbriotfpunvv.supabase.co/storage/v1/object/public/images/';
    final raw = product['image_url'] ?? product['image_name'];
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return '$baseUrl${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Future<void> _cacheProductImages(List<Map<String, dynamic>> products) async {
    final appDirectory = await getApplicationSupportDirectory();
    final imageDirectory = Directory(
      path_util.join(appDirectory.path, 'pos_images', widget.brandId),
    );
    await imageDirectory.create(recursive: true);
    final db = await DatabaseHelper.instance.database;

    for (var start = 0; start < products.length; start += 4) {
      final end = math.min(start + 4, products.length);
      await Future.wait(
        products.sublist(start, end).map((product) async {
          final id = product['id']?.toString();
          final imageUrl = _productImageUrl(product);
          if (id == null || id.isEmpty || imageUrl == null) return;
          final extension = path_util.extension(Uri.parse(imageUrl).path);
          final safeExtension = extension.isNotEmpty && extension.length <= 6
              ? extension
              : '.jpg';
          final file = File(
            path_util.join(imageDirectory.path, '$id$safeExtension'),
          );
          try {
            if (!await file.exists() || await file.length() == 0) {
              final response = await http
                  .get(Uri.parse(imageUrl))
                  .timeout(const Duration(seconds: 15));
              if (response.statusCode != 200 || response.bodyBytes.isEmpty)
                return;
              await file.writeAsBytes(response.bodyBytes, flush: true);
            }
            await db.update(
              'products',
              {'local_image_path': file.path},
              where: 'id = ? AND brand_id = ?',
              whereArgs: [id, widget.brandId],
            );
            product['local_image_path'] = file.path;
          } catch (_) {
            // A later online sync retries failed image downloads.
          }
        }),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchPosData() async {
    try {
      final url = ApiService.initPos;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _categories = List<Map<String, dynamic>>.from(
            data['categories'] ?? [],
          );
          if (_categories.isEmpty || _categories.first['id'] != 'ALL') {
            _categories.insert(0, {'id': 'ALL', 'name': 'ทั้งหมด'});
          }
          _products = List<Map<String, dynamic>>.from(data['products'] ?? []);
          _tables = List<Map<String, dynamic>>.from(data['tables'] ?? []);
          _discounts = List<Map<String, dynamic>>.from(data['discounts'] ?? []);

          final allUnpaidOrders = List<Map<String, dynamic>>.from(
            data['unpaid_orders'] ?? [],
          );

          _unpaidOrders = allUnpaidOrders.where((order) {
            final status = order['status'];
            return status == 'pending' ||
                status == 'preparing' ||
                status == 'done';
          }).toList();

          _isLoadingAPI = false;
        });

        final db = await DatabaseHelper.instance.database;
        final previousProducts = await db.query(
          'products',
          columns: ['id', 'local_image_path'],
          where: 'brand_id = ?',
          whereArgs: [widget.brandId],
        );
        final localPaths = <String, String>{
          for (final row in previousProducts)
            if ((row['local_image_path']?.toString() ?? '').isNotEmpty)
              row['id'].toString(): row['local_image_path'].toString(),
        };
        await db.transaction((txn) async {
          for (var cat in data['categories'] ?? []) {
            await txn.insert('categories', {
              'id': cat['id'],
              'brand_id': widget.brandId,
              'name': cat['name'],
              'sort_order': cat['sort_order'] ?? 0,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }

          for (var prod in data['products'] ?? []) {
            await txn.insert('products', {
              'id': prod['id'],
              'category_id': prod['category_id'],
              'brand_id': widget.brandId,
              'barcode': prod['barcode'],
              'sku': prod['sku'],
              'name': prod['name'],
              'price': double.tryParse(prod['price']?.toString() ?? '0'),
              'price_special': double.tryParse(
                prod['price_special']?.toString() ?? '0',
              ),
              'price_jumbo': double.tryParse(
                prod['price_jumbo']?.toString() ?? '0',
              ),
              'image_url': prod['image_url'] ?? prod['image_name'],
              'local_image_path': localPaths[prod['id']?.toString()],
              'is_available': prod['is_available'] == false ? 0 : 1,
              'item_type': prod['item_type'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }

          for (var disc in data['discounts'] ?? []) {
            await txn.insert('discounts', {
              'id': disc['id'],
              'brand_id': widget.brandId,
              'type': disc['type'],
              'value': double.tryParse(disc['value']?.toString() ?? '0'),
              'start_date': disc['start_date'],
              'end_date': disc['end_date'],
              'apply_normal': disc['apply_normal'] == false ? 0 : 1,
              'apply_special': disc['apply_special'] == false ? 0 : 1,
              'apply_jumbo': disc['apply_jumbo'] == false ? 0 : 1,
              'apply_to': disc['apply_to'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);

            for (var dp in disc['discount_products'] ?? []) {
              await txn.insert('discount_products', {
                'discount_id': disc['id'],
                'product_id': dp['product_id'],
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        });
        unawaited(_cacheProductImages(_products));
        print("✅ [SQLITE] แคช Master Data สำเร็จ");
      } else {
        throw "Server ตอบกลับ: ${response.statusCode}";
      }
    } catch (e) {
      await _loadCachedPosData();
      if (mounted) setState(() => _isLoadingAPI = false);
      print("โหลดข้อมูลล้มเหลว: $e");
    }
  }

  void _triggerCartBounce() {
    if (!mounted) return;
    setState(() => _isCartBouncing = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _isCartBouncing = false);
    });
  }

  Map<String, dynamic> _calculatePrice(
    Map<String, dynamic> product,
    String variant,
  ) {
    double basePrice =
        double.tryParse(product['price']?.toString() ?? '0') ?? 0.0;
    if (variant == 'special' && product['price_special'] != null)
      basePrice = double.parse(product['price_special'].toString());
    if (variant == 'jumbo' && product['price_jumbo'] != null)
      basePrice = double.parse(product['price_jumbo'].toString());

    double originalPrice = basePrice;
    final now = DateTime.now();
    double bestDiscountAmount = 0.0;
    Map<String, dynamic>? bestPromoSnapshot;

    for (var discount in _discounts) {
      if (discount['start_date'] != null &&
          DateTime.parse(discount['start_date']).isAfter(now))
        continue;
      if (discount['end_date'] != null &&
          DateTime.parse(discount['end_date']).isBefore(now))
        continue;

      if (variant == 'normal' && discount['apply_normal'] == 0) continue;
      if (variant == 'special' && discount['apply_special'] == 0) continue;
      if (variant == 'jumbo' && discount['apply_jumbo'] == 0) continue;

      bool isApplicable = false;
      if (discount['apply_to'] == 'all') {
        isApplicable = true;
      } else if (discount['apply_to'] == 'specific') {
        final dpList = discount['discount_products'] as List?;
        if (dpList != null &&
            dpList.any((dp) => dp['product_id'] == product['id'])) {
          isApplicable = true;
        }
      }

      if (isApplicable) {
        double currentDiscount = 0.0;
        double discountValue =
            double.tryParse(discount['value'].toString()) ?? 0.0;

        if (discount['type'] == 'percentage') {
          currentDiscount = originalPrice * (discountValue / 100);
        } else if (discount['type'] == 'fixed') {
          currentDiscount = discountValue;
        }

        if (currentDiscount > bestDiscountAmount) {
          bestDiscountAmount = currentDiscount;
          bestPromoSnapshot = discount;
        }
      }
    }

    double rawFinalPrice = originalPrice - bestDiscountAmount;
    if (rawFinalPrice < 0) rawFinalPrice = 0;
    double finalPriceRounded = (rawFinalPrice * 4).round() / 4;

    return {
      'original': originalPrice,
      'final': finalPriceRounded,
      'discount': originalPrice - finalPriceRounded,
      'promotion_snapshot': bestPromoSnapshot,
    };
  }

  Future<void> _handleProductClick(Map<String, dynamic> product) async {
    if (product['price_special'] != null || product['price_jumbo'] != null) {
      final selectedVariant = await VariantModal.show(
        context,
        product,
        _calculatePrice,
      );
      if (selectedVariant != null) await _addToCart(product, selectedVariant);
    } else {
      await _addToCart(product, 'normal');
    }
  }

  Future<void> _addToCart(Map<String, dynamic> product, String variant) async {
    final draftOrderId = await _ensureWalkInDraftOrder();
    final pricing = _calculatePrice(product, variant);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    String? orderItemId;
    var nextQty = 1;

    setState(() {
      var existingIndex = _cart.indexWhere(
        (item) => item['id'] == product['id'] && item['variant'] == variant,
      );
      if (existingIndex > -1) {
        _cart[existingIndex]['qty'] += 1;
        orderItemId = _cart[existingIndex]['order_item_id']?.toString();
        nextQty = _cart[existingIndex]['qty'] as int;
      } else {
        orderItemId = const Uuid().v4();
        _cart.add({
          'order_item_id': orderItemId,
          'order_id': draftOrderId,
          'id': product['id'],
          'name': product['name'],
          'barcode': product['barcode'],
          'image_url': product['image_url'] ?? product['image_name'],
          'local_image_path': product['local_image_path'],
          'variant': variant,
          'price': pricing['final'],
          'original_price': pricing['original'],
          'discount': pricing['discount'],
          'promotion_snapshot': pricing['promotion_snapshot'],
          'qty': 1,
        });
      }
    });

    await _upsertWalkInDraftItem(
      orderId: draftOrderId,
      itemId: orderItemId!,
      product: product,
      variant: variant,
      pricing: pricing,
      quantity: nextQty,
      createdAt: nowIso,
    );
    await _updateWalkInDraftTotal();
    _triggerCartBounce();
  }

  Future<String> _ensureWalkInDraftOrder() async {
    if (_walkInDraftOrderId != null) return _walkInDraftOrderId!;

    final orderId = const Uuid().v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final db = await DatabaseHelper.instance.database;
    await db.insert('orders', {
      'id': orderId,
      'brand_id': widget.brandId,
      'table_label': 'Walk-in',
      'status': 'pending',
      'total_price': 0.0,
      'type': 'pos',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _walkInDraftOrderId = orderId;
    return orderId;
  }

  Future<void> _restoreWalkInDraftOrder() async {
    if (_walkInDraftOrderId != null || _cart.isNotEmpty) return;

    try {
      final db = await DatabaseHelper.instance.database;
      final orders = await db.query(
        'orders',
        where: 'brand_id = ? AND type = ? AND status = ?',
        whereArgs: [widget.brandId, 'pos', 'pending'],
        orderBy: 'updated_at DESC, created_at DESC',
        limit: 1,
      );
      if (orders.isEmpty) return;

      final orderId = orders.first['id']?.toString();
      if (orderId == null || orderId.isEmpty) return;

      final items = await db.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'created_at ASC',
      );

      final activeItems = <Map<String, dynamic>>[];
      final cancelledItems = <Map<String, dynamic>>[];

      for (final row in items) {
        final status = row['status']?.toString().toLowerCase() ?? 'active';
        final cartItem = _cartItemFromDraftRow(orderId, row);
        if (status == 'cancelled') {
          cancelledItems.add({
            ...cartItem,
            'status': 'cancelled',
            'cancelled_by': row['cancelled_by'],
            'cancelled_at': row['cancelled_at'],
          });
        } else {
          activeItems.add(cartItem);
        }
      }

      if (activeItems.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _walkInDraftOrderId = orderId;
        _cart
          ..clear()
          ..addAll(activeItems);
        _cancelledCartItems
          ..clear()
          ..addAll(cancelledItems);
      });
    } catch (error) {
      debugPrint('[OFFLINE POS] Cannot restore pending walk-in order: $error');
    }
  }

  Map<String, dynamic> _cartItemFromDraftRow(
    String orderId,
    Map<String, dynamic> row,
  ) {
    dynamic promotionSnapshot = row['promotion_snapshot'];
    if (promotionSnapshot is String && promotionSnapshot.trim().isNotEmpty) {
      try {
        promotionSnapshot = jsonDecode(promotionSnapshot);
      } catch (_) {}
    }

    final productId = row['product_id']?.toString();
    final product = productId == null
        ? null
        : _products.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['id']?.toString() == productId,
            orElse: () => null,
          );

    return {
      'order_item_id': row['id'],
      'order_id': orderId,
      'id': row['product_id'],
      'name': row['product_name'],
      'image_url': product?['image_url'],
      'local_image_path': product?['local_image_path'],
      'variant': row['variant'],
      'price': row['price'],
      'original_price': row['original_price'],
      'discount': row['discount'],
      'promotion_snapshot': promotionSnapshot,
      'note': row['note'],
      'qty': int.tryParse(row['quantity']?.toString() ?? '1') ?? 1,
    };
  }

  Future<void> _upsertWalkInDraftItem({
    required String orderId,
    required String itemId,
    required Map<String, dynamic> product,
    required String variant,
    required Map<String, dynamic> pricing,
    required int quantity,
    required String createdAt,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('order_items', {
      'id': itemId,
      'order_id': orderId,
      'product_id': product['id'],
      'product_name': product['name'],
      'quantity': quantity,
      'price': pricing['final'],
      'original_price': pricing['original'],
      'discount': pricing['discount'],
      'variant': variant,
      'promotion_snapshot': jsonEncode(pricing['promotion_snapshot'] ?? {}),
      'status': 'active',
      'created_at': createdAt,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _updateWalkInDraftTotal() async {
    final orderId = _walkInDraftOrderId;
    if (orderId == null) return;
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'orders',
      {
        'total_price': _rawTotal,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  String _currentUserId() {
    final token = _accessToken;
    if (token == null || token.isEmpty) return 'unknown';
    try {
      final parts = token.split('.');
      if (parts.length != 3) return 'unknown';
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload['sub']?.toString() ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  String? _currentUserUuidOrNull() {
    final userId = _currentUserId();
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(userId) ? userId : null;
  }

  Future<void> _onCancelWalkInCartItemClick(int index) async {
    if (_activeTab != 'pos') return;
    if (index < 0 || index >= _cart.length) return;

    final item = Map<String, dynamic>.from(_cart[index]);
    final itemName = item['name'] ?? item['product_name'] ?? 'รายการนี้';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'ยืนยันลบสินค้า',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('ต้องการลบ $itemName ออกจากสรุปยอดใช่ไหม?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่ลบ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose500),
            child: const Text(
              'ลบสินค้า',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final orderId = item['order_id']?.toString() ?? _walkInDraftOrderId;
    final itemId = item['order_item_id']?.toString();
    final cancelledBy = _currentUserUuidOrNull();

    setState(() {
      _cart.removeAt(index);
      _cancelledCartItems.add({
        ...item,
        'status': 'cancelled',
        'cancelled_by': cancelledBy,
        'cancelled_at': nowIso,
      });
    });

    final db = await DatabaseHelper.instance.database;
    if (itemId != null && itemId.isNotEmpty) {
      await db.update(
        'order_items',
        {
          'status': 'cancelled',
          'cancelled_by': cancelledBy,
          'cancelled_at': nowIso,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
    }

    if (_cart.isEmpty && orderId != null) {
      await _cancelEmptyWalkInDraftOrder(
        orderId: orderId,
        cancelledBy: cancelledBy,
        cancelledAt: nowIso,
      );
      if (mounted) {
        setState(() {
          _walkInDraftOrderId = null;
          _cancelledCartItems.clear();
        });
      }
    } else {
      await _updateWalkInDraftTotal();
    }
  }

  Future<void> _cancelEmptyWalkInDraftOrder({
    required String orderId,
    required String? cancelledBy,
    required String cancelledAt,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final orderRows = await db.query(
      'orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    final itemRows = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    final itemsToSync = itemRows.map((row) {
      final item = Map<String, dynamic>.from(row);
      item.remove('updated_at');
      return item;
    }).toList();

    await db.transaction((txn) async {
      await txn.update(
        'orders',
        {
          'status': 'cancelled',
          'total_price': 0.0,
          'cancelled_by': cancelledBy,
          'cancelled_at': cancelledAt,
          'updated_at': cancelledAt,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      final newOrderData = orderRows.isEmpty
          ? <String, dynamic>{
              'id': orderId,
              'brand_id': widget.brandId,
              'table_label': 'Walk-in',
              'status': 'cancelled',
              'total_price': 0.0,
              'type': 'pos',
              'created_at': cancelledAt,
              'updated_at': cancelledAt,
              'cancelled_by': cancelledBy,
              'cancelled_at': cancelledAt,
            }
          : {
              ...Map<String, dynamic>.from(orderRows.first),
              'status': 'cancelled',
              'total_price': 0.0,
              'cancelled_by': cancelledBy,
              'cancelled_at': cancelledAt,
              'updated_at': cancelledAt,
            };

      await txn.insert('sync_queue', {
        'type': 'PAYMENT',
        'payload': jsonEncode({
          'action': 'cancel_order',
          'orderId': orderId,
          'brandId': widget.brandId,
          'cancelledBy': cancelledBy,
          'cancelledAt': cancelledAt,
          'isNewOffline': true,
          'newOrderData': newOrderData,
          'itemsToSave': itemsToSync,
        }),
        'status': 'pending',
      });
    });
  }

  void _markSelectedTableItemCancelled({
    required String itemId,
    required String userId,
    required String cancelledAt,
  }) {
    void markItem(Map<String, dynamic> order) {
      final items = order['order_items'];
      if (items is! List) return;
      order['order_items'] = items.map((rawItem) {
        if (rawItem is! Map) return rawItem;
        final item = Map<String, dynamic>.from(rawItem);
        if (item['id']?.toString() == itemId) {
          item['status'] = 'cancelled';
          item['cancelled_by'] = userId;
          item['cancelled_at'] = cancelledAt;
        }
        return item;
      }).toList();
    }

    setState(() {
      if (_selectedOrder != null) markItem(_selectedOrder!);
      _unpaidOrders = _unpaidOrders.map((order) {
        final updated = Map<String, dynamic>.from(order);
        markItem(updated);
        return updated;
      }).toList();
    });
  }

  Future<void> _onCancelTableOrderItemClick(int index) async {
    if (_activeTab != 'tables' || _selectedOrder == null) return;
    final items = _selectedOrder!['order_items'] as List? ?? const [];
    if (index < 0 || index >= items.length || items[index] is! Map) return;

    final item = Map<String, dynamic>.from(items[index] as Map);
    if (_isCancelledItem(item)) return;

    final itemId = item['id']?.toString();
    if (itemId == null || itemId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'ยืนยันยกเลิกรายการ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'ต้องการยกเลิก ${item['product_name'] ?? item['name'] ?? 'รายการนี้'} ใช่ไหม?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose500),
            child: const Text(
              'ยกเลิกรายการ',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final userId = _currentUserId();
      final response = await http.post(
        Uri.parse(ApiService.syncOffline),
        headers: {
          'Content-Type': 'application/json',
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          'action': 'cancel_order_item',
          'itemId': itemId,
          'orderId': item['order_id'] ?? _selectedOrder!['id'],
          'brandId': widget.brandId,
          'cancelledAt': nowIso,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(response.body);
      }

      _markSelectedTableItemCancelled(
        itemId: itemId,
        userId: userId,
        cancelledAt: nowIso,
      );
      unawaited(_fetchPosData());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ยกเลิกรายการโต๊ะแล้ว'),
          backgroundColor: AppColors.emerald500,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ยกเลิกรายการไม่สำเร็จ: $e'),
          backgroundColor: AppColors.rose500,
        ),
      );
    }
  }

  Future<void> _handleCartItemRemove(int index) async {
    if (_activeTab == 'tables') {
      await _onCancelTableOrderItemClick(index);
      return;
    }
    await _onCancelWalkInCartItemClick(index);
  }

  String? _normalizeIdentity(dynamic value, String prefix) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return '$prefix:$text';
  }

  String? _tableIdentityForOrder(Map<String, dynamic> order) {
    const idFields = [
      'table_id',
      'tableId',
      'tableID',
      'table_uuid',
      'tableUuid',
      'table_uid',
      'tableUid',
    ];

    for (final field in idFields) {
      final identity = _normalizeIdentity(order[field], 'table');
      if (identity != null) return identity;
    }

    final table = order['table'];
    if (table is Map) {
      final tableMap = Map<String, dynamic>.from(table);
      for (final field in ['id', 'uuid', 'table_id']) {
        final identity = _normalizeIdentity(tableMap[field], 'table');
        if (identity != null) return identity;
      }
    }

    for (final field in [
      'table_access_token',
      'tableAccessToken',
      'access_token',
    ]) {
      final identity = _normalizeIdentity(order[field], 'token');
      if (identity != null) return identity;
    }

    return null;
  }

  bool _isCancelledItem(Map<String, dynamic> item) =>
      item['status']?.toString().toLowerCase() == 'cancelled';

  double _orderTotal(Map<String, dynamic> order) {
    final items = order['order_items'];
    if (items is List) {
      final hasCancelledItems = items.any((item) {
        if (item is! Map) return false;
        return _isCancelledItem(Map<String, dynamic>.from(item));
      });
      if (hasCancelledItems) {
        return items.fold<double>(0.0, (sum, item) {
          if (item is! Map) return sum;
          final itemMap = Map<String, dynamic>.from(item);
          if (_isCancelledItem(itemMap)) return sum;
          final price =
              double.tryParse(itemMap['price']?.toString() ?? '0') ?? 0.0;
          final qty =
              double.tryParse(
                (itemMap['qty'] ?? itemMap['quantity'] ?? 1).toString(),
              ) ??
              1.0;
          return sum + (price * qty);
        });
      }
    }

    final parsedTotal = double.tryParse(order['total_price']?.toString() ?? '');
    if (parsedTotal != null) return parsedTotal;

    if (items is! List) return 0.0;

    return items.fold<double>(0.0, (sum, item) {
      if (item is! Map) return sum;
      final itemMap = Map<String, dynamic>.from(item);
      if (_isCancelledItem(itemMap)) return sum;
      final price = double.tryParse(itemMap['price']?.toString() ?? '0') ?? 0.0;
      final qty =
          double.tryParse(
            (itemMap['qty'] ?? itemMap['quantity'] ?? 1).toString(),
          ) ??
          1.0;
      return sum + (price * qty);
    });
  }

  List<String> _sourceOrderIdsFor(Map<String, dynamic>? order) {
    if (order == null) return const [];
    final rawIds = order['_source_order_ids'];
    if (rawIds is List) {
      return rawIds
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty && id.toLowerCase() != 'null')
          .toList();
    }

    final id = order['id']?.toString().trim();
    if (id == null || id.isEmpty || id.toLowerCase() == 'null') return const [];
    return [id];
  }

  List<String> _uniqueTextList(Iterable<dynamic> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      if (seen.add(text)) result.add(text);
    }
    return result;
  }

  List<String> _tableTokens(Map<String, dynamic> table) {
    final rawTokens = table['access_tokens'];
    if (rawTokens is List) {
      final tokens = _uniqueTextList(rawTokens);
      if (tokens.isNotEmpty) return tokens;
    }
    return _uniqueTextList([table['access_token']]);
  }

  List<String> _usedTableTokensForOrder(Map<String, dynamic>? order) {
    if (order == null) return const [];
    final tokens = <dynamic>[];

    final groupedTokens = order['_table_access_tokens'];
    if (groupedTokens is List) tokens.addAll(groupedTokens);

    for (final field in [
      'table_access_token',
      'tableAccessToken',
      'access_token',
    ]) {
      tokens.add(order[field]);
    }

    final sourceOrders = order['_source_orders'];
    if (sourceOrders is List) {
      for (final source in sourceOrders) {
        if (source is! Map) continue;
        for (final field in [
          'table_access_token',
          'tableAccessToken',
          'access_token',
        ]) {
          tokens.add(source[field]);
        }
      }
    }

    return _uniqueTextList(tokens);
  }

  List<String> _nextTableTokensAfterPayment(Map<String, dynamic>? order) {
    if (order == null) return const [];
    final tableId = order['table_id']?.toString();
    final tableLabel = order['table_label']?.toString();
    Map<String, dynamic>? table;
    for (final item in _tables) {
      final matchesId = tableId != null && item['id']?.toString() == tableId;
      final matchesLabel =
          tableLabel != null && item['label']?.toString() == tableLabel;
      if (matchesId || matchesLabel) {
        table = item;
        break;
      }
    }

    final currentTokens = table == null ? <String>[] : _tableTokens(table);
    final usedTokens = _usedTableTokensForOrder(order).toSet();
    final remaining = currentTokens
        .where((token) => !usedTokens.contains(token))
        .toList();
    return remaining.isNotEmpty ? remaining : [_generateTableToken()];
  }

  List<Map<String, dynamic>> get _unpaidTableOrders {
    final grouped = <String, Map<String, dynamic>>{};
    final result = <Map<String, dynamic>>[];

    for (final rawOrder in _unpaidOrders) {
      final order = Map<String, dynamic>.from(rawOrder);
      final tableKey = _tableIdentityForOrder(order);
      final orderId = order['id']?.toString().trim();
      final items = List<dynamic>.from(
        order['order_items'] as List? ?? const [],
      );

      if (tableKey == null) {
        order['_source_order_ids'] = orderId == null || orderId.isEmpty
            ? <String>[]
            : <String>[orderId];
        order['_source_orders'] = <Map<String, dynamic>>[order];
        result.add(order);
        continue;
      }

      final group = grouped.putIfAbsent(tableKey, () {
        final first = Map<String, dynamic>.from(order);
        first['id'] = 'table-group-$tableKey';
        first['_table_group_key'] = tableKey;
        first['_source_order_ids'] = <String>[];
        first['_source_orders'] = <Map<String, dynamic>>[];
        first['_table_access_tokens'] = <String>[];
        first['order_items'] = <dynamic>[];
        first['total_price'] = 0.0;
        result.add(first);
        return first;
      });

      final sourceIds = group['_source_order_ids'] as List<String>;
      if (orderId != null &&
          orderId.isNotEmpty &&
          !sourceIds.contains(orderId)) {
        sourceIds.add(orderId);
      }

      (group['_source_orders'] as List<Map<String, dynamic>>).add(order);
      (group['order_items'] as List<dynamic>).addAll(items);
      group['total_price'] = _orderTotal(group) + _orderTotal(order);
      final groupTokens = group['_table_access_tokens'] as List<String>;
      final orderToken = order['table_access_token']?.toString().trim();
      if (orderToken != null &&
          orderToken.isNotEmpty &&
          orderToken.toLowerCase() != 'null' &&
          !groupTokens.contains(orderToken)) {
        groupTokens.add(orderToken);
      }
      group['_order_count'] = sourceIds.length;
    }

    return result;
  }

  double get _rawTotal {
    if (_activeTab == 'tables' && _selectedOrder != null) {
      return _orderTotal(_selectedOrder!);
    }
    return _cart.fold(
      0.0,
      (sum, item) => sum + ((item['price'] as num) * (item['qty'] as num)),
    );
  }

  double get _payableAmount =>
      _paymentMethod == 'cash' ? ((_rawTotal * 4).ceil() / 4) : _rawTotal;

  int get _totalItems {
    if (_activeTab == 'tables' && _selectedOrder != null) {
      final items = _selectedOrder!['order_items'] as List? ?? const [];
      return items.where((item) {
        if (item is! Map) return false;
        return !_isCancelledItem(Map<String, dynamic>.from(item));
      }).length;
    }
    return _cart.fold(0, (sum, item) => sum + (item['qty'] as int));
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'th_TH',
      symbol: '฿',
      decimalDigits: 2,
    ).format(amount);
  }

  Future<void> _openTableSelector() async {
    if (_isLocked) {
      await _showQuotaLimitWarning(force: true);
    }

    if (!mounted) return;

    TableSelectorModal.show(
      context: context,
      tables: _tables,
      unpaidOrders: _unpaidOrders,
      onTableSelected: (tableInfo) {
        _showTableQrModal(tableInfo);
      },
    );
  }

  Future<void> _showTableQrModal(Map<String, dynamic> table) async {
    if (_isLocked) {
      await _showQuotaLimitWarning();
    }

    final brandId = widget.brandId.trim().isNotEmpty
        ? widget.brandId.trim()
        : (await StorageService.getBrandId()).trim();

    if (!mounted) return;

    if (brandId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบรหัสร้านค้า กรุณาเข้าสู่ระบบใหม่'),
          backgroundColor: AppColors.rose500,
        ),
      );
      return;
    }

    await TableQrModal.show(
      context,
      table['label'] ?? 'ไม่ทราบ',
      table['access_token'] ?? '0000',
      brandId,
      table['id'].toString(),
      accessTokens: _tableTokens(table),
      qrMode:
          (_brandSettings['table_qr_mode'] ??
                  _brandSettings['config']?['qr_mode'] ??
                  'rotating')
              .toString(),
      authToken: _accessToken ?? '',
    );

    if (mounted) {
      await _fetchPosData();
    }
  }

  void _handleBarcodeScan(String scannedCode) {
    if (scannedCode.trim().isEmpty) return;
    final foundProduct = _products.firstWhere(
      (p) => p['barcode'] == scannedCode || p['sku'] == scannedCode,
      orElse: () => <String, dynamic>{},
    );
    if (foundProduct.isNotEmpty) {
      _handleProductClick(foundProduct);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เพิ่ม ${foundProduct['name']} ลงตะกร้าแล้ว'),
          backgroundColor: AppColors.emerald500,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่พบสินค้ารหัส: $scannedCode'),
          backgroundColor: AppColors.rose500,
        ),
      );
    }
    _barcodeController.clear();
  }

  Future<void> _processPayment(double receivedAmount) async {
    print("========================================");
    print("🚀 [CHECKOUT] 1. เริ่มกระบวนการคิดเงิน...");
    print(
      "💰 ยอดสุทธิ: $_payableAmount | รับเงิน: $receivedAmount | วิธีจ่าย: $_paymentMethod",
    );

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final localPayId = const Uuid().v4();
      final selectedOrder = _selectedOrder;

      double changeAmount = _paymentMethod == 'promptpay'
          ? 0.0
          : (receivedAmount - _payableAmount);
      if (changeAmount < 0) changeAmount = 0.0;
      print("💵 [CHECKOUT] 2. คำนวณเงินทอน: $changeAmount");

      final sourceOrderIds = _activeTab == 'tables'
          ? _sourceOrderIdsFor(selectedOrder)
          : <String>[];
      final selectedTableId = _activeTab == 'tables' && selectedOrder != null
          ? selectedOrder['table_id']
          : null;
      final selectedOrderId = selectedOrder == null
          ? null
          : selectedOrder['id']?.toString();
      final selectedTableLabel = selectedOrder == null
          ? null
          : selectedOrder['table_label']?.toString();

      final selectedOrderItems = selectedOrder == null
          ? null
          : selectedOrder['order_items'];

      final tableOrderFallbackId = const Uuid().v4();

      String finalOrderId = _activeTab == 'pos'
          ? await _ensureWalkInDraftOrder()
          : (sourceOrderIds.isNotEmpty
                ? sourceOrderIds.first
                : (selectedOrderId ?? tableOrderFallbackId));

      String tableLabel = _activeTab == 'tables'
          ? (selectedTableLabel ?? '?')
          : 'Walk-in';
      String orderType = _activeTab == 'tables' ? 'table' : 'pos';

      final usedTableTokens = _activeTab == 'tables'
          ? _usedTableTokensForOrder(selectedOrder)
          : <String>[];
      final nextTableTokens = _activeTab == 'tables'
          ? _nextTableTokensAfterPayment(selectedOrder)
          : <String>[];
      print(
        "🍽️ [CHECKOUT] 3. ข้อมูลบิล -> Type: $orderType | โต๊ะ: $tableLabel | Order ID: $finalOrderId",
      );
      if (orderType == 'table') {
        print(
          "[CHECKOUT] Used table tokens: $usedTableTokens | Remaining after pay: $nextTableTokens",
        );
      }

      List<Map<String, dynamic>> itemsToSave = [];

      if (_activeTab == 'pos') {
        final activeItemsToSave = _cart
            .map(
              (i) => <String, dynamic>{
                'id': i['order_item_id'] ?? const Uuid().v4(),
                'order_id': finalOrderId,
                'product_id': i['id'],
                'product_name': i['name'],
                'quantity': i['quantity'] ?? i['qty'] ?? 1,
                'price': i['price'],
                'original_price': i['original_price'],
                'discount': i['discount'],
                'variant': i['variant'],
                'note': i['note'],
                'promotion_snapshot': i['promotion_snapshot'],
                'status': 'active',
                'created_at': nowIso,
              },
            )
            .toList();
        final cancelledItemsToSave = _cancelledCartItems
            .map(
              (i) => <String, dynamic>{
                'id': i['order_item_id'] ?? const Uuid().v4(),
                'order_id': finalOrderId,
                'product_id': i['product_id'] ?? i['id'],
                'product_name': i['product_name'] ?? i['name'] ?? 'Unknown',
                'quantity': i['quantity'] ?? i['qty'] ?? 1,
                'price': i['price'] ?? 0.0,
                'original_price': i['original_price'],
                'discount': i['discount'],
                'variant': i['variant'],
                'note': i['note'],
                'promotion_snapshot': i['promotion_snapshot'],
                'status': 'cancelled',
                'cancelled_by': i['cancelled_by'],
                'cancelled_at': i['cancelled_at'] ?? nowIso,
                'created_at': nowIso,
              },
            )
            .toList();
        itemsToSave = [...activeItemsToSave, ...cancelledItemsToSave];
      } else {
        final rawItems = List<Map<String, dynamic>>.from(
          selectedOrderItems ?? [],
        );
        itemsToSave = rawItems.where((i) => !_isCancelledItem(i)).map((i) {
          var mapped = Map<String, dynamic>.from(i);
          mapped['order_id'] = finalOrderId;
          mapped.remove('updated_at');
          return mapped;
        }).toList();
      }
      final receiptItems = itemsToSave
          .where((item) => !_isCancelledItem(item))
          .toList();

      print(
        "📦 [CHECKOUT] 4. เตรียม Item ลงฐานข้อมูลจำนวน: ${itemsToSave.length} รายการ",
      );

      final paymentRepo = PaymentRepository();

      print("💾 [SQLITE] 5. เริ่มบันทึกลง SQLite & Sync Queue...");
      await paymentRepo.savePaymentToLocal(
        newOrderData: {
          'id': finalOrderId,
          'brand_id': widget.brandId,
          'table_label': tableLabel,
          if (_activeTab == 'tables') ...{
            'table_id': selectedTableId,
            'table_access_token': usedTableTokens.isNotEmpty
                ? usedTableTokens.first
                : null,
          },
          'status': 'paid',
          'total_price': _payableAmount,
          'type': orderType,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
        itemsToSave: itemsToSave,
        paiOrderData: {
          'id': localPayId,
          'order_id': finalOrderId,
          'brand_id': widget.brandId,
          'total_amount': _payableAmount,
          'received_amount': _paymentMethod == 'promptpay'
              ? _payableAmount
              : receivedAmount,
          'change_amount': changeAmount,
          'payment_method': _paymentMethod.toUpperCase(),
          'created_at': nowIso,
        },
        syncPayload: {
          'cartItems': _activeTab == 'pos' ? _cart : selectedOrderItems,
          'cancelledCartItems': _activeTab == 'pos'
              ? _cancelledCartItems
              : const <Map<String, dynamic>>[],
          'brandId': widget.brandId,
          'type': _activeTab,
          'used_tokens': usedTableTokens,
          'next_tokens': nextTableTokens,
          'table_label': tableLabel,
          'source_order_ids': sourceOrderIds,
          'table_id': selectedTableId,
        },
      );

      print("✅ [SQLITE] บันทึกลงเครื่องสำเร็จ!");

      print("🖨️ [PRINTER] กำลังสั่งพิมพ์ใบเสร็จ...");
      final receiptData = {
        'brand_name': _brandSettings['name'] ?? 'ร้านของคุณ',
        'table_label': tableLabel,
        'order_id': finalOrderId,
        'items': receiptItems,
        'total_amount': _payableAmount,
        'payment_method': _paymentMethod.toUpperCase(),
        'received_amount': _paymentMethod == 'promptpay'
            ? _payableAmount
            : receivedAmount,
        'change_amount': changeAmount,
        'cashier_name': 'System',
      };
      unawaited(_printReceiptFromPos(receiptData));

      print("🧾 [UI] 6. เปิด Modal ใบเสร็จ...");
      if (mounted) {
        CompletedReceiptModal.show(
          context,
          {
            'brand_name': _brandSettings['name'] ?? 'ร้านของคุณ',
            'table_label': tableLabel,
            'order_id': finalOrderId,
            'items': receiptItems,
            'payment_method': _paymentMethod.toUpperCase(),
            'total_amount': _payableAmount,
            'received_amount': _paymentMethod == 'promptpay'
                ? _payableAmount
                : receivedAmount,
            'change_amount': changeAmount,
            'cashier_name': 'System',
          },
          () {
            setState(() {
              if (_activeTab == 'pos') {
                _cart.clear();
                _cancelledCartItems.clear();
                _walkInDraftOrderId = null;
              } else {
                _selectedOrder = null;
                if (selectedTableId != null && nextTableTokens.isNotEmpty) {
                  _tables = _tables.map((table) {
                    if (table['id']?.toString() != selectedTableId.toString())
                      return table;
                    return {
                      ...table,
                      'access_token': nextTableTokens.first,
                      'access_tokens': nextTableTokens,
                      'status': 'available',
                    };
                  }).toList();
                }
              }
            });
            _fetchPosData();
            _fetchOrderQuota();
          },
          onPrint: () async {
            await _printReceiptFromPos(receiptData, showSuccess: true);
          },
        );
      }

      if (_activeTab == 'tables' && widget.brandId.isNotEmpty) {
        print("☁️ [BACKGROUND] 7. เริ่มยิง API ล้างโต๊ะขึ้น Cloud...");

        final checkoutOrderIds = sourceOrderIds.isNotEmpty
            ? sourceOrderIds
            : [finalOrderId];

        Future(() async {
          try {
            // 🌟 แก้ไข: ใช้ ApiService.baseUrl ตรงๆ โค้ดสะอาดขึ้น 10 เท่า
            final checkoutApiUrl = "${ApiService.baseUrl}/pos/checkout";

            for (final checkoutOrderId in checkoutOrderIds) {
              if (checkoutOrderId != checkoutOrderIds.first) continue;
              print(
                "   -> 📡 [POST] Checkout: $checkoutApiUrl ($checkoutOrderId)",
              );
              final response = await http.post(
                Uri.parse(checkoutApiUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $_accessToken',
                },
                body: jsonEncode({
                  'order_id': checkoutOrderId,
                  'order_ids': checkoutOrderIds,
                  'payment_id': localPayId,
                  'table_id': selectedTableId,
                  'table_label': tableLabel,
                  'used_tokens': usedTableTokens,
                  'now_iso': nowIso,
                }),
              );

              if (response.statusCode == 200) {
                print(
                  "✅ [BACKGROUND] เคลียร์ออเดอร์ $checkoutOrderId & อัปเดต Token โต๊ะ สำเร็จ!",
                );
              } else {
                print(
                  "❌ [BACKGROUND ERROR] API Checkout $checkoutOrderId ล้มเหลว: ${response.body}",
                );
              }
            }
          } catch (e) {
            print("❌ [BACKGROUND ERROR] ยิงอัปเดต Cloud ล้มเหลว: $e");
          }
        });

        Future(() async {
          try {
            // 🌟 แก้ไข: ใช้ ApiService.baseUrl ตรงๆ โค้ดสะอาดขึ้น 10 เท่า
            final fcmApiUrl = "${ApiService.baseUrl}/send-notification";
            final currentFcmToken = await FirebaseMessaging.instance.getToken();

            print(
              "📣 [FCM] กำลังยิงแจ้งเตือนไปบอกเครื่องอื่นว่าคิดเงินแล้ว...",
            );
            final response = await http.post(
              Uri.parse(fcmApiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_accessToken',
              },
              body: jsonEncode({
                'brandId': widget.brandId,
                'message': 'โต๊ะ $tableLabel ชำระเงินเรียบร้อยแล้ว!',
                'type': 'ORDER_PAID',
                'excludeToken': currentFcmToken,
                'title': '💰 ชำระเงินสำเร็จ',
              }),
            );
            if (response.statusCode == 200) {
              print("✅ [FCM] ยิงแจ้งเตือน ORDER_PAID ไปยังเครื่องอื่นสำเร็จ!");
            } else {
              print(
                "❌ [FCM ERROR] ยิง FCM พลาด (Status: ${response.statusCode})",
              );
            }
          } catch (e) {
            print("❌ [FCM ERROR] Network Error: $e");
          }
        });
      }
      print("========================================");
    } catch (e, stacktrace) {
      print("❌❌❌ [CRITICAL ERROR] การชำระเงินล้มเหลว!");
      print("Error: $e");
      print("StackTrace: $stacktrace");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("บันทึกการชำระเงินล้มเหลว: $e"),
            backgroundColor: AppColors.rose500,
          ),
        );
      }
    }
  }

  Future<void> _onMainPaymentClick() async {
    if (_payableAmount <= 0) return;

    if (_paymentMethod == 'promptpay') {
      String promptPayNum = _brandSettings['promptpay_number'] ?? '';
      final promptPayItems = _activeTab == 'pos'
          ? List<dynamic>.from(_cart)
          : List<dynamic>.from(
              (_selectedOrder?['order_items'] as List?) ?? const [],
            );
      final promptPayTableLabel = _activeTab == 'tables'
          ? (_selectedOrder?['table_label']?.toString() ?? '?')
          : 'Walk-in';
      final promptPayReceiptData = {
        'brand_name': _brandSettings['name'] ?? 'ร้านของคุณ',
        'table_label': promptPayTableLabel,
        'items': promptPayItems,
        'total_amount': _payableAmount,
        'payment_method': 'PROMPTPAY',
      };

      PromptPayModal.show(
        context: context,
        payableAmount: _payableAmount,
        promptPayNum: promptPayNum,
        formatCurrency: _formatCurrency,
        onPrintReceiptWithQr: () async {
          final cleanedPromptPay = promptPayNum.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
          final success = await PrinterService.printPromptPayReceipt(
            promptPayReceiptData,
            widget.brandId,
            promptPayId: cleanedPromptPay,
            amount: _payableAmount,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'พิมพ์ใบพร้อม QR สำเร็จ'
                    : 'พิมพ์ใบพร้อม QR ไม่สำเร็จ',
              ),
              backgroundColor: success
                  ? AppColors.emerald500
                  : AppColors.rose500,
            ),
          );
        },
        onConfirm: () => _processPayment(_payableAmount),
      );
    } else {
      final dynamic result = await CashModal.show(context, _payableAmount);

      if (result is double) {
        _processPayment(result);
      } else if (result == true) {
        _processPayment(_payableAmount);
      }
    }
  }

  Future<void> _onCancelOrderClick() async {
    final bool isWalkIn = (_activeTab == 'pos');

    if (isWalkIn && _cart.isEmpty) return;
    if (!isWalkIn && _selectedOrder == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'ยืนยันยกเลิกออเดอร์',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'คุณต้องการยกเลิกออเดอร์นี้ใช่หรือไม่?\nการยกเลิกจะถูกบันทึกในระบบ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose500),
            child: const Text(
              'ใช่, ยกเลิกออเดอร์',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    String userId = 'unknown';
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      try {
        final parts = _accessToken!.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          );
          userId = payload['sub'] ?? 'unknown';
        }
      } catch (_) {}
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final db = await DatabaseHelper.instance.database;
    final cancelledBy = _currentUserUuidOrNull();

    try {
      if (isWalkIn) {
        // สร้างหัวออเดอร์สำหรับ Walk-in ที่ถูกยกเลิก
        final String cancelOrderId = _walkInDraftOrderId ?? const Uuid().v4();
        final allWalkInItems = [..._cart, ..._cancelledCartItems];
        final itemsToCancel = allWalkInItems
            .map(
              (item) => {
                'id': item['order_item_id'] ?? const Uuid().v4(),
                'order_id': cancelOrderId,
                'product_id': item['product_id'] ?? item['id'],
                'product_name':
                    item['product_name'] ?? item['name'] ?? 'Unknown',
                'quantity': item['quantity'] ?? item['qty'] ?? 1,
                'price': item['price'] ?? 0.0,
                'original_price': item['original_price'],
                'discount': item['discount'],
                'variant': item['variant'],
                'note': item['note'],
                'promotion_snapshot': item['promotion_snapshot'] is String
                    ? item['promotion_snapshot']
                    : jsonEncode(item['promotion_snapshot'] ?? {}),
                'created_at': nowIso,
                'status': 'cancelled',
                'cancelled_by': cancelledBy,
                'cancelled_at': nowIso,
              },
            )
            .toList();

        await db.transaction((txn) async {
          // บันทึกหัวออเดอร์
          await txn.insert('orders', {
            'id': cancelOrderId,
            'brand_id': widget.brandId,
            'table_label': 'Walk-in',
            'status': 'cancelled',
            'total_price': _payableAmount,
            'type': 'pos',
            'created_at': nowIso,
            'updated_at': nowIso,
            'cancelled_by': cancelledBy,
            'cancelled_at': nowIso,
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          // บันทึกรายการสินค้าในตะกร้า
          for (var item in itemsToCancel) {
            await txn.insert(
              'order_items',
              item,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          // โยนลง sync_queue เพื่อส่งไปให้ cloud สรุปยอด
          await txn.insert('sync_queue', {
            'type': 'PAYMENT',
            'payload': jsonEncode({
              'action': 'cancel_order',
              'orderId': cancelOrderId,
              'brandId': widget.brandId,
              'cancelledBy': cancelledBy,
              'cancelledAt': nowIso,
              'isNewOffline': true, // เป็นออเดอร์ที่เกิดออฟไลน์ใหม่เลย
              'newOrderData': {
                'id': cancelOrderId,
                'brand_id': widget.brandId,
                'table_label': 'Walk-in',
                'status': 'cancelled',
                'total_price': _payableAmount,
                'type': 'pos',
                'created_at': nowIso,
                'updated_at': nowIso,
                'cancelled_by': cancelledBy,
                'cancelled_at': nowIso,
              },
              'itemsToSave': itemsToCancel,
            }),
            'status': 'pending',
          });
        });

        setState(() {
          _cart.clear();
          _cancelledCartItems.clear();
          _walkInDraftOrderId = null;
        });
      } else {
        // กรณีเป็นบิลที่ดึงมาจากโต๊ะ
        final orderId = _selectedOrder!['id'];
        final sourceOrderIds = _sourceOrderIdsFor(_selectedOrder);
        final cancelOrderIds = sourceOrderIds.isNotEmpty
            ? sourceOrderIds
            : [orderId.toString()];
        final primaryCancelOrderId = cancelOrderIds.first;
        final response = await http.post(
          Uri.parse(ApiService.syncOffline),
          headers: {
            'Content-Type': 'application/json',
            if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
          },
          body: jsonEncode({
            'action': 'cancel_order',
            'orderId': primaryCancelOrderId,
            'orderIds': cancelOrderIds,
            'brandId': widget.brandId,
            'cancelledAt': nowIso,
          }),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception(response.body);
        }
        await db.transaction((txn) async {
          await txn.update(
            'orders',
            {
              'status': 'cancelled',
              'cancelled_by': userId,
              'cancelled_at': nowIso,
              'updated_at': nowIso,
            },
            where:
                'id IN (${List.filled(cancelOrderIds.length, '?').join(',')})',
            whereArgs: cancelOrderIds,
          );

          await txn.insert('sync_queue', {
            'type': 'PAYMENT',
            'payload': jsonEncode({
              'action': 'cancel_order',
              'orderId': primaryCancelOrderId,
              'orderIds': cancelOrderIds,
              'brandId': widget.brandId,
              'cancelledBy': userId,
              'cancelledAt': nowIso,
            }),
            'status': 'pending',
          });
        });

        setState(() {
          _selectedOrder = null;
          _unpaidOrders = _unpaidOrders
              .where(
                (order) => !cancelOrderIds.contains(order['id']?.toString()),
              )
              .toList();
        });
      }

      _fetchPosData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยกเลิกออเดอร์และบันทึกออฟไลน์แล้ว'),
            backgroundColor: AppColors.emerald500,
          ),
        );
      }
    } catch (e) {
      print('❌ Error cancelling order offline: $e');
    }
  }

  void _showMobileCartModal() {
    final rootMediaQuery = MediaQuery.of(context);
    final safeTop = rootMediaQuery.viewPadding.top;
    final sheetHeight = rootMediaQuery.size.height - safeTop;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SizedBox(
              height: sheetHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: CartPanel(
                        activeTab: _activeTab,
                        selectedOrder: _selectedOrder,
                        cart: _cart,
                        paymentMethod: _paymentMethod,
                        rawTotal: _rawTotal,
                        payableAmount: _payableAmount,
                        showProductImages: _showProductImages,
                        formatCurrency: _formatCurrency,
                        onRemoveFromCart: (index) async {
                          await _handleCartItemRemove(index);
                          setState(() {});
                          setModalState(() {});
                        },
                        onCancelOrder: _activeTab == 'tables'
                            ? () async {
                                await _onCancelOrderClick();
                                setState(() {});
                                setModalState(() {});
                              }
                            : null,
                        onPaymentMethodChanged: (method) {
                          setModalState(() => _paymentMethod = method);
                          setState(() => _paymentMethod = method);
                        },
                        onMainPaymentClick: () {
                          Navigator.pop(context);
                          _onMainPaymentClick();
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Material(
                      color: AppColors.slate100,
                      shape: const CircleBorder(),
                      elevation: 1,
                      child: IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 21,
                          height: 21,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.slate500,
                          size: 13,
                        ),
                        tooltip: 'ปิด',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 1024;
    final pagePadding = isDesktop
        ? const EdgeInsets.fromLTRB(24, 0, 24, 24)
        : const EdgeInsets.all(8);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgLight,
      drawer: const AppSidebar(activeMenu: 'pos'),
      body: _isLoadingAPI
          ? const SuparPosLoading(
              message: 'กำลังโหลดข้อมูลร้านและสินค้า',
              fullScreen: false,
            )
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: Padding(
                    padding: pagePadding,
                    child: isDesktop
                        ? _buildDesktopLayout()
                        : _buildMobileLayout(),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: _buildLeftSection()),
        const SizedBox(width: 24),
        Expanded(
          flex: 5,
          child: AnimatedScale(
            scale: _isCartBouncing ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            child: Container(
              key: _desktopCartKey,
              child: CartPanel(
                activeTab: _activeTab,
                selectedOrder: _selectedOrder,
                cart: _cart,
                paymentMethod: _paymentMethod,
                rawTotal: _rawTotal,
                payableAmount: _payableAmount,
                showProductImages: _showProductImages,
                formatCurrency: _formatCurrency,
                onRemoveFromCart: _handleCartItemRemove,
                onCancelOrder: _activeTab == 'tables'
                    ? _onCancelOrderClick
                    : null,
                onPaymentMethodChanged: (method) =>
                    setState(() => _paymentMethod = method),
                onMainPaymentClick: _onMainPaymentClick,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(child: _buildLeftSection()),
        AnimatedScale(
          scale: _isCartBouncing ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          child: Container(
            key: _mobileCartKey,
            child: MobileBottomCart(
              totalItems: _totalItems,
              payableAmount: _payableAmount,
              formatCurrency: _formatCurrency,
              onTap: _showMobileCartModal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftSection() {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final categoryProducts = _selectedCategory == 'ALL'
        ? _products
        : _products
              .where((p) => p['category_id'] == _selectedCategory)
              .toList();
    final displayProducts = _showBarcodeProducts
        ? categoryProducts
        : categoryProducts.where((p) => !_hasBarcode(p['barcode'])).toList();
    final unpaidTableOrders = _unpaidTableOrders;

    return Column(
      children: [
        PosTopBar(
          activeTab: _activeTab,
          unpaidCount: unpaidTableOrders.length,
          onMenuPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
          onTabChanged: (tab) => setState(() => _activeTab = tab),
          quotaLabel: _orderLimit == -1
              ? (_currentPlan == 'ultimate'
                    ? 'ULTIMATE 👑'
                    : _currentPlan == 'pro'
                    ? 'PRO ✨'
                    : 'BASIC 🥉')
              : "$_orderUsage/$_orderLimit",

          isQuotaLocked: _isLocked,
          planType: _currentPlan,
          onQrButtonPressed: _openTableSelector,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isDesktop ? 32 : 16),
              border: Border.all(color: AppColors.slate100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _activeTab == 'tables'
                ? TableList(
                    unpaidOrders: unpaidTableOrders,
                    selectedOrder: _selectedOrder,
                    onSelectOrder: (order) =>
                        setState(() => _selectedOrder = order),
                    formatCurrency: _formatCurrency,
                  )
                : ProductGrid(
                    categories: _categories,
                    selectedCategory: _selectedCategory,
                    onCategorySelected: (id) =>
                        setState(() => _selectedCategory = id),
                    displayProducts: displayProducts,
                    barcodeController: _barcodeController,
                    onProductClick: _handleProductClick,
                    calculatePrice: _calculatePrice,
                    formatCurrency: _formatCurrency,
                    showProductImages: _showProductImages,
                    onCameraPressed: () {
                      BarcodeScannerModal.show(context, (scannedCode) {
                        _handleBarcodeScan(scannedCode);
                      });
                    },
                    onBarcodeSubmitted: (code) {
                      _handleBarcodeScan(code);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  bool _hasBarcode(dynamic value) {
    if (value == null) return false;
    final barcode = value.toString().trim();
    return barcode.isNotEmpty && barcode.toLowerCase() != 'null';
  }
}
