import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM Background] ${message.data}');
}

class AppNotificationService {
  AppNotificationService._();

  static const String ordersChannelId = 'orders_urgent_v3';
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static bool _ttsReady = false;

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await _setupLocalNotifications();
    await _setupThaiVoice();
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken();
    if (token != null) {
      await _saveFcmTokenToServer(token);
    }

    await _tokenSubscription?.cancel();
    _tokenSubscription = messaging.onTokenRefresh.listen(_saveFcmTokenToServer);

    await _messageSubscription?.cancel();
    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      _showForegroundNotification(message);
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM Opened From Terminated] ${initialMessage.data}');
    }

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM Opened From Background] ${message.data}');
    });
  }

  static Future<void> _saveFcmTokenToServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = await StorageService.getToken();
      if (accessToken == null || accessToken.isEmpty) return;

      final baseUri = Uri.parse(ApiService.baseUrl);
      final url =
          "${baseUri.scheme}://${baseUri.host}:${baseUri.port}/api/update-fcm";

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'fcm_token': token}),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Token saved');
      }
    } catch (e) {
      debugPrint('[FCM] Token save failed: $e');
    }
  }

  static Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotifications.initialize(settings: initializationSettings);

    const channel = AndroidNotificationChannel(
      ordersChannelId,
      'FoodScan Orders',
      description: 'Order and payment alerts',
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('foodscan_order'),
      enableVibration: true,
      showBadge: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static void _showForegroundNotification(RemoteMessage message) {
    final type = message.data['type']?.toString();
    if (type != 'NEW_ORDER' && type != 'ORDER_PAID') return;

    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'FoodScan';
    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        (type == 'NEW_ORDER' ? 'มีออเดอร์ใหม่เข้ามา' : 'มีการอัปเดตออเดอร์');

    _showAndroidNotification(title: title, body: body);

    _playCustomSound();
    _speakThaiNotification(type: type, title: title, body: body);
  }

  static Future<void> _showAndroidNotification({
    required String title,
    required String body,
  }) async {
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          ordersChannelId,
          'FoodScan Orders',
          channelDescription: 'Order and payment alerts',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('foodscan_order'),
          enableVibration: true,
          ticker: 'FoodScan',
        ),
      ),
    );
  }

  static Future<void> _setupThaiVoice() async {
    if (_ttsReady) return;

    await _tts.setLanguage('th-TH');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false);
    _ttsReady = true;
  }

  static Future<void> _speakThaiNotification({
    required String? type,
    required String title,
    required String body,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final brandId = prefs.getString('saved_brand_id');
      if (brandId != null) {
        final enabled =
            prefs.getBool('notification_voice_enabled_$brandId') ?? true;
        if (!enabled) return;
      }

      await _setupThaiVoice();
      await _tts.stop();

      final prefix = type == 'NEW_ORDER'
          ? 'มีออเดอร์ใหม่'
          : type == 'ORDER_PAID'
          ? 'มีการชำระเงินแล้ว'
          : title;
      await _tts.speak('$prefix $body');
    } catch (e) {
      debugPrint('[TTS] speak failed: $e');
    }
  }

  static Future<void> _playCustomSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final brandId = prefs.getString('saved_brand_id');
      if (brandId == null) return;

      final enabled =
          prefs.getBool('notification_sound_enabled_$brandId') ?? true;
      final path = prefs.getString('notification_sound_path_$brandId');
      if (!enabled || path == null || path.isEmpty) return;

      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('[Notification Sound] play failed: $e');
    }
  }

  static Future<void> previewNotificationSound(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
  }

  static Future<void> previewThaiVoice() async {
    await _setupThaiVoice();
    await _tts.stop();
    await _tts.speak('ทดสอบเสียงแจ้งเตือน มีออเดอร์ใหม่เข้ามา');
  }
}
