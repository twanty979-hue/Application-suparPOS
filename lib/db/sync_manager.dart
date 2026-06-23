// lib/db/sync_manager.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
class SyncManager {
  final _dbHelper = DatabaseHelper.instance;

  // ฟังก์ชันนี้จะถูกเรียกให้ทำงานเป็นระยะ (อาจจะใช้ Timer หรือตอนแอปกลับมา Active)
  Future<void> runSyncWorker() async {
    // 1. จำลองการเช็คอินเทอร์เน็ต (ถ้าทำจริงแนะนำใช้แพ็กเกจ connectivity_plus)
    bool hasInternet = true; // สมมติว่ามีเน็ต
    if (!hasInternet) {
      print("❌ [SYNC] ไม่มีอินเทอร์เน็ต ข้ามการซิงค์...");
      return;
    }

    final db = await _dbHelper.database;

    // 2. กวาดข้อมูลที่ค้างอยู่ในคิว
    final pendingItems = await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'id ASC', // ซิงค์ตามลำดับคิวจากเก่าไปใหม่
    );

    if (pendingItems.isEmpty) {
      print("✅ [SYNC] ไม่มีข้อมูลค้างซิงค์");
      return;
    }

    print("🔄 [SYNC] พบข้อมูลค้าง ${pendingItems.length} รายการ กำลังเริ่มส่งขึ้น Cloud...");

    // 3. ทยอยยิงข้อมูลทีละตัว
    for (var item in pendingItems) {
      try {
        int queueId = item['id'] as int;
        String type = item['type'] as String;
        Map<String, dynamic> payload = jsonDecode(item['payload'] as String);

        if (type == 'PAYMENT') {
          // 🔑 ดึง access_token ที่เก็บไว้ตอน Login มาแนบใน Header
          final prefs = await SharedPreferences.getInstance();
          final accessToken = await StorageService.getToken();

          print("📡 [SYNC] กำลังยิงคิว ID $queueId ขึ้นเซิร์ฟเวอร์...");

          // 🚀 ยิง HTTP POST ไปที่ API ผ่าน ApiService (มันจะฉลาดดึงจาก .env ให้อัตโนมัติ)
          final response = await http.post(
            Uri.parse(ApiService.syncOffline), // 👈 เปลี่ยนมาใช้ตัวนี้แทน
            headers: {
              'Content-Type': 'application/json',
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(payload),
          );

          // 🎯 ตรวจสอบสถานะการตอบกลับจากเซิร์ฟเวอร์
          if (response.statusCode == 200 || response.statusCode == 201) {
            // บรรทัดที่เคยมีปัญหามันอยู่ตรงนี้ครับ ตอนนี้จับมัดรวมกันในบรรทัดเดียวแล้ว
            print("✅ [SYNC] ส่งข้อมูลคิว ID $queueId ขึ้น Cloud สำเร็จ!");

            // 4. ถ้าส่งสำเร็จชัวร์ๆ ให้เปลี่ยนสถานะใน SQLite เป็น done
            await db.update(
              'sync_queue',
              {'status': 'done'},
              where: 'id = ?',
              whereArgs: [queueId],
            );
          } else {
            // โยน Exception เพื่อให้คิวนี้คงค้างอยู่รอซิงค์ใหม่รอบหน้า
            throw Exception('เซิร์ฟเวอร์ตอบกลับรหัส: ${response.statusCode}');
          }
        }

      } catch (e) {
        print("❌ [SYNC] ส่งคิว ${item['id']} ไม่ผ่าน: $e (เก็บไว้ส่งรอบหน้า)");
      }
    }
  }
}