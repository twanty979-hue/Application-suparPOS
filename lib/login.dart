import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'screens/pos_screen.dart';
import 'services/app_notification_service.dart';
import 'services/auto_print_service.dart';
import 'services/printer_keep_alive_service.dart';
import 'services/revenuecat_service.dart';
import 'services/profile_cache_service.dart';
import 'services/storage_service.dart';
import 'widgets/suparpos_loading.dart';

enum _AuthStep {
  login,
  register,
  recovery,
  resetPassword,
  checkEmail,
  profile,
  brand,
  tutorial,
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _deepLinks = MethodChannel('suparpos/deep_links');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _shopName = TextEditingController();
  final _shopPhone = TextEditingController();

  final _googleSignIn = GoogleSignIn.instance;
  late final Future<void> _googleInitialization;

  _AuthStep _step = _AuthStep.login;
  bool _loading = false;
  bool _routing = false;
  bool _showPassword = false;
  String? _message;
  bool _messageIsError = false;
  String? _brandId;
  String? _accessToken;
  String? _recoveryTicket;
  String? _userId;
  Map<String, dynamic> _userMetadata = const {};
  String _timezone = 'Asia/Bangkok';

  @override
  void initState() {
    super.initState();
    _googleInitialization = _googleSignIn.initialize();
    _deepLinks.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        _handleDeepLink(call.arguments?.toString());
      }
    });
    _deepLinks.invokeMethod<String>('getInitialLink').then(_handleDeepLink);
  }

  void _handleDeepLink(String? rawLink) {
    final uri = rawLink == null ? null : Uri.tryParse(rawLink);
    if (uri == null ||
        uri.scheme != 'com.suparpos.app' ||
        uri.host != 'login-callback') {
      return;
    }
    final type = uri.queryParameters['type'];
    if (type == 'recovery') {
      final ticket = uri.queryParameters['ticket'];
      if (ticket == null || ticket.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _recoveryTicket = ticket;
        _step = _AuthStep.resetPassword;
        _message = null;
        _password.clear();
        _confirmPassword.clear();
      });
    } else if (type == 'verified' && mounted) {
      setState(() {
        _step = _AuthStep.login;
        _message = 'ยืนยันอีเมลสำเร็จแล้ว กรุณาเข้าสู่ระบบ';
        _messageIsError = false;
      });
    }
  }

  @override
  void dispose() {
    _deepLinks.setMethodCallHandler(null);
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _fullName.dispose();
    _phone.dispose();
    _shopName.dispose();
    _shopPhone.dispose();
    super.dispose();
  }

  Future<void> _routeAuthenticated(Map<String, dynamic> session) async {
    if (_routing || _step == _AuthStep.resetPassword) return;
    _routing = true;
    try {
      final accessToken = session['access_token']?.toString() ?? '';
      final user = session['user'] is Map
          ? Map<String, dynamic>.from(session['user'] as Map)
          : <String, dynamic>{};
      if (accessToken.isEmpty || user['id'] == null) {
        throw Exception('ไม่พบข้อมูลเซสชัน');
      }
      _accessToken = accessToken;
      _userId = user['id'].toString();
      _userMetadata = user['user_metadata'] is Map
          ? Map<String, dynamic>.from(user['user_metadata'] as Map)
          : <String, dynamic>{};
      await StorageService.saveSession(session);

      Map<String, dynamic> profile = const {};
      final profileResponse = await http.get(
        Uri.parse(ApiService.profile),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (profileResponse.statusCode >= 200 &&
          profileResponse.statusCode < 300) {
        final decoded = jsonDecode(profileResponse.body);
        if (decoded is Map && decoded['profile'] is Map) {
          profile = Map<String, dynamic>.from(decoded['profile'] as Map);
        }
      } else if (profileResponse.statusCode != 404) {
        throw Exception('ตรวจสอบข้อมูลบัญชีไม่สำเร็จ');
      }

      profile = {
        ...profile,
        'email': profile['email'] ?? user['email'],
        'full_name':
            profile['full_name'] ??
            _userMetadata['full_name'] ??
            _userMetadata['name'],
        'avatar_url':
            profile['avatar_url'] ??
            _userMetadata['avatar_url'] ??
            _userMetadata['picture'],
      };

      final brandId = profile['brand_id']?.toString() ?? '';
      if (brandId.isNotEmpty && brandId.toLowerCase() != 'null') {
        await ProfileCacheService.save(brandId, profile);
        await _finishLogin(brandId, accessToken);
        return;
      }

      if (!mounted) return;
      _fullName.text =
          (profile['full_name'] ??
                  _userMetadata['full_name'] ??
                  _userMetadata['name'] ??
                  '')
              .toString();
      _phone.text = (profile['phone'] ?? '').toString();
      setState(() {
        _step = _fullName.text.trim().isEmpty
            ? _AuthStep.profile
            : _AuthStep.brand;
        _message = null;
      });
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      _routing = false;
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    switch (_step) {
      case _AuthStep.login:
        return _login();
      case _AuthStep.register:
        return _register();
      case _AuthStep.recovery:
        return _sendRecovery();
      case _AuthStep.resetPassword:
        return _updatePassword();
      case _AuthStep.profile:
        return _saveProfile();
      case _AuthStep.brand:
        return _saveBrand();
      case _AuthStep.tutorial:
        return _runTutorial();
      case _AuthStep.checkEmail:
        setState(() => _step = _AuthStep.login);
        return;
    }
  }

  Future<void> _login() async {
    if (!_validateEmailPassword()) return;
    await _runLoading(() async {
      final result = await _postJson(ApiService.login, {
        'email': _email.text.trim(),
        'password': _password.text,
      });
      final session = result['session'] as Map<String, dynamic>?;
      if (session == null) throw Exception('ไม่พบข้อมูลเซสชัน');
      await _routeAuthenticated(session);
    });
  }

  Future<void> _register() async {
    if (!_validateEmailPassword(requireConfirm: true)) return;
    await _runLoading(() async {
      final result = await _postJson(ApiService.register, {
        'email': _email.text.trim(),
        'password': _password.text,
        'source': 'app',
      });
      final session = result['session'] as Map<String, dynamic>?;
      if (session != null &&
          (session['access_token']?.toString().isNotEmpty ?? false)) {
        await _routeAuthenticated(session);
      } else if (mounted) {
        setState(() {
          _step = _AuthStep.checkEmail;
          _message = null;
        });
      }
    });
  }

  Future<void> _googleAuth() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await _googleInitialization;
      if (!_googleSignIn.supportsAuthenticate()) {
        throw Exception('อุปกรณ์นี้ไม่รองรับ Google Sign-In');
      }

      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('ไม่ได้รับ Google ID token');
      }

      final result = await _postJson(ApiService.googleAuth, {
        'idToken': idToken,
      });
      final session = result['session'];
      if (session is! Map) throw Exception('ไม่พบข้อมูลเซสชัน');
      await _routeAuthenticated(Map<String, dynamic>.from(session));
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled) {
        _showMessage(_friendlyError(error), error: true);
      }
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendRecovery() async {
    if (!_validEmail(_email.text)) {
      _showMessage('กรุณากรอกอีเมลให้ถูกต้อง', error: true);
      return;
    }
    await _runLoading(() async {
      await _postJson(ApiService.recovery, {
        'email': _email.text.trim(),
        'source': 'app',
      });
      _showMessage('ส่งลิงก์ตั้งรหัสผ่านใหม่ไปที่อีเมลแล้ว');
    });
  }

  Future<void> _updatePassword() async {
    if (_password.text.length < 6) {
      _showMessage('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร', error: true);
      return;
    }
    if (_password.text != _confirmPassword.text) {
      _showMessage('รหัสผ่านทั้งสองช่องไม่ตรงกัน', error: true);
      return;
    }
    await _runLoading(() async {
      final token = _accessToken ?? await StorageService.getToken();
      if ((token == null || token.isEmpty) && _recoveryTicket == null) {
        return _expiredSession();
      }
      _accessToken = token;
      await _postJson(ApiService.updatePassword, {
        'password': _password.text,
        if (_recoveryTicket != null) 'ticket': _recoveryTicket,
      });
      _recoveryTicket = null;
      await StorageService.clearAll();
      if (!mounted) return;
      setState(() {
        _step = _AuthStep.login;
        _password.clear();
        _confirmPassword.clear();
      });
      _showMessage('เปลี่ยนรหัสผ่านสำเร็จ กรุณาเข้าสู่ระบบอีกครั้ง');
    });
  }

  Future<void> _saveProfile() async {
    if (_fullName.text.trim().isEmpty) {
      _showMessage('กรุณากรอกชื่อ-นามสกุล', error: true);
      return;
    }
    final userId = _userId;
    if (userId == null || userId.isEmpty) return _expiredSession();

    await _runLoading(() async {
      await _postJson(ApiService.setupProfile, {
        'userId': userId,
        'fullName': _fullName.text.trim(),
        'phone': _phone.text.trim(),
        'avatarUrl': '',
      });
      if (mounted) setState(() => _step = _AuthStep.brand);
    });
  }

  Future<void> _saveBrand() async {
    if (_shopName.text.trim().isEmpty) {
      _showMessage('กรุณากรอกชื่อร้าน', error: true);
      return;
    }
    final userId = _userId;
    if (userId == null || userId.isEmpty) return _expiredSession();

    await _runLoading(() async {
      final result = await _postJson(ApiService.setupBrand, {
        'userId': userId,
        'shopName': _shopName.text.trim(),
        'shopPhone': _shopPhone.text.trim(),
      });
      _brandId = result['brandId']?.toString();
      if (_brandId == null || _brandId!.isEmpty) {
        throw Exception('สร้างร้านสำเร็จแต่ไม่พบรหัสร้าน');
      }
      if (mounted) setState(() => _step = _AuthStep.tutorial);
    });
  }

  Future<void> _runTutorial() async {
    final brandId = _brandId;
    final accessToken = _accessToken ?? await StorageService.getToken();
    if (brandId == null || accessToken == null || accessToken.isEmpty) {
      return _expiredSession();
    }

    await _runLoading(() async {
      await _postJson(ApiService.setupTutorial, {
        'brandId': brandId,
        'timezone': _timezone,
      });
      await _finishLogin(brandId, accessToken);
    });
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (_accessToken != null && _accessToken!.isNotEmpty)
          'Authorization': 'Bearer $_accessToken',
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body);
    final result = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(result['error'] ?? 'เชื่อมต่อระบบไม่สำเร็จ');
    }
    return result;
  }

  Future<void> _finishLogin(String brandId, String accessToken) async {
    await StorageService.saveBrandId(brandId);
    await StorageService.saveToken(accessToken);
    try {
      await AppNotificationService.initialize();
    } catch (error, stackTrace) {
      debugPrint('Notification service restart failed after login: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    await RevenueCatService.configure(appUserId: brandId);
    AutoPrintService.instance.start(brandId);
    try {
      PrinterKeepAliveService.instance.start(brandId);
    } catch (error, stackTrace) {
      debugPrint('Printer keep-alive start failed after login: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => PosScreen(brandId: brandId)),
      (_) => false,
    );
  }

  Future<void> _runLoading(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validateEmailPassword({bool requireConfirm = false}) {
    if (!_validEmail(_email.text)) {
      _showMessage('กรุณากรอกอีเมลให้ถูกต้อง', error: true);
      return false;
    }
    if (_password.text.length < 6) {
      _showMessage('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร', error: true);
      return false;
    }
    if (requireConfirm && _password.text != _confirmPassword.text) {
      _showMessage('รหัสผ่านทั้งสองช่องไม่ตรงกัน', error: true);
      return false;
    }
    return true;
  }

  bool _validEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  void _expiredSession() {
    _showMessage('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่', error: true);
    setState(() => _step = _AuthStep.login);
  }

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('Invalid login credentials')) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (text.contains('Email not confirmed')) {
      return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
    }
    if (text.contains('User already registered')) {
      return 'อีเมลนี้สมัครสมาชิกแล้ว';
    }
    return text;
  }

  void _setStep(_AuthStep step) {
    setState(() {
      _step = step;
      _message = null;
      _password.clear();
      _confirmPassword.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF2FBF4),
      body: Stack(
        children: [
          Positioned(
            top: -110,
            right: -90,
            child: _orb(const Color(0xFF22C55E).withValues(alpha: 0.16)),
          ),
          Positioned(
            bottom: -130,
            left: -80,
            child: _orb(const Color(0xFF86EFAC).withValues(alpha: 0.20)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: size.height < 650 ? 12 : 28,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 430),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A334155),
                        blurRadius: 35,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Column(
                      key: ValueKey(_step),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _header(),
                        const SizedBox(height: 22),
                        if (_message != null) ...[
                          _messageBox(),
                          const SizedBox(height: 16),
                        ],
                        ..._fields(),
                        const SizedBox(height: 18),
                        _primaryButton(),
                        if (_showGoogle) ...[
                          const SizedBox(height: 16),
                          _divider(),
                          const SizedBox(height: 16),
                          _googleButton(),
                        ],
                        const SizedBox(height: 18),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_loading || _routing)
            const Positioned.fill(
              child: IgnorePointer(child: SuparPosLoading(fullScreen: true)),
            ),
        ],
      ),
    );
  }

  Widget _orb(Color color) => Container(
    width: 280,
    height: 280,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 35)],
    ),
  );

  Widget _header() {
    final data = switch (_step) {
      _AuthStep.login => ('ยินดีต้อนรับ', 'เข้าสู่ระบบ SuparPOS'),
      _AuthStep.register => (
        'สร้างบัญชีใหม่',
        'เริ่มต้นร้านของคุณในไม่กี่ขั้นตอน',
      ),
      _AuthStep.recovery => ('ลืมรหัสผ่าน', 'รับลิงก์ตั้งรหัสใหม่ทางอีเมล'),
      _AuthStep.resetPassword => (
        'ตั้งรหัสผ่านใหม่',
        'กำหนดรหัสผ่านอย่างน้อย 6 ตัวอักษร',
      ),
      _AuthStep.checkEmail => (
        'ตรวจสอบอีเมล',
        'กดยืนยันในอีเมลแล้วแอปจะเปิดต่อให้อัตโนมัติ',
      ),
      _AuthStep.profile => ('ข้อมูลส่วนตัว', 'ขั้นตอนที่ 1 จาก 3'),
      _AuthStep.brand => ('ข้อมูลร้าน', 'ขั้นตอนที่ 2 จาก 3'),
      _AuthStep.tutorial => ('ตั้งค่าระบบ', 'ขั้นตอนสุดท้าย'),
    };
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F8EC), Color(0xFFD1F3D9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFB7E7C3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3315803D),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Image.asset('lib/assets/app_logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(height: 15),
        const Text(
          'SuparPOS',
          style: TextStyle(
            color: Color(0xFF15803D),
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          data.$1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          data.$2,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  List<Widget> _fields() {
    switch (_step) {
      case _AuthStep.login:
        return [
          _field(
            _email,
            'อีเมล',
            Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 13),
          _passwordField(_password, 'รหัสผ่าน'),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _setStep(_AuthStep.recovery),
              child: const Text('ลืมรหัสผ่าน?'),
            ),
          ),
        ];
      case _AuthStep.register:
        return [
          _field(
            _email,
            'อีเมล',
            Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 13),
          _passwordField(_password, 'รหัสผ่าน'),
          const SizedBox(height: 13),
          _passwordField(_confirmPassword, 'ยืนยันรหัสผ่าน'),
        ];
      case _AuthStep.recovery:
        return [
          _field(
            _email,
            'อีเมลที่ใช้สมัคร',
            Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
        ];
      case _AuthStep.resetPassword:
        return [
          _passwordField(_password, 'รหัสผ่านใหม่'),
          const SizedBox(height: 13),
          _passwordField(_confirmPassword, 'ยืนยันรหัสผ่านใหม่'),
        ];
      case _AuthStep.checkEmail:
        return [
          const Icon(
            Icons.mail_outline_rounded,
            color: Color(0xFF2563EB),
            size: 48,
          ),
          const SizedBox(height: 10),
          Text(
            _email.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ];
      case _AuthStep.profile:
        return [
          _field(_fullName, 'ชื่อ-นามสกุล', Icons.badge_outlined),
          const SizedBox(height: 13),
          _field(
            _phone,
            'เบอร์โทรศัพท์',
            Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
        ];
      case _AuthStep.brand:
        return [
          _field(_shopName, 'ชื่อร้าน', Icons.storefront_outlined),
          const SizedBox(height: 13),
          _field(
            _shopPhone,
            'เบอร์โทรร้าน',
            Icons.phone_in_talk_outlined,
            keyboardType: TextInputType.phone,
          ),
        ];
      case _AuthStep.tutorial:
        return [
          DropdownButtonFormField<String>(
            initialValue: _timezone,
            decoration: _inputDecoration('เขตเวลาของร้าน', Icons.public),
            items: const [
              DropdownMenuItem(
                value: 'Asia/Bangkok',
                child: Text('ไทย — Asia/Bangkok'),
              ),
              DropdownMenuItem(
                value: 'Asia/Phnom_Penh',
                child: Text('กัมพูชา — Asia/Phnom Penh'),
              ),
              DropdownMenuItem(
                value: 'Asia/Vientiane',
                child: Text('ลาว — Asia/Vientiane'),
              ),
              DropdownMenuItem(
                value: 'Asia/Yangon',
                child: Text('เมียนมา — Asia/Yangon'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _timezone = value);
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'ระบบจะสร้างโต๊ะ หมวดหมู่ และเมนูตัวอย่างให้โดยอัตโนมัติ',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ];
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: _inputDecoration(label, icon),
    );
  }

  Widget _passwordField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: !_showPassword,
      textInputAction: TextInputAction.next,
      decoration: _inputDecoration(label, Icons.lock_outline_rounded).copyWith(
        suffixIcon: IconButton(
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(
            _showPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF15803D), width: 1.7),
      ),
    );
  }

  Widget _messageBox() {
    final color = _messageIsError
        ? const Color(0xFFDC2626)
        : const Color(0xFF059669);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _loading ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF15803D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                _buttonLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }

  String get _buttonLabel => switch (_step) {
    _AuthStep.login => 'เข้าสู่ระบบ',
    _AuthStep.register => 'สมัครสมาชิก',
    _AuthStep.recovery => 'ส่งลิงก์รีเซ็ตรหัสผ่าน',
    _AuthStep.resetPassword => 'บันทึกรหัสผ่านใหม่',
    _AuthStep.checkEmail => 'กลับหน้าเข้าสู่ระบบ',
    _AuthStep.profile => 'บันทึกและไปต่อ',
    _AuthStep.brand => 'สร้างร้านและไปต่อ',
    _AuthStep.tutorial => 'เริ่มต้นใช้งาน SuparPOS',
  };

  bool get _showGoogle =>
      _step == _AuthStep.login || _step == _AuthStep.register;

  Widget _divider() => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'หรือ',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
      ),
      Expanded(child: Divider()),
    ],
  );

  Widget _googleButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _googleAuth,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF334155),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: SvgPicture.asset(
          'lib/assets/google_g.svg',
          width: 24,
          height: 24,
        ),
        label: Text(
          _step == _AuthStep.register
              ? 'สมัครด้วย Google'
              : 'เข้าสู่ระบบด้วย Google',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _footer() {
    if (_step == _AuthStep.login) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('ยังไม่มีบัญชี?', style: TextStyle(fontSize: 12)),
          TextButton(
            onPressed: () => _setStep(_AuthStep.register),
            child: const Text('สมัครสมาชิกฟรี'),
          ),
        ],
      );
    }
    if (_step == _AuthStep.register || _step == _AuthStep.recovery) {
      return TextButton.icon(
        onPressed: () => _setStep(_AuthStep.login),
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: const Text('กลับหน้าเข้าสู่ระบบ'),
      );
    }
    return const Text(
      'บัญชีเดียว ใช้งานได้ทั้งแอปและเว็บไซต์',
      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
    );
  }
}
