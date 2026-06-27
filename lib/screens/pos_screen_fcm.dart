part of 'pos_screen.dart';

extension PosFcmExtension on _PosScreenState {

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

}
