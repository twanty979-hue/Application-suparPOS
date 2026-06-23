import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'storage_service.dart';

class RevenueCatService {
  static bool _configured = false;

  static Future<void> configure({String? appUserId}) async {
    if (!Platform.isAndroid) return;

    final apiKey = dotenv.env['REVENUECAT_ANDROID_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw Exception('ยังไม่ได้ตั้งค่า REVENUECAT_ANDROID_KEY ในไฟล์ .env');
    }

    final isConfigured = await Purchases.isConfigured;
    if (!_configured && !isConfigured) {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _configured = true;
    }

    final userId = (appUserId == null || appUserId.isEmpty)
        ? await StorageService.getBrandId()
        : appUserId;
    if (userId.isNotEmpty) {
      final currentUserId = await Purchases.appUserID;
      if (currentUserId != userId) {
        await Purchases.logIn(userId);
      }
    }
  }

  static Future<Offering> getCurrentOffering() async {
    await configure();
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) {
      throw Exception('ยังไม่ได้ตั้ง Offering ปัจจุบันใน RevenueCat');
    }
    return current;
  }

  static Future<Package> packageFor({
    required String planId,
    required String period,
  }) async {
    final offering = await getCurrentOffering();
    final normalizedPlan = planId.toLowerCase();
    final normalizedPeriod = period.toLowerCase();

    final package = offering.availablePackages.cast<Package?>().firstWhere((
      candidate,
    ) {
      if (candidate == null) return false;
      return _packageMatches(candidate, normalizedPlan, normalizedPeriod);
    }, orElse: () => null);

    if (package == null) {
      // 🌟 ดึงชื่อที่มีอยู่จริงใน RevenueCat มาแสดงบนหน้าจอ Error เลย
      final availableIds = offering.availablePackages
          .map((p) => p.identifier)
          .join(', ');
      throw Exception(
        'หาแพ็กเกจ $planId ($period) ไม่เจอครับนาย!\n(ในเว็บมีแค่ชื่อ: $availableIds)\nกรุณาไปแก้ Identifier ในเว็บ RevenueCat ให้มีคำว่า basic, pro หรือ ultimate',
      );
    }

    return package;
  }

  static Future<CustomerInfo> purchasePlan({
    required String planId,
    required String period,
  }) async {
    await configure();
    final package = await packageFor(planId: planId, period: period);
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return result.customerInfo;
  }

  static Future<CustomerInfo> restorePurchases() async {
    await configure();
    return Purchases.restorePurchases();
  }

  static String? activePlanFrom(CustomerInfo customerInfo) {
    final activePlans = customerInfo.entitlements.active.keys
        .map(_planFromIdentifier)
        .whereType<String>()
        .toSet();

    for (final plan in const ['ultimate', 'pro', 'basic']) {
      if (activePlans.contains(plan)) return plan;
    }
    return null;
  }

  static bool _packageMatches(Package package, String planId, String period) {
    final identifiers = [
      package.identifier,
      package.storeProduct.identifier,
    ].map(_normalizeIdentifier);
    final expectedPeriod = period == 'yearly' ? 'yearly' : 'monthly';

    return identifiers.any(
      (identifier) =>
          _planFromIdentifier(identifier) == _normalizeIdentifier(planId) &&
          _periodFromIdentifier(identifier) == expectedPeriod,
    );
  }

  static String _normalizeIdentifier(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static String? _planFromIdentifier(String value) {
    final tokens = _normalizeIdentifier(value).split('_');
    if (tokens.contains('ultimate')) return 'ultimate';
    if (tokens.contains('pro')) return 'pro';
    if (tokens.contains('basic')) return 'basic';
    return null;
  }

  static String? _periodFromIdentifier(String value) {
    final tokens = _normalizeIdentifier(value).split('_');
    if (tokens.any(const ['yearly', 'annual', 'year'].contains)) {
      return 'yearly';
    }
    if (tokens.any(const ['monthly', 'month'].contains)) return 'monthly';
    return null;
  }
}
