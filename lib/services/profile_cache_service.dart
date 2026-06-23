import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileCacheService {
  static String _key(String brandId) => 'cached_profile_$brandId';

  static Future<Map<String, dynamic>?> load(String brandId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_key(brandId)) ?? prefs.getString('cached_profile');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> save(
    String brandId,
    Map<String, dynamic> profile,
  ) async {
    final previous = await load(brandId) ?? <String, dynamic>{};
    final cached = <String, dynamic>{...previous, ...profile};
    for (final key in const ['email', 'full_name', 'avatar_url', 'role']) {
      final value = cached[key]?.toString().trim() ?? '';
      if (value.isEmpty || value.toLowerCase() == 'null') {
        cached[key] = previous[key];
      }
    }
    final avatarUrl = cached['avatar_url']?.toString().trim() ?? '';
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      try {
        final directory = await getApplicationSupportDirectory();
        final avatarDirectory = Directory(
          path_util.join(directory.path, 'profile_images', brandId),
        );
        await avatarDirectory.create(recursive: true);
        final extension = path_util.extension(Uri.parse(avatarUrl).path);
        final file = File(
          path_util.join(
            avatarDirectory.path,
            'avatar${extension.isNotEmpty && extension.length <= 6 ? extension : '.jpg'}',
          ),
        );
        final response = await http
            .get(Uri.parse(avatarUrl))
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(response.bodyBytes, flush: true);
          cached['local_avatar_path'] = file.path;
        }
      } catch (_) {
        // Remote avatar remains available and will be retried next refresh.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(cached);
    await Future.wait([
      prefs.setString(_key(brandId), encoded),
      prefs.setString('cached_profile', encoded),
    ]);
    return cached;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (key) => key == 'cached_profile' || key.startsWith('cached_profile_'),
    );
    await Future.wait(keys.map(prefs.remove));
  }
}
