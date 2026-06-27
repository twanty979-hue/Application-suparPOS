// lib/widgets/app_sidebar.dart
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../login.dart';
import '../api_service.dart';
import '../screens/dashboard_screen.dart';
import '../screens/db_inspector_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/kitchen_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/menu_management_screen.dart';
import '../screens/pos_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/receipt_history_screen.dart';
import '../screens/store_settings_screen.dart';
import '../screens/theme_selection_screen.dart';
import '../services/storage_service.dart';
import '../services/profile_cache_service.dart';
import 'suparpos_navigation_loader.dart';

class AppSidebar extends StatefulWidget {
  final String activeMenu;

  const AppSidebar({super.key, required this.activeMenu});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _magicAnimController;
  String _profileName = 'โปรไฟล์ของฉัน';
  String _profileEmail = '';
  String? _avatarUrl;
  String? _localAvatarPath;
  bool _hasInvitation = false;
  String _profileRole = 'unknown';

  bool get _canManageStore => _profileRole.trim().toLowerCase() == 'owner';

  static const _purple = Color(0xFF15803D); // Changed to Logo Green
  static const _text = Color(0xFF64748B);
  static const _muted = Color(0xFF94A3B8);
  static const _line = Color(0xFFEFF3F8);
  static const _blue = Color(0xFF15803D); // Changed to Logo Green
  static const _blueSoft = Color(0xFFE8F8EC); // Changed to Soft Green

  @override
  void initState() {
    super.initState();
    _magicAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final brandId = await StorageService.getBrandId();
      final cached = await ProfileCacheService.load(brandId);
      final cachedProfile = cached == null ? null : jsonEncode(cached);

      // 1. โหลดข้อมูลจาก Cache มาแสดงผลก่อนทันที เพื่อลดความหน่วง
      if (cachedProfile != null) {
        final profile = jsonDecode(cachedProfile) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _profileName =
                profile['full_name']?.toString().trim().isNotEmpty == true
                ? profile['full_name'].toString()
                : 'โปรไฟล์ของฉัน';
            _avatarUrl = profile['avatar_url']?.toString();
            _localAvatarPath = profile['local_avatar_path']?.toString();
            _profileEmail = profile['email']?.toString() ?? '';
            _hasInvitation = profile['invited_brand'] != null;
            _profileRole = profile['role']?.toString() ?? _profileRole;
          });
        }
      }

      // 2. แอบยิง API เพื่อเช็คข้อมูลล่าสุด
      final token = await StorageService.getToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse(ApiService.profile),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) return;

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final profile = result['profile'] as Map<String, dynamic>?;
      if (profile == null) return;

      // บันทึกข้อมูลใหม่ลง Cache
      final savedProfile = await ProfileCacheService.save(brandId, profile);

      // อัปเดต UI อีกรอบด้วยข้อมูลล่าสุด (ถ้ามีการเปลี่ยนแปลง)
      if (mounted) {
        setState(() {
          _profileName =
              profile['full_name']?.toString().trim().isNotEmpty == true
              ? profile['full_name'].toString()
              : 'โปรไฟล์ของฉัน';
          _avatarUrl = savedProfile['avatar_url']?.toString();
          _localAvatarPath = savedProfile['local_avatar_path']?.toString();
          _profileEmail = savedProfile['email']?.toString() ?? '';
          _hasInvitation = profile['invited_brand'] != null;
          _profileRole = savedProfile['role']?.toString() ?? _profileRole;
        });
      }
    } catch (_) {
      // ถ้า API พังหรือเน็ตหลุด อย่างน้อยก็ยังมีข้อมูลจาก Cache โชว์อยู่
    }
  }

  @override
  void dispose() {
    _magicAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawerWidth = MediaQuery.sizeOf(context).width < 280 ? 240.0 : 250.0;

    return Drawer(
      width: drawerWidth,
      elevation: 0,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, thickness: 1, color: _line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 14),
                children: [
                  _buildMenuItem(
                    context,
                    menuKey: 'pos',
                    icon: Icons.desktop_windows_outlined,
                    title: 'คิดเงิน (POS)',
                    onTap: () => _openPos(context),
                  ),
                  _buildMenuItem(
                    context,
                    menuKey: 'kitchen',
                    icon: Icons.room_service_outlined,
                    title: 'ออเดอร์ (ครัว)',
                    onTap: () => _openKitchen(context),
                  ),
                  _buildMenuItem(
                    context,
                    menuKey: 'receipt_history',
                    aliases: const {'receipt'},
                    icon: Icons.receipt_long_outlined,
                    title: 'ใบเสร็จย้อนหลัง',
                    page: const ReceiptHistoryScreen(),
                  ),
                  _buildMenuItem(
                    context,
                    menuKey: 'inventory',
                    icon: Icons.inventory_2_outlined,
                    title: 'ระบบคลังสินค้า',
                    page: const InventoryScreen(),
                  ),
                  _buildMenuItem(
                    context,
                    menuKey: 'db_inspector',
                    icon: Icons.storage_rounded,
                    title: 'DB Inspector',
                    page: const DbInspectorScreen(),
                  ),
                  if (_canManageStore) ...[
                    _buildSectionDivider('จัดการร้าน'),
                    _buildMenuItem(
                      context,
                      menuKey: 'dashboard',
                      icon: Icons.insert_chart_outlined_rounded,
                      title: 'Dashboard',
                      page: const DashboardScreen(),
                    ),
                    _buildMenuItem(
                      context,
                      menuKey: 'menu_management',
                      aliases: const {'menu'},
                      icon: Icons.add_box_outlined,
                      title: 'เมนูอาหาร',
                      page: const MenuManagementScreen(),
                    ),
                    _buildMenuItem(
                      context,
                      menuKey: 'settings',
                      icon: Icons.home_outlined,
                      title: 'ตั้งค่าร้าน',
                      onTap: () => _openStoreSettings(context),
                    ),
                  ],
                  _buildSectionDivider('จัดการธีม'),
                  _buildThemeButton(context),
                  const SizedBox(height: 8),
                  _buildMarketplaceButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _replaceFromDrawer(context, const ProfileScreen()),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8EC), // Soft green
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFB7E7C3)), // Green border
                  ),
                  child:
                      _localAvatarPath != null &&
                          _localAvatarPath!.isNotEmpty &&
                          File(_localAvatarPath!).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.file(
                            File(_localAvatarPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.person, color: _purple),
                          ),
                        )
                      : _avatarUrl != null && _avatarUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.network(
                            _avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.person, color: _purple),
                          ),
                        )
                      : const Icon(
                          Icons.person_outline_rounded,
                          color: _purple,
                          size: 22,
                        ),
                ),
                if (_hasInvitation)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.notifications_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () =>
                      _replaceFromDrawer(context, const ProfileScreen()),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Text(
                      _profileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _purple,
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                if (_profileEmail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _profileEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                InkWell(
                  onTap: () => _logout(context),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout_rounded, color: _muted, size: 13),
                        SizedBox(width: 5),
                        Text(
                          'ออกจากระบบ',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              tooltip: 'ปิดเมนู',
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: _muted, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String menuKey,
    required IconData icon,
    required String title,
    Set<String> aliases = const {},
    Widget? page,
    VoidCallback? onTap,
  }) {
    final isSelected =
        widget.activeMenu == menuKey || aliases.contains(widget.activeMenu);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (isSelected) {
              Navigator.pop(context);
              return;
            }
            if (onTap != null) {
              onTap();
              return;
            }
            if (page != null) {
              _replaceFromDrawer(context, page);
            }
          },
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: isSelected ? _blueSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFB7E7C3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? _blue : _text, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF15803D) : _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionDivider(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 3, 15, 11),
      child: Row(
        children: [
          const Expanded(child: Divider(color: _line, height: 1, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Expanded(child: Divider(color: _line, height: 1, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildThemeButton(BuildContext context) {
    final isSelected = widget.activeMenu == 'theme';

    return AnimatedBuilder(
      animation: _magicAnimController,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (!isSelected) {
                _replaceFromDrawer(context, const ThemeSelectionScreen());
              } else {
                Navigator.pop(context);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF16A34A), Color(0xFF22C55E)], // Green gradient
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  children: [
                    const Icon(
                      Icons.palette_outlined,
                      color: Colors.white,
                      size: 21,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'เลือกธีมร้าน',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _MagicStars(animation: _magicAnimController),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarketplaceButton(BuildContext context) {
    final isSelected = widget.activeMenu == 'marketplace';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!isSelected) {
            _replaceFromDrawer(context, const MarketplaceScreen());
          } else {
            Navigator.pop(context);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F8EC), // Soft green
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFB7E7C3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xFF15803D), // Green icon
                  size: 20,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Marketplace',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF15803D), // Green text
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  height: 25,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22C55E), Color(0xFF16A34A)], // Green gradient badge
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _hasInternet() async {
    try {
      final uri = Uri.parse(ApiService.baseUrl);
      final socket = await Socket.connect(
        uri.host,
        uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80),
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _replaceFromDrawer(
    BuildContext context,
    Widget page, {
    bool allowOffline = false,
  }) async {
    if (!allowOffline && !await _hasInternet()) {
      if (!mounted || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            Icons.wifi_off_rounded,
            color: Color(0xFFEF4444),
            size: 42,
          ),
          title: const Text(
            'ไม่พบอินเทอร์เน็ต',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'หน้านี้ต้องเชื่อมต่ออินเทอร์เน็ต แต่หน้าคิดเงินยังใช้งานและบันทึกการขายแบบออฟไลน์ได้ครับ',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('เข้าใจแล้ว'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted || !context.mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();

    // ให้ Drawer มีเวลาเลื่อนปิดก่อนเล็กน้อย แล้วค่อยเปลี่ยนหน้าแบบต่อเนื่อง
    await Future<void>.delayed(const Duration(milliseconds: 110));
    if (!mounted) return;

    navigator.pushReplacement(_smoothRoute(page));
  }

  PageRouteBuilder<void> _smoothRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => SuparPosNavigationLoader(child: page),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openPos(BuildContext context) async {
    final brandId = await StorageService.getBrandId();

    if (!mounted || !context.mounted) {
      return;
    }

    _replaceFromDrawer(
      context,
      PosScreen(brandId: brandId),
      allowOffline: true,
    );
  }

  Future<void> _openKitchen(BuildContext context) async {
    final brandId = await StorageService.getBrandId();

    if (!mounted || !context.mounted) {
      return;
    }

    _replaceFromDrawer(context, KitchenScreen(brandId: brandId));
  }

  Future<void> _openStoreSettings(BuildContext context) async {
    final brandId = await StorageService.getBrandId();

    if (!mounted || !context.mounted) {
      return;
    }

    _replaceFromDrawer(context, StoreSettingsScreen(brandId: brandId));
  }

  Future<void> _logout(BuildContext context) async {
    final token = await StorageService.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse(ApiService.logout),
          headers: {'Authorization': 'Bearer $token'},
        );
      } catch (_) {
        // Local logout must still complete if the device is offline.
      }
    }
    try {
      await GoogleSignIn.instance.signOut();
    } on GoogleSignInException {
      // Email/password users may never have initialized a Google session.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_brand_id');
    await prefs.remove('access_token');

    // เคลียร์ Cache โปรไฟล์ทิ้งตอนล็อคเอาท์ คนอื่นล็อกอินเข้ามาจะได้ไม่เห็น
    await prefs.remove('cached_profile');

    await StorageService.clearAll();

    if (!mounted || !context.mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }
}

class _MagicStars extends StatelessWidget {
  const _MagicStars({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 30,
      child: CustomPaint(
        painter: _MagicSparklesPainter(progress: animation.value),
      ),
    );
  }
}

class _MagicSparklesPainter extends CustomPainter {
  const _MagicSparklesPainter({required this.progress});

  final double progress;

  static const _sparkles = [
    _MagicSparkle(x: 8, y: 18, radius: 5.5, phase: 0.00, speed: 2.0),
    _MagicSparkle(x: 27, y: 9, radius: 8.0, phase: 0.34, speed: 1.6),
    _MagicSparkle(x: 45, y: 20, radius: 4.8, phase: 0.68, speed: 2.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final sparkle in _sparkles) {
      final wave =
          0.5 +
          (0.5 *
              math.sin(
                ((progress * sparkle.speed) + sparkle.phase) * math.pi * 2,
              ));
      final glow = Curves.easeInOut.transform(wave);
      final radius = sparkle.radius * (0.78 + (glow * 0.22));
      final center = Offset(sparkle.x, sparkle.y);

      canvas.drawCircle(
        center,
        radius * 1.45,
        Paint()
          ..color = const Color(
            0xFFFFE57A,
          ).withValues(alpha: 0.05 + (glow * 0.16))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + (glow * 5)),
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.drawPath(
        _sparklePath(radius),
        Paint()
          ..shader = const LinearGradient(
            colors: [Colors.white, Color(0xFFFFE27A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius))
          ..color = Colors.white.withValues(alpha: 0.55 + (glow * 0.45)),
      );
      canvas.drawCircle(
        Offset.zero,
        radius * 0.12,
        Paint()..color = Colors.white.withValues(alpha: 0.72 + (glow * 0.28)),
      );
      canvas.restore();
    }
  }

  Path _sparklePath(double radius) {
    final waist = radius * 0.18;
    return Path()
      ..moveTo(0, -radius)
      ..quadraticBezierTo(waist, -waist, radius, 0)
      ..quadraticBezierTo(waist, waist, 0, radius)
      ..quadraticBezierTo(-waist, waist, -radius, 0)
      ..quadraticBezierTo(-waist, -waist, 0, -radius)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _MagicSparklesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _MagicSparkle {
  const _MagicSparkle({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.speed,
  });

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double speed;
}
