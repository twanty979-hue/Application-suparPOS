// lib/api_service.dart

import 'package:flutter/foundation.dart'; // 🌟 1. นำเข้า foundation เพื่อใช้ kReleaseMode
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // 🌟 2. ลอจิกสลับสวิตช์อัจฉริยะ (Deploy ปุ๊บ เปลี่ยนลิงก์ปั๊บ)
  static String get baseUrl {
    if (kReleaseMode) {
      // 🚀 โหมด Production (ตอนสั่ง flutter build apk/ipa เอาขึ้นสโตร์)
      // มันจะบังคับวิ่งเข้าลิงก์ของ Vercel เสมอ! นายไม่ต้องมานั่งแก้ IP แล้ว!
      return 'https://www.pos-foodscan.com/api';
    } else {
      // 🛠️ โหมด Debug (ตอนเทสเสียบสายรันในคอม)
      // ให้มันวิ่งไปอ่านไฟล์ .env ก่อน ถ้าไม่มีค่อย fallback เป็น IP เครื่องนาย
      return dotenv.env['NEXT_PUBLIC_API_BASE_URL'] ??
          'http://192.168.0.103:3000/api';
    }
  }

  static String get login => "$baseUrl/login";
  static String get register => "$baseUrl/register";
  static String get googleAuth => "$baseUrl/auth/google";
  static String get refreshSession => "$baseUrl/auth/refresh";
  static String get recovery => "$baseUrl/auth/recovery";
  static String get updatePassword => "$baseUrl/auth/password";
  static String get logout => "$baseUrl/auth/logout";
  static String get initPos => "$baseUrl/pos/init";
  static String get setupProfile => "$baseUrl/setup/profile";
  static String get setupBrand => "$baseUrl/setup/brand";
  static String get setupTutorial => "$baseUrl/tutorial";
  static String get settings => "$baseUrl/settings";
  static String get discounts => "$baseUrl/discounts";
  static String get products => "$baseUrl/products";
  static String get profile => "$baseUrl/profile";
  static String get staff => "$baseUrl/staff";
  static String get upload => "$baseUrl/upload";

  // 📦 สำหรับระบบสต็อก (Stock Inventory)
  static String get stockHistory => "$baseUrl/stock/history";
  static String get stockOverview => "$baseUrl/stock/overview";
  static String get adjustStock => "$baseUrl/stock/adjust";

  // 🚀 สำหรับระบบครัว
  static String get kitchenOrders => "$baseUrl/kitchen/orders";
  static String get kitchenUpdateStatus => "$baseUrl/kitchen/update-status";

  // 📊 สำหรับแดชบอร์ด
  static String get dashboard => "$baseUrl/dashboard";

  // 🎨 สำหรับระบบ Themes & Marketplace
  static String get themes => "$baseUrl/themes";
  static String get applyTheme => "$baseUrl/themes/apply";

  // 🚀 เพิ่มเส้นนี้สำหรับหน้าต่างร้านค้า
  static String get marketplace => "$baseUrl/marketplace";
  static String get purchaseTheme => "$baseUrl/marketplace/purchase";

  static String get syncOffline => "$baseUrl/pos/sync";

  static String get availablePlans => "$baseUrl/plans";
  static String get paymentPromptpay => "$baseUrl/payment/promptpay";
  static String get paymentCheckStatus => "$baseUrl/payment/status";
  static String get paymentUpgradeFree => "$baseUrl/payment/upgrade-free";
  // เติมบรรทัดนี้ไว้ด้านล่างสุดของ class ApiService ในไฟล์ lib/api_service.dart นะครับนาย
  static String get paymentHistory => "$baseUrl/payment/history";
}
