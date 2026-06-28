part of 'pos_screen.dart';

extension PosUiExtension on _PosScreenState {

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
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppColors.slate500,
                            size: 16,
                          ),
                        ),
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
                    showProductNames: _showProductNames,
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
