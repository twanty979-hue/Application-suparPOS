// lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

// 🌟 เพิ่ม import ตัวนี้เข้ามาเพื่อให้มันรู้จัก Purchases ครับ
import 'package:purchases_flutter/purchases_flutter.dart';

import 'login.dart';
import 'services/app_notification_service.dart';
import 'services/auto_print_service.dart';
import 'services/printer_keep_alive_service.dart';
import 'screens/pos_screen.dart';
import 'screens/products_main_screen.dart';
import 'services/storage_service.dart';
import 'services/revenuecat_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoodScanApp());
}

class FoodScanApp extends StatelessWidget {
  const FoodScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: AppNotificationService.scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'SuparPOS',
      theme: ThemeData(
        useMaterial3: true,
        // ปรับพื้นหลังเป็นสีเทาอ่อนๆ (Slate 50) เพื่อไม่ให้สว่างแสบตาเกินไป
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          // ส่วน surface (พวกการ์ด/กล่อง) ให้เป็นสีขาว เพื่อให้ตัดกับพื้นหลังเทาและดูลอยขึ้นมา
          surface: Colors.white,
        ),
        fontFamily: 'Kanit',
      ),
      home: const _StartupGate(),
      routes: {'/menu_management': (context) => const ProductsMainScreen()},
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  _BootstrapData? _bootstrapData;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_resolveStartup());
    });
  }

  Future<void> _resolveStartup() async {
    try {
      final data = await _bootstrap();
      if (!mounted) return;
      setState(() => _bootstrapData = data);
    } catch (error) {
      if (!mounted) return;
      setState(() => _startupError = error.toString());
    }
  }

  Future<_BootstrapData> _bootstrap() async {
    unawaited(initializeDateFormatting('th', null));
    final startupState = await StorageService.getStartupSessionState();

    if (startupState.known) {
      _scheduleBackgroundServices(startupState.brandId);
      return _BootstrapData(
        signedIn: startupState.signedIn && startupState.brandId.isNotEmpty,
        brandId: startupState.brandId.isEmpty ? null : startupState.brandId,
      );
    }

    // Existing installs do one legacy secure-storage read, then every next
    // launch can choose the first screen from the lightweight local cache.
    final legacyResults = await Future.wait<dynamic>([
      StorageService.getToken(),
      StorageService.getBrandId(),
    ]);
    final accessToken = legacyResults[0] as String?;
    final savedBrandId = legacyResults[1] as String;
    final signedIn =
        accessToken != null &&
        accessToken.isNotEmpty &&
        savedBrandId.isNotEmpty;
    await StorageService.cacheStartupSession(
      signedIn: signedIn,
      brandId: savedBrandId,
    );

    _scheduleBackgroundServices(savedBrandId);

    return _BootstrapData(
      signedIn: signedIn,
      brandId: savedBrandId.isEmpty ? null : savedBrandId,
    );
  }

  void _scheduleBackgroundServices(String savedBrandId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 350),
          () => _startBackgroundServices(savedBrandId),
        ),
      );
    });
  }

  Future<void> _startBackgroundServices(String savedBrandId) async {
    try {
      await dotenv.load(fileName: '.env');
      await Future.wait([
        Purchases.setLogLevel(LogLevel.debug),
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      ]);
      await AppNotificationService.initialize();
      if (savedBrandId.isNotEmpty) {
        await RevenueCatService.configure(appUserId: savedBrandId);
        AutoPrintService.instance.start(savedBrandId);
        PrinterKeepAliveService.instance.start(savedBrandId);
      }
    } catch (error, stackTrace) {
      debugPrint('Background startup service failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final startupError = _startupError;
    if (startupError != null) {
      return _StartupError(error: startupError);
    }

    final data = _bootstrapData;
    if (data == null) {
      return const _StartupSplash();
    }

    if (data.signedIn && data.brandId != null) {
      return PosScreen(brandId: data.brandId!);
    }
    return const LoginPage();
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF70C56B));
  }
}

class _BootstrapData {
  const _BootstrapData({required this.signedIn, required this.brandId});

  final bool signedIn;
  final String? brandId;
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF70C56B),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Colors.white,
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'เปิด SuparPOS ไม่สำเร็จ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
