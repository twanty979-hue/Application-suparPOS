import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; 
import '../api_service.dart';
import '../theme/app_colors.dart'; 

// Import Modals
import '../widgets/modals/status_modal.dart';
import '../widgets/modals/cash_modal.dart';   
import '../widgets/modals/variant_modal.dart'; 

// Import Widgets
import '../widgets/pos/cart_panel.dart';
import '../widgets/pos/product_grid.dart';
import '../widgets/pos/table_list.dart';
import '../widgets/pos/pos_top_bar.dart'; 
import '../widgets/pos/mobile_bottom_cart.dart';

class PosScreen extends StatefulWidget {
  final String brandId;

  const PosScreen({super.key, required this.brandId});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with SingleTickerProviderStateMixin {
  String _activeTab = 'tables'; 
  String _selectedCategory = 'ALL';
  String _paymentMethod = 'cash';
  bool _isLoadingAPI = true;
  bool _autoKitchen = false;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _discounts = [];
  List<Map<String, dynamic>> _cart = [];
  List<Map<String, dynamic>> _unpaidOrders = []; 

  Map<String, dynamic>? _selectedOrder; 
  final TextEditingController _barcodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPosData();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _fetchPosData() async {
    try {
      final url = "${ApiService.initPos}?brand_id=${widget.brandId}";
      final response = await http.get(Uri.parse(url), headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data['categories'] ?? []);
          if (_categories.isEmpty || _categories.first['id'] != 'ALL') {
            _categories.insert(0, {'id': 'ALL', 'name': 'ทั้งหมด'});
          }
          _products = List<Map<String, dynamic>>.from(data['products'] ?? []);
          _tables = List<Map<String, dynamic>>.from(data['tables'] ?? []);
          _discounts = List<Map<String, dynamic>>.from(data['discounts'] ?? []);
          
          _unpaidOrders = [
            {'id': '1', 'table_label': 'A1', 'total_price': 450.0, 'order_items': [{'name': 'ข้าวผัด', 'price': 50, 'qty': 1}]},
            {'id': '2', 'table_label': 'B2', 'total_price': 1200.0, 'order_items': [{'name': 'สเต็ก', 'price': 300, 'qty': 4}]}
          ];

          _isLoadingAPI = false;
        });
      } else {
        throw "Server ตอบกลับ: ${response.statusCode}";
      }
    } catch (e) {
      setState(() => _isLoadingAPI = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("เชื่อมต่อข้อมูลล้มเหลว: $e"), backgroundColor: AppColors.rose500));
      }
    }
  }

  Map<String, dynamic> _calculatePrice(Map<String, dynamic> product, String variant) {
    double basePrice = double.tryParse(product['price']?.toString() ?? '0') ?? 0.0;
    if (variant == 'special' && product['price_special'] != null) basePrice = double.parse(product['price_special'].toString());
    if (variant == 'jumbo' && product['price_jumbo'] != null) basePrice = double.parse(product['price_jumbo'].toString());

    double originalPrice = basePrice;
    if (product['originalPrice'] != null) {
       originalPrice = double.tryParse(product['originalPrice']?.toString() ?? basePrice.toString()) ?? basePrice;
    }

    return {
      'original': originalPrice,
      'final': basePrice,
      'discount': originalPrice > basePrice ? originalPrice - basePrice : 0,
    };
  }

  Future<void> _handleProductClick(Map<String, dynamic> product) async {
    if (product['price_special'] != null || product['price_jumbo'] != null) {
      final selectedVariant = await VariantModal.show(context, product, _calculatePrice);
      if (selectedVariant != null) _addToCart(product, selectedVariant);
    } else {
      _addToCart(product, 'normal');
    }
  }

  void _addToCart(Map<String, dynamic> product, String variant) {
    final pricing = _calculatePrice(product, variant);
    setState(() {
      var existingIndex = _cart.indexWhere((item) => item['id'] == product['id'] && item['variant'] == variant);
      if (existingIndex > -1) {
        _cart[existingIndex]['qty'] += 1;
      } else {
        _cart.add({
          'id': product['id'],
          'name': product['name'],
          'barcode': product['barcode'],
          'variant': variant,
          'price': pricing['final'],
          'original_price': pricing['original'],
          'qty': 1,
        });
      }
    });
  }

  void _removeFromCart(int index) => setState(() => _cart.removeAt(index));

  double get _rawTotal {
    if (_activeTab == 'tables' && _selectedOrder != null) return _selectedOrder!['total_price'];
    return _cart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));
  }

  double get _payableAmount => _paymentMethod == 'cash' ? ((_rawTotal * 4).ceil() / 4) : _rawTotal;

  int get _totalItems {
     if (_activeTab == 'tables' && _selectedOrder != null) return (_selectedOrder!['order_items'] as List).length;
     return _cart.fold(0, (sum, item) => sum + (item['qty'] as int));
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(locale: 'th_TH', symbol: '฿', decimalDigits: 2).format(amount);
  }

  void _processPayment() {
    setState(() {
      if (_activeTab == 'pos') {
        _cart.clear();
      } else {
        _selectedOrder = null;
      }
    });
    StatusModal.show(context, "ชำระเงินสำเร็จ", "บันทึกรายการเรียบร้อยแล้ว", Icons.check_circle, AppColors.emerald500);
  }

  Future<void> _onMainPaymentClick() async {
    if (_payableAmount <= 0) return;
    if (_paymentMethod == 'promptpay') {
        StatusModal.show(context, "QR Code", "แสดง QR พร้อมเพย์ตรงนี้", Icons.qr_code_2, AppColors.blue600);
    } else {
        final success = await CashModal.show(context, _payableAmount);
        if (success == true) _processPayment();
    }
  }

  // 🔥 ฟังก์ชันสำหรับเปิด Bottom Sheet ตะกร้าสินค้าบนมือถือ
  void _showMobileCartModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.slate200, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: CartPanel(
                  activeTab: _activeTab,
                  selectedOrder: _selectedOrder,
                  cart: _cart,
                  paymentMethod: _paymentMethod,
                  rawTotal: _rawTotal,
                  payableAmount: _payableAmount,
                  formatCurrency: _formatCurrency,
                  onRemoveFromCart: _removeFromCart,
                  onPaymentMethodChanged: (method) => setState(() => _paymentMethod = method),
                  onMainPaymentClick: () {
                    Navigator.pop(context); // ปิดตะกร้า
                    _onMainPaymentClick(); // เปิด Modal จ่ายเงิน
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // เช็กขนาดจอ
    bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: _isLoadingAPI
            ? const Center(child: CircularProgressIndicator(color: AppColors.slate800))
            : Center( // 🔥 ครอบ Center เพื่อล็อกตำแหน่งเนื้อหา
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400), // 🔥 ล็อกความกว้างสูงสุด
                  child: Padding(
                    padding: const EdgeInsets.all(16.0), 
                    child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
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
          child: CartPanel(
            activeTab: _activeTab,
            selectedOrder: _selectedOrder,
            cart: _cart,
            paymentMethod: _paymentMethod,
            rawTotal: _rawTotal,
            payableAmount: _payableAmount,
            formatCurrency: _formatCurrency,
            onRemoveFromCart: _removeFromCart,
            onPaymentMethodChanged: (method) => setState(() => _paymentMethod = method),
            onMainPaymentClick: _onMainPaymentClick,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(child: _buildLeftSection()),
        MobileBottomCart(
          totalItems: _totalItems,
          payableAmount: _payableAmount,
          formatCurrency: _formatCurrency,
          onTap: _showMobileCartModal, // 🔥 เชื่อมฟังก์ชันเปิด Modal ตะกร้า
        ),
      ],
    );
  }

  Widget _buildLeftSection() {
    final displayProducts = _selectedCategory == 'ALL'
        ? _products
        : _products.where((p) => p['category_id'] == _selectedCategory).toList();

    return Column(
      children: [
        PosTopBar(
          activeTab: _activeTab,
          unpaidCount: _unpaidOrders.length,
          autoKitchen: _autoKitchen,
          onTabChanged: (tab) => setState(() => _activeTab = tab),
          onKitchenToggled: () => setState(() => _autoKitchen = !_autoKitchen),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.slate100),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
            ),
            clipBehavior: Clip.antiAlias,
            child: _activeTab == 'tables' 
              ? TableList(
                  unpaidOrders: _unpaidOrders,
                  selectedOrder: _selectedOrder,
                  onSelectOrder: (order) => setState(() => _selectedOrder = order),
                  formatCurrency: _formatCurrency,
                ) 
              : ProductGrid(
                  categories: _categories,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: (id) => setState(() => _selectedCategory = id),
                  displayProducts: displayProducts,
                  barcodeController: _barcodeController,
                  onProductClick: _handleProductClick,
                  calculatePrice: _calculatePrice,
                  formatCurrency: _formatCurrency,
                ),
          ),
        ),
      ],
    );
  }
}