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
part 'pos_screen_fcm.dart';
part 'pos_screen_api.dart';
part 'pos_screen_cart.dart';
part 'pos_screen_payment.dart';
part 'pos_screen_printer.dart';
part 'pos_screen_ui.dart';

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
}
