part of 'pos_screen.dart';

extension PosPaymentExtension on _PosScreenState {
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
      final cashierId =
          await StorageService.getUserId() ?? _currentUserUuidOrNull();
      final selectedOrder = _selectedOrder;

      double changeAmount = _paymentMethod == 'promptpay'
          ? 0.0
          : (receivedAmount - _payableAmount);
      if (changeAmount < 0) changeAmount = 0.0;
      print("💵 [CHECKOUT] 2. คำนวณเงินทอน: $changeAmount");

      final sourceOrderIds = selectedOrder != null
          ? _sourceOrderIdsFor(selectedOrder)
          : <String>[];
      final selectedTableId = selectedOrder != null
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

      String finalOrderId = selectedOrder == null
          ? await _ensureWalkInDraftOrder()
          : (sourceOrderIds.isNotEmpty
                ? sourceOrderIds.first
                : (selectedOrderId ?? tableOrderFallbackId));

      String tableLabel = selectedOrder != null
          ? (selectedTableLabel ?? '?')
          : 'Walk-in';
      String orderType = selectedOrder != null ? 'table' : 'pos';

      final usedTableTokens = selectedOrder != null
          ? _usedTableTokensForOrder(selectedOrder)
          : <String>[];
      final nextTableTokens = selectedOrder != null
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

      if (selectedOrder == null) {
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
          final isCancelled = i['status']?.toString().toLowerCase() == 'cancelled';
          return <String, dynamic>{
            'id': i['id'] ?? const Uuid().v4(),
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
            'status': i['status'] ?? 'active',
            'cancelled_by': isCancelled ? (i['cancelled_by'] ?? _currentUserUuidOrNull()) : null,
            'cancelled_at': isCancelled ? (i['cancelled_at'] ?? nowIso) : null,
            'cancel_reason': isCancelled ? (i['cancel_reason'] ?? '') : null,
            'created_at': i['created_at'] ?? nowIso,
          };
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
          if (selectedOrder != null) ...{
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
          'cashier_id': cashierId,
          'created_at': nowIso,
        },
        syncPayload: {
          'cartItems': selectedOrder == null ? _cart : selectedOrderItems,
          'cancelledCartItems': selectedOrder == null
              ? _cancelledCartItems
              : const <Map<String, dynamic>>[],
          'brandId': widget.brandId,
          'type': selectedOrder != null ? 'tables' : 'pos',
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
              if (selectedOrder == null) {
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

      if (selectedOrder != null && widget.brandId.isNotEmpty) {
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
                  // 'payment_id': localPayId, // เอาออกชั่วคราวเพื่อป้องกัน Error Foreign Key บน Server เพราะ Payment เพิ่งสร้างใน Local ยังไม่ Sync
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
      final promptPayItems = _selectedOrder == null
          ? List<dynamic>.from(_cart)
          : List<dynamic>.from(
              (_selectedOrder?['order_items'] as List?) ?? const [],
            );
      final promptPayTableLabel = _selectedOrder != null
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

  Future<void> _onCancelOrderClick({bool skipConfirm = false}) async {
    final bool isWalkIn = (_selectedOrder == null);

    if (isWalkIn && _cart.isEmpty) return;
    if (!isWalkIn && _selectedOrder == null) return;

    if (!skipConfirm) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
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
    }

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
}
