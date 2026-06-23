import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// ลบ SharedPreferences ออกไปเลยครับ เราไม่ใช้แล้ว
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 ใช้ตู้เซฟดิจิทัล
import '../widgets/iphone_mockup.dart';

class ThemeDetailScreen extends StatefulWidget {
  final dynamic theme;
  final String imageUrl;

  const ThemeDetailScreen({
    super.key,
    required this.theme,
    required this.imageUrl,
  });

  @override
  State<ThemeDetailScreen> createState() => _ThemeDetailScreenState();
}

class _ThemeDetailScreenState extends State<ThemeDetailScreen> {
  String _selectedPlan = 'monthly';
  bool _isLoading = false;
  bool _isLoadingCoins = true;
  late List<Map<String, dynamic>> _availablePlans;
  int _currentCoins = 0;
  bool _ownedAfterPurchase = false;
  int? _daysLeftAfterPurchase;
  String? _purchaseTypeAfterPurchase;
  bool _showMobilePreview = true;

  // ตัวแปรสำหรับระบบเลื่อนรูป
  late PageController _pageController;
  int _currentImageIndex = 0;
  List<String> _displayImages = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1);
    _setupImages();
    _setupAvailablePlans();
    _fetchLatestThemeState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goBack() async {
    final navigator = Navigator.of(context);
    if (await navigator.maybePop()) {
      return;
    }

    if (!mounted) return;
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
  }

  void _setupImages() {
    _displayImages = [];
    if (widget.imageUrl.isNotEmpty) {
      _displayImages.add(widget.imageUrl);
    }

    final gallery = widget.theme['gallery_urls'] ?? widget.theme['gallery'];
    if (gallery != null && gallery['mobile'] != null) {
      for (var img in gallery['mobile']) {
        final imgStr = img.toString();
        if (!_displayImages.contains(imgStr)) {
          _displayImages.add(imgStr);
        }
      }
    }
  }

  Future<void> _fetchLatestThemeState() async {
    try {
      // 🌟 แก้ไขจุดที่ 1: ดึง Token จากตู้เซฟดิจิทัล
      final String? userToken = await StorageService.getToken();
      final themeId = widget.theme['id']?.toString() ?? '';

      if (userToken == null) {
        setState(() => _isLoadingCoins = false);
        return;
      }

      final url = themeId.isEmpty
          ? Uri.parse(ApiService.marketplace)
          : Uri.parse(
              ApiService.marketplace,
            ).replace(queryParameters: {'id': themeId});
            
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $userToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _currentCoins = _toInt(data['user_coins'] ?? data['coins'] ?? 0);
              if (data['theme'] is Map) {
                _mergeExactMarketplaceTheme(
                  Map<String, dynamic>.from(data['theme'] as Map),
                );
              }
              _isLoadingCoins = false;
            });
          }
        }
      } else {
        if (mounted) setState(() => _isLoadingCoins = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCoins = false);
    }
  }

  void _mergeExactMarketplaceTheme(Map<String, dynamic> latestTheme) {
    final themeMap = widget.theme;
    if (themeMap is! Map) return;

    final ownership = latestTheme['ownership'];
    final isOwned = _toBool(latestTheme['is_owned']);

    themeMap['is_owned'] = isOwned;

    if (ownership is Map) {
      final ownershipMap = Map<String, dynamic>.from(ownership);
      themeMap['ownership'] = ownershipMap;
      themeMap['purchase_type'] = ownershipMap['type'];
      themeMap['expires_at'] = ownershipMap['expires_at'];
      themeMap['days_left'] = ownershipMap['days_left'];

      if (isOwned) {
        _purchaseTypeAfterPurchase = ownershipMap['type']?.toString();
        _daysLeftAfterPurchase = _extractDaysLeft(ownershipMap);
      } else {
        _purchaseTypeAfterPurchase = null;
        _daysLeftAfterPurchase = null;
      }
    }

    _ownedAfterPurchase = false;
  }

  void _setupAvailablePlans() {
    _availablePlans = [];
    if (widget.theme['price_weekly'] != null) {
      _availablePlans.add({
        'id': 'weekly',
        'label': 'รายสัปดาห์',
        'price': _toInt(widget.theme['price_weekly']),
        'desc': 'เรียกเก็บเงินทุกๆ 7 วัน',
      });
    }
    if (widget.theme['price_monthly'] != null) {
      _availablePlans.add({
        'id': 'monthly',
        'label': 'รายเดือน',
        'price': _toInt(widget.theme['price_monthly']),
        'desc': 'เรียกเก็บเงินทุกๆ 30 วัน',
      });
    }
    if (widget.theme['price_yearly'] != null) {
      _availablePlans.add({
        'id': 'yearly',
        'label': 'รายปี',
        'price': _toInt(widget.theme['price_yearly']),
        'desc': 'เรียกเก็บเงินทุกๆ 365 วัน',
      });
    }
    if (_availablePlans.isNotEmpty) {
      _selectedPlan = _availablePlans.firstWhere(
        (plan) => plan['id'] == 'monthly',
        orElse: () => _availablePlans.first,
      )['id'];
    }
  }

  int get _currentPrice {
    final plan = _availablePlans.firstWhere(
      (p) => p['id'] == _selectedPlan,
      orElse: () => {'price': 0},
    );
    return _toInt(plan['price']);
  }

  String get _currentPlanDesc {
    final plan = _availablePlans.firstWhere(
      (p) => p['id'] == _selectedPlan,
      orElse: () => {'desc': ''},
    );
    return plan['desc'] as String;
  }

  String get _selectedPlanLabel {
    final plan = _availablePlans.firstWhere(
      (p) => p['id'] == _selectedPlan,
      orElse: () => {'label': ''},
    );
    return plan['label'] as String;
  }

  Map<String, dynamic>? get _ownershipMap {
    final ownership = widget.theme['ownership'];
    if (ownership is Map) {
      return Map<String, dynamic>.from(ownership);
    }
    return null;
  }

  bool get _isExpired =>
      _toBool(widget.theme['is_expired']) ||
      _toBool(_ownershipMap?['is_expired']);

  bool get _isOwned =>
      _ownedAfterPurchase || (_toBool(widget.theme['is_owned']) && !_isExpired);

  bool get _isLifetimeOwned {
    final rawType =
        _purchaseTypeAfterPurchase ??
        widget.theme['purchase_type'] ??
        _ownershipMap?['type'];
    final purchaseType = rawType?.toString().toLowerCase() ?? '';
    return purchaseType == 'lifetime' || purchaseType == 'ถาวร';
  }

  int? get _daysLeft =>
      _daysLeftAfterPurchase ??
      _extractDaysLeft(_ownershipMap) ??
      _extractDaysLeft(widget.theme);

  String get _ownershipDurationText {
    if (_isLifetimeOwned) return 'ใช้ได้ถาวร';

    final days = _daysLeft;
    if (days == null) return 'กำลังตรวจสอบวันคงเหลือ';
    if (days <= 0) return 'หมดอายุวันนี้';
    return 'เหลืออีก $days วัน';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase().trim();
    return text == 'true' || text == '1' || text == 'yes';
  }

  int? _extractDaysLeft(dynamic source) {
    if (source is! Map) return null;

    const dayKeys = [
      'days_left',
      'remaining_days',
      'days_remaining',
      'duration_days',
    ];

    for (final key in dayKeys) {
      final value = source[key];
      if (value == null) continue;
      final parsed = _toInt(value);
      return math.max(0, parsed);
    }

    const expiryKeys = [
      'expires_at',
      'expiry_date',
      'expire_at',
      'expired_at',
      'expiresAt',
    ];

    for (final key in expiryKeys) {
      final value = source[key];
      if (value == null) continue;
      final expiryDate = DateTime.tryParse(value.toString());
      if (expiryDate == null) continue;

      final diff = expiryDate.difference(DateTime.now());
      if (diff.isNegative) return 0;
      return math.max(1, diff.inDays + (diff.inHours % 24 == 0 ? 0 : 1));
    }

    return null;
  }

  int? _estimatedDaysForPlan(String planId) {
    switch (planId) {
      case 'weekly':
        return 7;
      case 'monthly':
        return 30;
      case 'yearly':
        return 365;
      default:
        return null;
    }
  }

  void _applyPurchaseResult(Map<String, dynamic> data) {
    final purchaseType = (data['purchase_type'] ?? _selectedPlan).toString();
    final isLifetime =
        purchaseType.toLowerCase() == 'lifetime' || _selectedPlan == 'lifetime';
    final daysLeft = isLifetime
        ? null
        : _extractDaysLeft(data) ?? _estimatedDaysForPlan(_selectedPlan);

    setState(() {
      _currentCoins = _toInt(
        data['new_coin_balance'] ??
            data['coin_balance'] ??
            data['user_coins'] ??
            _currentCoins,
      );
      _ownedAfterPurchase = true;
      _purchaseTypeAfterPurchase = isLifetime ? 'lifetime' : purchaseType;
      _daysLeftAfterPurchase = daysLeft;

      final themeMap = widget.theme;
      if (themeMap is Map) {
        themeMap['is_owned'] = true;
        themeMap['purchase_type'] = _purchaseTypeAfterPurchase;
        if (daysLeft != null) {
          themeMap['days_left'] = daysLeft;
        }
      }
    });
  }

  Future<bool> _purchaseTheme() async {
    setState(() => _isLoading = true);

    try {
      // 🌟 แก้ไขจุดที่ 2: ดึง Token จากตู้เซฟดิจิทัล ตอนกดจ่ายเงิน
      final String? userToken = await StorageService.getToken();

      if (userToken == null || userToken.isEmpty) {
        throw Exception('ไม่พบข้อมูลการล็อกอิน กรุณาล็อกอินใหม่');
      }

      final url = Uri.parse(ApiService.purchaseTheme);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $userToken',
        },
        body: jsonEncode({
          'theme_id': widget.theme['id'],
          'plan': _selectedPlan,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (!mounted) return false;
        _applyPurchaseResult(Map<String, dynamic>.from(data));

        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 120));
        if (!mounted) return false;
        await _showPurchaseSuccessDialog();
        return true;
      } else {
        throw Exception(data['error'] ?? 'เกิดข้อผิดพลาดในการสั่งซื้อ');
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ล้มเหลว: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = (widget.theme['name'] ?? 'Unknown Theme').toString();
    final categoryMap = widget.theme['marketplace_categories'];
    final String category = categoryMap is Map
        ? (categoryMap['name'] ?? 'ทั่วไป').toString()
        : 'ทั่วไป';
    final String mode =
        (widget.theme['theme_mode'] ??
                widget.theme['slug'] ??
                widget.theme['min_plan'] ??
                '')
            .toString()
            .toUpperCase();
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 430;
    final horizontalPadding = isCompact ? 18.0 : 24.0;
    final previewHeight = (screenWidth * (isCompact ? 1.34 : 1.04))
        .clamp(360.0, 500.0)
        .toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 128,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _goBack,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Color(0xFF334155),
                  ),
                  SizedBox(width: 7),
                  Text(
                    'ย้อนกลับ',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        title: _buildCoinBalancePill(),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0B1730),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share_outlined, color: Color(0xFF94A3B8)),
            tooltip: 'แชร์',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: _buildDeviceToggle(),
                  ),
                  const SizedBox(height: 22),
                  _buildPreviewCarousel(previewHeight),
                  if (_displayImages.length > 1) ...[
                    const SizedBox(height: 16),
                    _buildPageDots(),
                  ],
                  SizedBox(height: isCompact ? 26 : 34),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildThemeHeader(category, mode, name, isCompact),
                        const SizedBox(height: 24),
                        if (_isOwned) ...[
                          _buildOwnedStatusCard(),
                          const SizedBox(height: 30),
                        ],
                        if (!_isOwned && _availablePlans.isNotEmpty) ...[
                          _buildPlanTabs(),
                          const SizedBox(height: 20),
                          _buildPriceCard(),
                          const SizedBox(height: 34),
                        ] else if (!_isOwned) ...[
                          _buildUnavailableCard(),
                          const SizedBox(height: 30),
                        ],
                        _buildFeatureListCard(),
                        const SizedBox(height: 34),
                        _buildPrimaryAction(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoinBalancePill() {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset('lib/assets/cion.png', width: 20),
          const SizedBox(width: 4),
          _isLoadingCoins
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                )
              : Text(
                  '$_currentCoins',
                  style: TextStyle(
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildDeviceToggle() {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDDE5EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                left: _showMobilePreview ? 0 : segmentWidth,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1730),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B1730).withValues(alpha: 0.16),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDeviceToggleItem(
                      label: 'มือถือ',
                      icon: Icons.phone_android_rounded,
                      selected: _showMobilePreview,
                      onTap: () => setState(() => _showMobilePreview = true),
                    ),
                    _buildDeviceToggleItem(
                      label: 'แท็บเล็ต',
                      icon: Icons.tablet_mac_rounded,
                      selected: !_showMobilePreview,
                      onTap: () => setState(() => _showMobilePreview = false),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeviceToggleItem({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCarousel(double height) {
    if (_displayImages.isEmpty) {
      return Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 42,
            color: Color(0xFF94A3B8),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _pageController,
        clipBehavior: Clip.hardEdge,
        onPageChanged: (index) => setState(() => _currentImageIndex = index),
        itemCount: _displayImages.length,
        itemBuilder: (context, index) {
          final isCurrent = _currentImageIndex == index;
          return AnimatedScale(
            scale: isCurrent ? 1 : 0.94,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 6,
                ),
                child: AspectRatio(
                  aspectRatio: _showMobilePreview ? 0.48 : 0.66,
                  child: IphoneMockup(
                    imageUrl: _displayImages[index],
                    isCurrent: false,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThemeHeader(
    String category,
    String mode,
    String name,
    bool isCompact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildCategoryPill(category),
            if (mode.isNotEmpty)
              Text(
                'โหมด $mode',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isCompact ? 27 : 30,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0B1730),
            height: 1.04,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Shop Theme: $category',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _displayImages.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentImageIndex == index ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: _currentImageIndex == index
                ? const Color(0xFF0B1730)
                : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPill(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildOwnedStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'แพ็กเกจปัจจุบันของคุณ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _isLifetimeOwned
                      ? 'แพ็กเกจนี้ใช้งานได้ถาวร'
                      : 'แพ็กเกจจะหมดอายุในอีก ${_daysLeft ?? '-'} วัน',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTabs() {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeIndex = math.max(
            0,
            _availablePlans.indexWhere((plan) => plan['id'] == _selectedPlan),
          );
          final segmentWidth =
              constraints.maxWidth / math.max(1, _availablePlans.length);

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 390),
                curve: Curves.easeOutBack,
                left: segmentWidth * activeIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD4DCE6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _availablePlans.map((plan) {
                    final planId = plan['id'].toString();
                    final isSelected = _selectedPlan == planId;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPlan = planId),
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF0B1730)
                                    : const Color(0xFF64748B),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                              child: Text(
                                plan['label'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (planId == 'yearly' && !isSelected)
                              const Positioned(
                                right: 14,
                                top: 13,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(width: 6, height: 6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPriceCard() {
    final badge = _selectedPlan == 'yearly'
        ? ('คุ้มค่าที่สุด', const Color(0xFFECFDF5), const Color(0xFF047857))
        : _selectedPlan == 'monthly'
        ? ('ยอดนิยม', const Color(0xFFDBEAFE), const Color(0xFF2563EB))
        : ('', Colors.transparent, Colors.transparent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF0B1730), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 26,
            child: badge.$1.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: badge.$2,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _selectedPlan == 'yearly'
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedPlan == 'yearly'
                              ? Icons.star_rounded
                              : Icons.local_fire_department_rounded,
                          size: 13,
                          color: _selectedPlan == 'yearly'
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF97316),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badge.$1,
                          style: TextStyle(
                            color: badge.$3,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  '$_currentPrice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B1730),
                    fontSize: 50,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'เหรียญ',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _currentPlanDesc,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 64,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE8F5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 28),
          _buildPriceBenefitRow('ต่ออายุเพิ่มได้ตลอดเวลา'),
          const SizedBox(height: 18),
          _buildPriceBenefitRow('เข้าถึงทุกฟีเจอร์แบบพรีเมียม'),
        ],
      ),
    );
  }

  Widget _buildPriceBenefitRow(String text) {
    return Row(
      children: [
        const SizedBox(width: 18),
        const Icon(Icons.check_rounded, color: Color(0xFF475569), size: 18),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0B1730),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureListCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สิ่งที่คุณจะได้รับ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            icon: Icons.bolt_rounded,
            color: const Color(0xFF059669),
            text: 'ติดตั้งผ่านระบบอัตโนมัติทันที',
          ),
          const SizedBox(height: 13),
          _buildFeatureRow(
            icon: Icons.phone_android_rounded,
            color: const Color(0xFF2563EB),
            text: 'รองรับการแสดงผลทุกขนาดหน้าจอ',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0B1730),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailableCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'ธีมนี้ยังไม่มีแพ็กเกจสำหรับสั่งซื้อ',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction() {
    if (_isOwned) {
      return SizedBox(
        height: 58,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0B1730),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            shadowColor: const Color(0xFF0B1730).withValues(alpha: 0.22),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'ไปที่หน้าจัดการธีม',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    final canCheckout = !_isLoadingCoins && _availablePlans.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0B1730),
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: canCheckout ? 8 : 0,
          shadowColor: const Color(0xFF0B1730).withValues(alpha: 0.24),
        ),
        onPressed: canCheckout ? _showPurchaseModal : null,
        child: _isLoadingCoins
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _availablePlans.isEmpty
                        ? Icons.block_rounded
                        : Icons.shopping_bag_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _availablePlans.isEmpty
                        ? 'ไม่มีแพ็กเกจให้ซื้อ'
                        : 'ดำเนินการชำระเงิน',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Modal ยืนยันชำระเงิน
  void _showPurchaseModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bool hasEnoughCoins = _currentCoins >= _currentPrice;
            final afterPay = math.max(0, _currentCoins - _currentPrice);

            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Center(
                        child: Image.asset('lib/assets/cion.png', width: 38),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'ยืนยันการสั่งซื้อ',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0B1730),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'แพ็กเกจ $_selectedPlanLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _currentPlanDesc,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_currentPrice',
                                    style: const TextStyle(
                                      color: Color(0xFF0B1730),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Image.asset('lib/assets/cion.png', width: 24),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildModalBalanceRow(
                            label: 'ยอดคงเหลือ',
                            value: _isLoadingCoins
                                ? 'กำลังโหลด'
                                : '$_currentCoins เหรียญ',
                            color: const Color(0xFF0B1730),
                          ),
                          const SizedBox(height: 9),
                          _buildModalBalanceRow(
                            label: 'หลังชำระ',
                            value: _isLoadingCoins ? '-' : '$afterPay เหรียญ',
                            color: hasEnoughCoins
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                        ],
                      ),
                    ),
                    if (!_isLoadingCoins && !hasEnoughCoins) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 18,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'เหรียญของคุณไม่เพียงพอสำหรับแพ็กเกจนี้',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasEnoughCoins && !_isLoadingCoins
                              ? const Color(0xFF0B1730)
                              : const Color(0xFFCBD5E1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: hasEnoughCoins && !_isLoadingCoins ? 5 : 0,
                        ),
                        onPressed:
                            (_isLoading || !hasEnoughCoins || _isLoadingCoins)
                            ? null
                            : () async {
                                setModalState(() => _isLoading = true);
                                final purchased = await _purchaseTheme();
                                if (!purchased && mounted) {
                                  setModalState(() {});
                                }
                              },
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : Text(
                                hasEnoughCoins
                                    ? 'ยืนยันชำระเงิน $_currentPrice เหรียญ'
                                    : 'เหรียญของคุณไม่เพียงพอ',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: hasEnoughCoins
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalBalanceRow({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Future<void> _showPurchaseSuccessDialog() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ปิด',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 380),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 128,
                    height: 104,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          top: 4,
                          left: 12,
                          child: _buildSuccessSpark(
                            color: const Color(0xFFFDE68A),
                            size: 18,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: 18,
                          child: _buildSuccessSpark(
                            color: const Color(0xFFBFDBFE),
                            size: 16,
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          right: 22,
                          child: _buildSuccessSpark(
                            color: const Color(0xFFA7F3D0),
                            size: 14,
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.82, end: 1),
                          duration: const Duration(milliseconds: 430),
                          curve: Curves.elasticOut,
                          builder: (context, value, child) {
                            return Transform.scale(scale: value, child: child);
                          },
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF22C55E), Color(0xFF2563EB)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ซื้อสำเร็จแล้ว',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF0B1730),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ธีมพร้อมใช้งานในบัญชีของคุณ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_bottom_rounded,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _ownershipDurationText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF047857),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B1730),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'เรียบร้อย',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  Widget _buildSuccessSpark({required Color color, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}