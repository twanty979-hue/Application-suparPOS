import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';

class StorageService {
  // สร้างตู้เซฟเป็น Singleton (เรียกใช้ที่ไหนก็ได้ในแอปโดยไม่ต้อง new ใหม่)
  static const _storage = FlutterSecureStorage();
  static Future<String?>? _refreshOperation;

  // 🔒 ฟังก์ชันบันทึกข้อมูล (ใช้ตอน Login)
  static Future<void> saveToken(String token) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      _storage.write(key: 'access_token', value: token),
      preferences.setBool('startup_session_known', true),
      preferences.setBool('startup_signed_in', true),
    ]);
  }

  static Future<void> saveSession(Map<String, dynamic> session) async {
    final accessToken = session['access_token']?.toString() ?? '';
    final refreshToken = session['refresh_token']?.toString() ?? '';
    final writes = <Future<dynamic>>[];
    if (accessToken.isNotEmpty) {
      writes.add(_storage.write(key: 'access_token', value: accessToken));
      final preferences = await SharedPreferences.getInstance();
      writes.add(preferences.setBool('startup_session_known', true));
      writes.add(preferences.setBool('startup_signed_in', true));
    }
    if (refreshToken.isNotEmpty) {
      writes.add(_storage.write(key: 'refresh_token', value: refreshToken));
    }
    await Future.wait(writes);
  }

  static Future<void> saveBrandId(String brandId) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      _storage.write(key: 'saved_brand_id', value: brandId),
      preferences.setString('startup_brand_id', brandId),
      preferences.setBool('startup_session_known', true),
      preferences.setBool('startup_signed_in', true),
    ]);
  }

  static Future<StartupSessionState> getStartupSessionState() async {
    final preferences = await SharedPreferences.getInstance();
    return StartupSessionState(
      known: preferences.getBool('startup_session_known') ?? false,
      signedIn: preferences.getBool('startup_signed_in') ?? false,
      brandId: preferences.getString('startup_brand_id') ?? '',
    );
  }

  static Future<void> cacheStartupSession({
    required bool signedIn,
    String brandId = '',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool('startup_session_known', true),
      preferences.setBool('startup_signed_in', signedIn),
      if (brandId.isNotEmpty)
        preferences.setString('startup_brand_id', brandId),
    ]);
  }

  // 🔓 ฟังก์ชันดึงข้อมูล (ใช้ตอนดึง API หรือจ่ายเงิน)
  static Future<String?> getToken() async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null || accessToken.isEmpty) return null;
    if (!_isExpiringSoon(accessToken)) return accessToken;

    _refreshOperation ??= _refreshAccessToken();
    try {
      return await _refreshOperation;
    } finally {
      _refreshOperation = null;
    }
  }

  static Future<String?> _refreshAccessToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse(ApiService.refreshSession),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await clearAll();
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final session = decoded['session'];
      if (session is! Map<String, dynamic>) return null;
      await saveSession(session);
      return session['access_token']?.toString();
    } catch (_) {
      // Keep the current session during temporary network outages. API calls can
      // retry when connectivity returns instead of forcing an immediate logout.
      return await _storage.read(key: 'access_token');
    }
  }

  static bool _isExpiringSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final expiresAt = payload is Map<String, dynamic>
          ? (payload['exp'] as num?)?.toInt()
          : null;
      if (expiresAt == null) return false;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return expiresAt <= now + 120;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getBrandId() async {
    return await _storage.read(key: 'saved_brand_id') ?? '';
  }

  // 🗑️ ฟังก์ชันลบข้อมูล (ใช้ตอน Logout)
  static Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      _storage.deleteAll(),
      preferences.setBool('startup_session_known', true),
      preferences.setBool('startup_signed_in', false),
      preferences.remove('startup_brand_id'),
    ]);
  }
}

class StartupSessionState {
  const StartupSessionState({
    required this.known,
    required this.signedIn,
    required this.brandId,
  });

  final bool known;
  final bool signedIn;
  final String brandId;
}
