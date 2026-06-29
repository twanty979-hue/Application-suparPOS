part of 'pos_screen.dart';

extension PosApiExtension on _PosScreenState {

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
          }).map((order) {
            if (order['order_items'] != null) {
              for (var item in order['order_items']) {
                if (item is Map) {
                  final productId = item['product_id']?.toString();
                  if (productId != null) {
                    final product = _products.firstWhere(
                      (p) => p['id']?.toString() == productId,
                      orElse: () => <String, dynamic>{},
                    );
                    if (product.isNotEmpty) {
                      item['image_url'] ??= product['image_url'] ?? product['image_name'];
                      item['local_image_path'] ??= product['local_image_path'];
                    }
                  }
                }
              }
            }
            return order;
          }).toList();

          if (_selectedOrder != null) {
            final currentId = _selectedOrder!['id'];
            final updatedOrder = _unpaidOrders.cast<Map<String, dynamic>?>().firstWhere(
              (o) => o!['id'] == currentId,
              orElse: () => null,
            );
            if (updatedOrder != null) {
              // Check if order items changed
              final oldItems = _selectedOrder!['order_items'] as List? ?? [];
              final newItems = updatedOrder['order_items'] as List? ?? [];
              bool itemsChanged = oldItems.length != newItems.length;
              _selectedOrder = Map<String, dynamic>.from(updatedOrder);
              if (itemsChanged) {
                _triggerCartBounce();
              }
            } else {
              _selectedOrder = null;
            }
          }

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

}
