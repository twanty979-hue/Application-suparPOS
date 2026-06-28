import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../widgets/iphone_mockup.dart';
import 'theme_detail_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const Color _ink = Color(0xFF0B1730);
  static const Color _pageBg = const Color(0xFFEDE9E3);
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _muted = Color(0xFF94A3B8);

  bool isLoading = true;
  int userCoins = 0;
  List<dynamic> categories = [];
  List<dynamic> allThemes = [];
  List<dynamic> displayedThemes = [];
  String selectedCategoryId = 'ALL';
  String selectedTier = 'ALL';

  int currentPage = 1;
  final int itemsPerPage = 12;

  final String _cdnBaseUrl = 'https://img.pos-foodscan.com';

  @override
  void initState() {
    super.initState();
    fetchMarketplaceData();
  }

  Future<void> fetchMarketplaceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = await StorageService.getToken();

      final response = await http.get(
        Uri.parse(ApiService.marketplace),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            userCoins = _toInt(data['user_coins']);
            categories = data['categories'] ?? [];
            allThemes = data['themes'] ?? [];
            _applyFilters(resetPage: true);
            isLoading = false;
          });
          return;
        }
      }
    } catch (_) {
      // Keep the screen quiet and show an empty state below.
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  void _applyFilters({bool resetPage = false}) {
    Iterable<dynamic> nextThemes = allThemes;

    if (selectedCategoryId != 'ALL') {
      nextThemes = nextThemes.where(
        (theme) => theme['category_id']?.toString() == selectedCategoryId,
      );
    }

    if (selectedTier != 'ALL') {
      nextThemes = nextThemes.where(
        (theme) => _themeTier(theme) == selectedTier.toLowerCase(),
      );
    }

    displayedThemes = nextThemes.toList();
    if (resetPage) currentPage = 1;
  }

  void _setCategory(String categoryId) {
    setState(() {
      selectedCategoryId = categoryId;
      _applyFilters(resetPage: true);
    });
  }

  void _setTier(String tier) {
    setState(() {
      selectedTier = tier;
      _applyFilters(resetPage: true);
    });
  }

  String _getImageUrl(String? fileName) {
    if (fileName == null || fileName.isEmpty) {
      return 'https://via.placeholder.com/300x600?text=No+Image';
    }
    if (fileName.contains('supabase.co')) {
      final cleanFileName = fileName.split('/').last;
      return '$_cdnBaseUrl/themes/$cleanFileName';
    }
    if (fileName.startsWith('http')) return fileName;
    if (fileName.startsWith('themes/')) return '$_cdnBaseUrl/$fileName';
    return '$_cdnBaseUrl/themes/$fileName';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  String _themeTier(dynamic theme) {
    final raw = (theme['min_plan'] ?? theme['tier'] ?? 'free')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'basic' || raw == 'pro' || raw == 'ultimate') return raw;
    return 'free';
  }

  bool _isThemeOwned(dynamic theme) {
    final ownership = theme['ownership'];
    final isExpired =
        _toBool(theme['is_expired']) ||
        (ownership is Map && _toBool(ownership['is_expired']));
    return _toBool(theme['is_owned']) && !isExpired;
  }

  Map<String, int> _tierCounts() {
    final counts = {
      'ALL': allThemes.length,
      'free': 0,
      'basic': 0,
      'pro': 0,
      'ultimate': 0,
    };
    for (final theme in allThemes) {
      final tier = _themeTier(theme);
      counts[tier] = (counts[tier] ?? 0) + 1;
    }
    return counts;
  }

  List<dynamic> _visiblePages(int current, int total) {
    if (total <= 5) return List<int>.generate(total, (index) => index + 1);
    if (current <= 3) return [1, 2, 3, 4, '...', total];
    if (current >= total - 2) {
      return [1, '...', total - 3, total - 2, total - 1, total];
    }
    return [1, '...', current - 1, current, current + 1, '...', total];
  }

  @override
  Widget build(BuildContext context) {
    int totalPages = (displayedThemes.length / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    final startIndex = (currentPage - 1) * itemsPerPage;
    var endIndex = startIndex + itemsPerPage;
    if (endIndex > displayedThemes.length) endIndex = displayedThemes.length;

    final pageThemes = displayedThemes.isNotEmpty
        ? displayedThemes.sublist(startIndex, endIndex)
        : <dynamic>[];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _pageBg,
      drawer: const AppSidebar(activeMenu: 'marketplace'),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Expanded(
                  child: isLoading
                      ? const SuparPosLoading(fullScreen: false)
                      : displayedThemes.isEmpty
                      ? _buildEmptyState()
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: _buildResultSummary(
                                pageThemes.length,
                                totalPages,
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 94),
                              sliver: _buildThemesGrid(pageThemes),
                            ),
                          ],
                        ),
                ),
              ],
            ),
            if (!isLoading && displayedThemes.isNotEmpty)
              _buildPagination(totalPages),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFEDE9E3),
        border: Border(bottom: BorderSide(color: Color(0xFFDCD6CB))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A0B1730),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Material(
              color: _ink,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A0B1730),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MARKETPLACE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      height: 0.95,
                    ),
                  ),
                  SizedBox(height: 7),
                  Row(
                    children: [
                      _LiveDot(),
                      SizedBox(width: 7),
                      Text(
                        'OFFICIAL STORE',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.7,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildCoinPill(),
            const SizedBox(width: 8),
            _buildFilterButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinPill() {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF8D986)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0FF59E0B),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'lib/assets/cion.png',
            width: 19,
            height: 19,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.monetization_on,
              color: Color(0xFFF59E0B),
              size: 18,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            NumberFormat('#,###').format(userCoins),
            style: const TextStyle(
              color: Color(0xFFB45309),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton() {
    final hasFilter = selectedTier != 'ALL' || selectedCategoryId != 'ALL';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: const Color(0xFF0B1730),
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: _showFiltersSheet,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF0B1730)),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        if (hasFilter)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFF43F5E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  void _showFiltersSheet() {
    final counts = _tierCounts();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            void chooseTier(String tier) {
              _setTier(tier);
              sheetSetState(() {});
            }

            void chooseCategory(String categoryId) {
              _setCategory(categoryId);
              sheetSetState(() {});
            }

            return Container(
              margin: const EdgeInsets.all(12),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x330B1730),
                    blurRadius: 34,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'FILTERS',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      _buildSheetLabel('FILTER BY PLAN'),
                      _buildFilterTile(
                        label: 'All Plans',
                        count: counts['ALL'] ?? 0,
                        selected: selectedTier == 'ALL',
                        onTap: () => chooseTier('ALL'),
                      ),
                      _buildFilterTile(
                        label: 'Free',
                        count: counts['free'] ?? 0,
                        selected: selectedTier == 'free',
                        onTap: () => chooseTier('free'),
                      ),
                      _buildFilterTile(
                        label: 'Basic',
                        count: counts['basic'] ?? 0,
                        selected: selectedTier == 'basic',
                        onTap: () => chooseTier('basic'),
                      ),
                      _buildFilterTile(
                        label: 'Pro',
                        count: counts['pro'] ?? 0,
                        selected: selectedTier == 'pro',
                        onTap: () => chooseTier('pro'),
                      ),
                      _buildFilterTile(
                        label: 'Ultimate',
                        count: counts['ultimate'] ?? 0,
                        selected: selectedTier == 'ultimate',
                        onTap: () => chooseTier('ultimate'),
                      ),
                      const Divider(height: 22, color: _line),
                      _buildSheetLabel('CATEGORIES'),
                      _buildFilterTile(
                        label: 'All Items',
                        selected: selectedCategoryId == 'ALL',
                        onTap: () => chooseCategory('ALL'),
                      ),
                      ...categories.map(
                        (cat) => _buildFilterTile(
                          label: (cat['name'] ?? 'Category').toString(),
                          selected: selectedCategoryId == cat['id'].toString(),
                          onTap: () => chooseCategory(cat['id'].toString()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
      child: Text(
        label,
        style: const TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildFilterTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? count,
  }) {
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF2563EB),
                        size: 16,
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFDBEAFE)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF94A3B8),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultSummary(int pageCount, int totalPages) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (selectedTier != 'ALL') _buildSmallPill(selectedTier),
                if (selectedCategoryId != 'ALL')
                  _buildSmallPill(_categoryName(selectedCategoryId)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _categoryName(String id) {
    for (final cat in categories) {
      if (cat['id'].toString() == id) return (cat['name'] ?? id).toString();
    }
    return id;
  }

  Widget _buildSmallPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line, width: 1.5),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_rounded, color: _muted, size: 34),
            SizedBox(height: 12),
            Text(
              'NO ITEMS FOUND',
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'ลองเปลี่ยนตัวกรองดูครับ',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemesGrid(List<dynamic> pageThemes) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columnCount = width >= 900 ? 6 : (width >= 600 ? 4 : 3);

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            childAspectRatio: 0.43,
            crossAxisSpacing: width >= 600 ? 12 : 8,
            mainAxisSpacing: width >= 600 ? 16 : 12,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final theme = pageThemes[index];
            return ThemeCardItem(
              theme: theme,
              imageUrl: _getImageUrl(
                (theme['image_url'] ?? theme['preview_image'] ?? '').toString(),
              ),
              isOwned: _isThemeOwned(theme),
            );
          }, childCount: pageThemes.length),
        );
      },
    );
  }

  Widget _buildPagination(int totalPages) {
    final pages = _visiblePages(currentPage, totalPages);
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF292524),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pageNavButton(
                icon: Icons.arrow_back_rounded,
                enabled: currentPage > 1,
                onTap: () => setState(() => currentPage--),
              ),
              const SizedBox(width: 4),
              ...pages.map(
                (page) => page == '...'
                    ? const SizedBox(
                        width: 24,
                        height: 30,
                        child: Center(
                          child: Text(
                            '...',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                    : _pageNumberButton(page as int),
              ),
              const SizedBox(width: 4),
              _pageNavButton(
                icon: Icons.arrow_forward_rounded,
                enabled: currentPage < totalPages,
                onTap: () => setState(() => currentPage++),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageNumberButton(int page) {
    final selected = currentPage == page;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => currentPage = page),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Text(
                page.toString(),
                style: TextStyle(
                  color: selected ? const Color(0xFF292524) : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 31,
          height: 31,
          child: Icon(
            icon,
            color: enabled ? Colors.white : const Color(0xFF475569),
            size: 17,
          ),
        ),
      ),
    );
  }
}

class ThemeCardItem extends StatefulWidget {
  final dynamic theme;
  final String imageUrl;
  final bool isOwned;

  const ThemeCardItem({
    super.key,
    required this.theme,
    required this.imageUrl,
    required this.isOwned,
  });

  @override
  State<ThemeCardItem> createState() => _ThemeCardItemState();
}

class _ThemeCardItemState extends State<ThemeCardItem> {
  static const Color _ink = Color(0xFF0B1730);
  static const Color _line = Color(0xFFE2E8F0);

  Timer? _timer;
  int _priceIndex = 0;
  final List<Map<String, dynamic>> _priceList = [];

  @override
  void initState() {
    super.initState();
    _setupPrices();
    if (_priceList.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) {
          setState(() => _priceIndex = (_priceIndex + 1) % _priceList.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _setupPrices() {
    final theme = widget.theme;
    if (theme['price_weekly'] != null) {
      _priceList.add({
        'price': _toInt(theme['price_weekly']),
        'label': 'สัปดาห์',
      });
    }
    if (theme['price_monthly'] != null) {
      _priceList.add({
        'price': _toInt(theme['price_monthly']),
        'label': 'เดือน',
      });
    }
    if (theme['price_yearly'] != null) {
      _priceList.add({'price': _toInt(theme['price_yearly']), 'label': 'ปี'});
    }

    if (_priceList.isEmpty) {
      final plan = (theme['min_plan'] ?? 'free').toString().toLowerCase();
      if (plan == 'pro') {
        _priceList.addAll([
          {'price': 100, 'label': 'เดือน'},
          {'price': 990, 'label': 'ปี'},
        ]);
      } else if (plan == 'ultimate') {
        _priceList.addAll([
          {'price': 150, 'label': 'เดือน'},
          {'price': 1490, 'label': 'ปี'},
        ]);
      } else {
        _priceList.add({'price': 0, 'label': 'ฟรี'});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final priceInfo = _priceList[_priceIndex];
    final isFree = _toInt(priceInfo['price']) == 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ThemeDetailScreen(theme: theme, imageUrl: widget.imageUrl),
          ),
        );
      },
      child: Container(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: IphoneMockup(
                imageUrl: widget.imageUrl,
                isCurrent: widget.isOwned,
              ),
            ),
            const SizedBox(height: 8),
              Text(
                (theme['name'] ?? 'UNKNOWN THEME').toString().toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 7),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: widget.isOwned
                    ? _statusButton(
                        key: const ValueKey('owned'),
                        text: 'INSTALLED',
                        bg: const Color(0xFFECFDF5),
                        fg: const Color(0xFF059669),
                        border: const Color(0xFFA7F3D0),
                      )
                    : _statusButton(
                        key: ValueKey(_priceIndex),
                        text: isFree
                            ? 'FREE'
                            : '${NumberFormat('#,###').format(_toInt(priceInfo['price']))} / ${priceInfo['label']}',
                        bg: const Color(0xFF292524),
                        fg: Colors.white,
                        border: const Color(0xFF292524),
                        showCoin: !isFree,
                      ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _statusButton({
    required Key key,
    required String text,
    required Color bg,
    required Color fg,
    required Color border,
    bool showCoin = false,
  }) {
    return Container(
      key: key,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 8.4,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          if (showCoin) ...[
            const SizedBox(width: 4),
            Image.asset('lib/assets/cion.png', width: 12, height: 12),
          ],
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF10B981),
        shape: BoxShape.circle,
      ),
    );
  }
}
