import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/printer_service.dart';
import 'storage_service.dart';

class AutoPrintService with WidgetsBindingObserver {
  AutoPrintService._();

  static final AutoPrintService instance = AutoPrintService._();

  Timer? _retryTimer;
  bool _isProcessing = false;
  String? _brandId;

  void start(String? brandId) {
    if (brandId != null && brandId.isNotEmpty) {
      _brandId = brandId;
    }

    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);

    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => processPendingQueue(),
    );
    unawaited(processPendingQueue());
  }

  void stop() {
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(processPendingQueue());
    }
  }

  Future<void> handleRemoteMessage(RemoteMessage message) {
    return handleMessageData(message.data);
  }

  Future<void> handleMessageData(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    if (type != 'NEW_ORDER') return;

    final prefs = await SharedPreferences.getInstance();
    final brandId = await _resolveBrandId(prefs, data);
    if (brandId == null || brandId.isEmpty) return;

    final enabled = prefs.getBool('auto_print_new_order_$brandId') ?? false;
    if (!enabled) return;

    final receiptData = _receiptDataFromMessage(data);
    if (receiptData == null) return;

    final orderId = _orderId(receiptData);
    if (orderId == null || await _isPrinted(prefs, brandId, orderId)) return;

    final entry = _PrintQueueEntry(
      id: orderId,
      brandId: brandId,
      receiptData: receiptData,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _upsertQueueEntry(prefs, entry);
    await processPendingQueue();
  }

  Future<void> processPendingQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final brandIds = await _knownBrandIds(prefs);

      for (final brandId in brandIds) {
        final enabled = prefs.getBool('auto_print_new_order_$brandId') ?? false;
        if (!enabled) continue;

        final queue = _loadQueue(prefs, brandId);
        if (queue.isEmpty) continue;

        final remaining = <_PrintQueueEntry>[];
        for (final entry in queue) {
          if (await _isPrinted(prefs, brandId, entry.id)) continue;

          final success = await PrinterService.printReceipt(
            entry.receiptData,
            brandId,
          ).timeout(const Duration(seconds: 18), onTimeout: () => false);

          if (success) {
            await _markPrinted(prefs, brandId, entry.id);
          } else {
            remaining.add(entry.copyWith(attempts: entry.attempts + 1));
          }
        }

        await _saveQueue(prefs, brandId, remaining);
      }
    } catch (e) {
      debugPrint('[AutoPrint] queue processing failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<String?> _resolveBrandId(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    final explicit = _text(data['brandId'] ?? data['brand_id']);
    if (explicit.isNotEmpty) {
      _brandId = explicit;
      return explicit;
    }

    final cached = prefs.getString('startup_brand_id') ?? '';
    if (cached.isNotEmpty) {
      _brandId = cached;
      return cached;
    }

    final secure = await StorageService.getBrandId();
    if (secure.isNotEmpty) {
      _brandId = secure;
      return secure;
    }

    return _brandId;
  }

  Future<Set<String>> _knownBrandIds(SharedPreferences prefs) async {
    final ids = <String>{};
    final current = _brandId;
    if (current != null && current.isNotEmpty) ids.add(current);

    final cached = prefs.getString('startup_brand_id') ?? '';
    if (cached.isNotEmpty) ids.add(cached);

    final secure = await StorageService.getBrandId();
    if (secure.isNotEmpty) ids.add(secure);

    for (final key in prefs.getKeys()) {
      const prefix = 'auto_print_queue_';
      if (key.startsWith(prefix)) ids.add(key.substring(prefix.length));
    }

    return ids;
  }

  Map<String, dynamic>? _receiptDataFromMessage(Map<String, dynamic> data) {
    final orderData = _orderData(data);
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
      'brand_name': orderData['brand_name'] ?? orderData['brandName'],
      'table_label':
          orderData['table_label'] ??
          orderData['tableLabel'] ??
          orderData['tableName'] ??
          data['table_label'] ??
          'Walk-in',
      'order_id':
          orderData['order_id'] ??
          orderData['orderId'] ??
          data['order_id'] ??
          data['orderId'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'items': items,
      'total_amount': orderData['total_amount'] ?? orderData['totalPrice'] ?? 0,
      'is_kitchen_ticket': true,
    };
  }

  Map<String, dynamic>? _orderData(Map<String, dynamic> data) {
    final raw = data['orderData'] ?? data['order_data'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  String? _orderId(Map<String, dynamic> receiptData) {
    final value = _text(receiptData['order_id'] ?? receiptData['orderId']);
    return value.isEmpty ? null : value;
  }

  Future<bool> _isPrinted(
    SharedPreferences prefs,
    String brandId,
    String orderId,
  ) async {
    return (prefs.getStringList(_printedKey(brandId)) ?? const <String>[])
        .contains(orderId);
  }

  Future<void> _markPrinted(
    SharedPreferences prefs,
    String brandId,
    String orderId,
  ) async {
    final printedIds = prefs.getStringList(_printedKey(brandId)) ?? <String>[];
    await prefs.setStringList(
      _printedKey(brandId),
      [orderId, ...printedIds.where((id) => id != orderId)].take(160).toList(),
    );
  }

  Future<void> _upsertQueueEntry(
    SharedPreferences prefs,
    _PrintQueueEntry entry,
  ) async {
    final queue = _loadQueue(prefs, entry.brandId);
    final updated = <_PrintQueueEntry>[
      entry,
      ...queue.where((item) => item.id != entry.id),
    ].take(80).toList();
    await _saveQueue(prefs, entry.brandId, updated);
  }

  List<_PrintQueueEntry> _loadQueue(SharedPreferences prefs, String brandId) {
    final encoded = prefs.getStringList(_queueKey(brandId)) ?? const <String>[];
    return encoded
        .map((item) {
          try {
            final decoded = jsonDecode(item);
            if (decoded is Map) {
              return _PrintQueueEntry.fromJson(
                Map<String, dynamic>.from(decoded),
              );
            }
          } catch (_) {}
          return null;
        })
        .whereType<_PrintQueueEntry>()
        .toList();
  }

  Future<void> _saveQueue(
    SharedPreferences prefs,
    String brandId,
    List<_PrintQueueEntry> queue,
  ) {
    return prefs.setStringList(
      _queueKey(brandId),
      queue.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  String _queueKey(String brandId) => 'auto_print_queue_$brandId';
  String _printedKey(String brandId) => 'auto_printed_orders_$brandId';

  String _text(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.toLowerCase() == 'null') return '';
    return text;
  }
}

class _PrintQueueEntry {
  const _PrintQueueEntry({
    required this.id,
    required this.brandId,
    required this.receiptData,
    required this.createdAt,
    this.attempts = 0,
  });

  factory _PrintQueueEntry.fromJson(Map<String, dynamic> json) {
    return _PrintQueueEntry(
      id: json['id'].toString(),
      brandId: json['brandId'].toString(),
      receiptData: Map<String, dynamic>.from(json['receiptData'] as Map),
      createdAt: json['createdAt']?.toString() ?? '',
      attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
    );
  }

  final String id;
  final String brandId;
  final Map<String, dynamic> receiptData;
  final String createdAt;
  final int attempts;

  _PrintQueueEntry copyWith({int? attempts}) {
    return _PrintQueueEntry(
      id: id,
      brandId: brandId,
      receiptData: receiptData,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'brandId': brandId,
      'receiptData': receiptData,
      'createdAt': createdAt,
      'attempts': attempts,
    };
  }
}
