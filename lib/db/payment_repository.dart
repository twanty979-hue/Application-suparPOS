// lib/db/payment_repository.dart
import 'dart:convert'; // 🔥 สำคัญมาก: ต้องมีตัวนี้เพื่อใช้ jsonEncode
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart'; // ดึง Helper ตัวที่เราสร้างไว้คราวก่อนมาใช้

class PaymentRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> savePaymentToLocal({
    required Map<String, dynamic> newOrderData,
    required List<Map<String, dynamic>> itemsToSave,
    required Map<String, dynamic> paiOrderData,
    required Map<String, dynamic> syncPayload,
  }) async {
    final db = await _dbHelper.database;
    await _dbHelper.ensureOrderTokenColumns();

    // ครอบด้วย Transaction ป้องกันข้อมูลบันทึกครึ่งๆ กลางๆ เวลาเครื่องดับหรือมือลั่น
    await db.transaction((txn) async {
      // 1. บันทึกข้อมูลลงตาราง orders
      await txn.insert(
        'orders',
        Map<String, dynamic>.from(
          newOrderData,
        ), // ป้องกันปัญหาเรื่อง Type ขัดขืนด้วยการครอบ Map.from
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. ลูปรันบันทึกรายการอาหารลงตาราง order_items
      for (var originalItem in itemsToSave) {
        // ก๊อปปี้ค่าออกมาเป็น Map ตัวใหม่เพื่อให้สามารถแก้ไของค์ประกอบด้านในได้ชัวร์ๆ
        final item = Map<String, dynamic>.from(originalItem);

        if (item['promotion_snapshot'] != null) {
          // ถ้าข้างในเป็น Map หรือ Object ให้แปลงเป็นข้อความ JSON String ก่อนลง SQLite
          if (item['promotion_snapshot'] is! String) {
            item['promotion_snapshot'] = jsonEncode(item['promotion_snapshot']);
          }
        }

        await txn.insert(
          'order_items',
          item,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. บันทึกข้อมูลบิลจ่ายเงินลงตาราง pai_orders
      await txn.insert(
        'pai_orders',
        Map<String, dynamic>.from(paiOrderData),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. ฝังข้อมูลลงคิวรอยิงขึ้นระบบ Cloud (sync_queue)
      await txn.insert('sync_queue', {
        'type': 'PAYMENT',
        // 🚀 🚨 แก้ไขตรงนี้: จับ 3 ก้อนที่เซฟลงเครื่องมามัดรวมกันให้ API รู้จัก!
        'payload': jsonEncode({
          'newOrderData': newOrderData,
          'itemsToSave': itemsToSave,
          'paiOrderData': paiOrderData,
          'syncPayload': syncPayload,
        }),
        'status': 'pending',
      });
    }); // 👈 ปิดวงเล็บ db.transaction ตรงนี้ครับ (ที่มันหายไปรอบก่อน)

    print("✅ [SQLITE] บันทึกข้อมูลการชำระเงินออฟไลน์ลงเครื่องเสร็จสมบูรณ์!");
  }
}
