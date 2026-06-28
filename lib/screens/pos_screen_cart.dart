part of 'pos_screen.dart';

extension PosCartExtension on _PosScreenState {

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
    if (_activeTab == 'tables') {
      if (_selectedOrder != null) return _orderTotal(_selectedOrder!);
      return 0.0; // ยังไม่เลือกโต๊ะ → ไม่นำตะกร้า POS มาแสดง
    }
    return _cart.fold(
      0.0,
      (sum, item) => sum + ((item['price'] as num) * (item['qty'] as num)),
    );
  }

  double get _payableAmount =>
      _paymentMethod == 'cash' ? ((_rawTotal * 4).ceil() / 4) : _rawTotal;

  int get _totalItems {
    if (_activeTab == 'tables') {
      if (_selectedOrder == null) return 0; // ยังไม่เลือกโต๊ะ → ไม่นำตะกร้า POS มาแสดง
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

}
