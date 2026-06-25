// lib/screens/theme_selection_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../widgets/iphone_mockup.dart';

class ThemeSelectionScreen extends StatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  State<ThemeSelectionScreen> createState() => _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends State<ThemeSelectionScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const Color _ink = Color(0xFF0B1730);
  static const Color _mutedInk = Color(0xFF8EA0B7);
  static const Color _pageBg = Color(0xFFF5F8FB);
  static const Color _softPanel = Color(0xFFE9EEF4);
  static const Color _line = Color(0xFFD9E2EC);
  static const Color _mint = Color(0xFFE9FFF6);
  static const Color _mintInk = Color(0xFF08A66A);

  bool _isLoading = true;
  String _activeTab = 'active';
  String _selectedCategory = 'ALL';
  String _applyingThemeId = '';

  List<dynamic> _themes = [];
  List<dynamic> _categories = [
    {'id': 'ALL', 'name': 'ALL THEMES'},
  ];
  String _currentThemeMode = 'standard';
  bool _isOwner = false;

  final String _cdnBaseUrl = 'https://img.pos-foodscan.com';

  @override
  void initState() {
    super.initState();
    _fetchThemes();
  }

  Future<void> _fetchThemes() async {
    setState(() => _isLoading = true);

    try {
      final accessToken = await StorageService.getToken();
      final response = await http.get(
        Uri.parse(ApiService.themes),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('API Error: ${response.statusCode}');
      }

      final result = jsonDecode(response.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Cannot load themes');
      }

      final data = result['data'] ?? {};
      final currentConfig = data['currentConfig'];
      final categories = List<dynamic>.from(data['categories'] ?? []);

      if (categories.isEmpty || categories.first['id']?.toString() != 'ALL') {
        categories.insert(0, {'id': 'ALL', 'name': 'ALL THEMES'});
      }

      if (!mounted) return;
      setState(() {
        _themes = List<dynamic>.from(data['themes'] ?? []);
        _categories = categories;
        _currentThemeMode = currentConfig is Map
            ? (currentConfig['mode']?.toString() ?? 'standard')
            : 'standard';
        _isOwner = data['isOwner'] == true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch Themes Error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _applyTheme(
    String themeId,
    String slug,
    String themeMode,
  ) async {
    if (!_isOwner) {
      _showSnack('เฉพาะเจ้าของร้านเท่านั้นที่เปลี่ยนธีมได้', Colors.red);
      return;
    }

    setState(() => _applyingThemeId = themeId);

    try {
      final accessToken = await StorageService.getToken();

      final response = await http.post(
        Uri.parse(ApiService.applyTheme),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'slug': slug, 'themeMode': themeMode}),
      );

      final result = jsonDecode(response.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Apply theme failed');
      }

      if (!mounted) return;
      setState(() => _currentThemeMode = themeMode);
      _showSnack('เปลี่ยนธีมสำเร็จ!', Colors.green);
    } catch (e) {
      if (mounted) {
        _showSnack('เกิดข้อผิดพลาด: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _applyingThemeId = '');
      }
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
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

  @override
  Widget build(BuildContext context) {
    final displayThemes = _themes.where((theme) {
      final isExpired = _isThemeExpired(theme);
      final mkt = theme['marketplace_themes'];
      final isMatchTab = _activeTab == 'active' ? !isExpired : isExpired;
      final isMatchCategory =
          _selectedCategory == 'ALL' ||
          (mkt is Map && mkt['category_id']?.toString() == _selectedCategory);

      return isMatchTab && isMatchCategory;
    }).toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _pageBg,
      drawer: const AppSidebar(activeMenu: 'themes'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildTabToggle(),
            _buildCategoryFilter(),
            Expanded(
              child: _isLoading
                  ? const SuparPosLoading(fullScreen: false)
                  : displayThemes.isEmpty
                  ? _buildEmptyState()
                  : _buildThemesGrid(displayThemes),
            ),
          ],
        ),
      ),
    );
  }

  bool _isThemeExpired(dynamic theme) {
    if (theme is! Map) return false;
    if (theme['is_expired'] == true) return true;

    final purchaseType = theme['purchase_type']?.toString();
    if (purchaseType == 'lifetime') return false;

    final rawDaysLeft = theme['days_left'];
    final daysLeft = rawDaysLeft is num
        ? rawDaysLeft.toInt()
        : int.tryParse(rawDaysLeft?.toString() ?? '');
    return daysLeft != null && daysLeft <= 0;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        10,
        16,
        0,
      ), // ปรับ padding ซ้ายนิดนึงให้ปุ่มชิดขอบพอดี
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.center, // จัดให้อยู่กึ่งกลางแนวตั้งพร้อมๆ กัน
        children: [
          // 1. ฝั่งซ้ายสุด: ปุ่ม Hamburger Menu สำหรับเปิด Sidebar
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.menu_rounded, color: _ink, size: 26),
              ),
            ),
          ),
          const SizedBox(
            width: 4,
          ), // เว้นระยะห่างระหว่างปุ่มกับตัวหนังสือนิดนึง
          // 2. ขยับมาทางขวา: ข้อความ MY THEMES
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY THEMES',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    height: 1,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'MANAGED COLLECTION',
                  style: TextStyle(
                    color: _mutedInk,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.9,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        height: 40, // เพิ่มความสูงขึ้นอีกนิดให้ดูอวบอิ่ม สบายตา
        decoration: BoxDecoration(
          color: _softPanel, // สีพื้นหลังเทาอ่อนนวลๆ
          borderRadius: BorderRadius.circular(
            20,
          ), // โค้งมนแบบ Pill Shape สมบูรณ์
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildTabButton('ACTIVE', Icons.grid_view_rounded, 'active'),
            _buildTabButton('HISTORY', Icons.history_rounded, 'history'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, IconData icon, String tabId) {
    final isActive = _activeTab == tabId;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // เปลี่ยน BorderRadius ให้โค้งมนเต็มที่ตามตัวแถบ
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _activeTab = tabId),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            // สั่งให้ Alignment อยู่ตรงกลาง เพื่อให้เนื้อหา (Row) อยู่กลางปุ่มที่ขยายเต็ม
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(16), // ล้อไปกับขอบนอก
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: _ink.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            // ตัวเนื้อหาข้างในไม่ต้องใช้ Expanded แล้ว ปล่อยให้อยู่ตรงกลางปุ่มที่ขยายเต็ม
            child: Row(
              mainAxisSize:
                  MainAxisSize.min, // บังคับให้ไอคอนกับข้อความชิดกันตรงกลาง
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: isActive ? 1.0 : 0.6,
                  child: Icon(
                    icon,
                    size: 14,
                    color: isActive ? _ink : const Color(0xFF6E7F93),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    color: isActive ? _ink : const Color(0xFF6E7F93),
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                    letterSpacing: 0.5,
                    height: 1,
                  ),
                  child: Text(title),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 31, 16, 18),
      child: Container(
        height: 25,
        padding: const EdgeInsets.only(left: 10, right: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedCategory,
            isDense: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF6E7F93),
              size: 14,
            ),
            style: const TextStyle(
              color: _ink,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
            ),
            selectedItemBuilder: (context) {
              return _categories.map<Widget>((cat) {
                return _buildCategoryLabel(cat);
              }).toList();
            },
            items: _categories.map<DropdownMenuItem<String>>((cat) {
              final id = _categoryId(cat);
              return DropdownMenuItem<String>(
                value: id,
                child: _buildCategoryLabel(cat),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCategory = value);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryLabel(dynamic cat) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.filter_alt_outlined,
          color: Color(0xFF6E7F93),
          size: 10,
        ),
        const SizedBox(width: 6),
        Text(_categoryName(cat).toUpperCase(), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  String _categoryId(dynamic cat) {
    if (cat is Map) return cat['id']?.toString() ?? 'ALL';
    return 'ALL';
  }

  String _categoryName(dynamic cat) {
    if (cat is Map) return cat['name']?.toString() ?? 'ALL THEMES';
    return 'ALL THEMES';
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'ไม่พบธีมในหมวดหมู่นี้',
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildThemesGrid(List<dynamic> displayThemes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columnCount = width < 430
            ? 3
            : width < 680
            ? 4
            : width < 980
            ? 5
            : 6;
        final spacing = width < 430 ? 10.0 : 16.0;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            childAspectRatio: 0.36,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 14,
          ),
          itemCount: displayThemes.length,
          itemBuilder: (context, index) {
            final theme = Map<String, dynamic>.from(
              displayThemes[index] as Map,
            );
            return _buildThemeCard(theme);
          },
        );
      },
    );
  }

  Widget _buildThemeCard(Map<String, dynamic> theme) {
    final mkt = theme['marketplace_themes'] is Map
        ? Map<String, dynamic>.from(theme['marketplace_themes'] as Map)
        : <String, dynamic>{};
    final themeId = theme['id']?.toString() ?? '';
    final themeMode = mkt['theme_mode']?.toString() ?? '';
    final slug = mkt['slug']?.toString() ?? '';
    final isCurrent = themeMode == _currentThemeMode;
    final isLifetime = theme['purchase_type']?.toString() == 'lifetime';
    final isApplying = _applyingThemeId == themeId;
    final isExpired = _isThemeExpired(theme);
    final imageUrl = _getImageUrl(mkt['image_url']?.toString());

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 0.48, // ปรับให้เพรียวขึ้นสไตล์ iPhone
          child: IphoneMockup(imageUrl: imageUrl, isCurrent: isCurrent),
        ),
        const SizedBox(height: 7),
        Text(
          (mkt['name'] ?? 'UNKNOWN THEME').toString().toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _ink,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Center(child: _buildDurationPill(theme, isLifetime)),
        const SizedBox(height: 9),
        SizedBox(
          height: 22,
          child: isExpired
              ? _buildExpiredButton()
              : isCurrent
              ? _buildCurrentButton()
              : _buildApplyButton(
                  isApplying: isApplying,
                  enabled:
                      themeId.isNotEmpty &&
                      slug.isNotEmpty &&
                      themeMode.isNotEmpty,
                  onPressed: () => _applyTheme(themeId, slug, themeMode),
                ),
        ),
      ],
    );

    if (!isExpired) return card;

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.42, child: card),
        const Positioned.fill(child: _ExpiredThemeOverlay()),
      ],
    );
  }

  Widget _buildDurationPill(Map<String, dynamic> theme, bool isLifetime) {
    final label = isLifetime
        ? 'Lifetime'
        : '${theme['days_left']?.toString() ?? '-'} Days';

    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _mint,
        border: Border.all(color: const Color(0xFFA7F3D0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLifetime
                ? Icons.workspace_premium_rounded
                : Icons.hourglass_empty_rounded,
            color: _mintInk,
            size: 9,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: _mintInk,
              fontSize: 7.5,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyButton({
    required bool isApplying,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _ink,
        disabledBackgroundColor: const Color(0xFFCBD5E1),
        elevation: 0,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: isApplying || !enabled ? null : onPressed,
      child: isApplying
          ? const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Text(
              'APPLY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 7.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
    );
  }

  Widget _buildCurrentButton() {
    return Container(
      decoration: BoxDecoration(
        color: _mint,
        border: Border.all(color: const Color(0xFF7CE3B0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_rounded, color: _mintInk, size: 10),
          SizedBox(width: 4),
          Text(
            'CURRENT',
            style: TextStyle(
              color: _mintInk,
              fontSize: 7.5,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Text(
          'EXPIRED',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _ExpiredThemeOverlay extends StatelessWidget {
  const _ExpiredThemeOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ExpiredThemePainter(),
        child: Center(
          child: Transform.rotate(
            angle: -0.18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1730).withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: const Text(
                'EXPIRED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpiredThemePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE11D48).withValues(alpha: 0.88)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(4, 4),
      Offset(size.width - 4, size.height - 4),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 4, 4),
      Offset(4, size.height - 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
