// lib/db/sync_manager.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';

class SyncManager {
  final _dbHelper = DatabaseHelper.instance;

  Set<String> _orderIdsFromPayload(Map<String, dynamic> payload) {
    final orderIds = <String>{};

    void addId(dynamic value) {
      final id = value?.toString().trim();
      if (id != null && id.isNotEmpty) orderIds.add(id);
    }

    void addIds(dynamic values) {
      if (values is List) {
        for (final value in values) {
          addId(value);
        }
      }
    }

    addId(payload['orderId']);
    addIds(payload['orderIds']);

    final newOrderData = payload['newOrderData'];
    if (newOrderData is Map) addId(newOrderData['id']);

    final paiOrderData = payload['paiOrderData'];
    if (paiOrderData is Map) addId(paiOrderData['order_id']);

    final syncPayload = payload['syncPayload'];
    if (syncPayload is Map) addIds(syncPayload['source_order_ids']);

    final items = payload['itemsToSave'];
    if (items is List) {
      for (final item in items) {
        if (item is Map) addId(item['order_id']);
      }
    }

    return orderIds;
  }

  Future<void> _removeSyncedLocalData(
    Database db,
    int queueId,
    Map<String, dynamic> payload,
  ) async {
    final newOrderData = payload['newOrderData'];
    final orderStatus = newOrderData is Map
        ? newOrderData['status']?.toString()
        : null;
    final shouldRemoveOrder =
        payload['action'] == 'cancel_order' ||
        orderStatus == 'paid' ||
        orderStatus == 'cancelled';
    final orderIds = shouldRemoveOrder
        ? _orderIdsFromPayload(payload).toList()
        : <String>[];

    await db.transaction((txn) async {
      if (orderIds.isNotEmpty) {
        final placeholders = List.filled(orderIds.length, '?').join(',');
        await txn.delete(
          'order_items',
          where: 'order_id IN ($placeholders)',
          whereArgs: orderIds,
        );
        await txn.delete(
          'pai_orders',
          where: 'order_id IN ($placeholders)',
          whereArgs: orderIds,
        );
        await txn.delete(
          'orders',
          where: 'id IN ($placeholders)',
          whereArgs: orderIds,
        );
      }

      await txn.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
    });
  }

  Future<void> cleanupCompletedQueue() async {
    final db = await _dbHelper.database;
    final completedItems = await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['done'],
      orderBy: 'id ASC',
    );

    for (final item in completedItems) {
      final queueId = item['id'] as int;
      final payload = jsonDecode(item['payload'] as String);
      if (payload is Map<String, dynamic>) {
        await _removeSyncedLocalData(db, queueId, payload);
      } else {
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
      }
    }
  }

  // ฟังก์ชันนี้จะถูกเรียกให้ทำงานเป็นระยะ (อาจจะใช้ Timer หรือตอนแอปกลับมา Active)
  Future<void> runSyncWorker({
    void Function(int completed, int total)? onProgress,
  }) async {
    final db = await _dbHelper.database;

    // 2. กวาดข้อมูลที่ค้างอยู่ในคิว
    final pendingItems = await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'id ASC', // ซิงค์ตามลำดับคิวจากเก่าไปใหม่
    );

    if (pendingItems.isEmpty) {
      onProgress?.call(0, 0);
      print("✅ [SYNC] ไม่มีข้อมูลค้างซิงค์");
      return;
    }

    print(
      "🔄 [SYNC] พบข้อมูลค้าง ${pendingItems.length} รายการ กำลังเริ่มส่งขึ้น Cloud...",
    );

    // 3. ทยอยยิงข้อมูลทีละตัว
    var failedCount = 0;
    var completedCount = 0;
    final accessToken = await StorageService.getToken();
    onProgress?.call(0, pendingItems.length);

    const batchSize = 4;
    for (var start = 0; start < pendingItems.length; start += batchSize) {
      final end = start + batchSize < pendingItems.length
          ? start + batchSize
          : pendingItems.length;
      final batch = pendingItems.sublist(start, end);

      await Future.wait(
        batch.map((item) async {
          try {
            int queueId = item['id'] as int;
            String type = item['type'] as String;
            Map<String, dynamic> payload = jsonDecode(
              item['payload'] as String,
            );

            if (type == 'PAYMENT') {
              // 🔑 ดึง access_token ที่เก็บไว้ตอน Login มาแนบใน Header
              print("📡 [SYNC] กำลังยิงคิว ID $queueId ขึ้นเซิร์ฟเวอร์...");

              // 🚀 ยิง HTTP POST ไปที่ API ผ่าน ApiService (มันจะฉลาดดึงจาก .env ให้อัตโนมัติ)
              final response = await http.post(
                Uri.parse(ApiService.syncOffline), // 👈 เปลี่ยนมาใช้ตัวนี้แทน
                headers: {
                  'Content-Type': 'application/json',
                  if (accessToken != null)
                    'Authorization': 'Bearer $accessToken',
                },
                body: jsonEncode(payload),
              );

              // 🎯 ตรวจสอบสถานะการตอบกลับจากเซิร์ฟเวอร์
              final responseBody = jsonDecode(response.body);
              final isSuccessful =
                  (response.statusCode == 200 || response.statusCode == 201) &&
                  responseBody is Map<String, dynamic> &&
                  responseBody['success'] == true;

              if (isSuccessful) {
                // บรรทัดที่เคยมีปัญหามันอยู่ตรงนี้ครับ ตอนนี้จับมัดรวมกันในบรรทัดเดียวแล้ว
                print("✅ [SYNC] ส่งข้อมูลคิว ID $queueId ขึ้น Cloud สำเร็จ!");

                await _removeSyncedLocalData(db, queueId, payload);
              } else {
                // โยน Exception เพื่อให้คิวนี้คงค้างอยู่รอซิงค์ใหม่รอบหน้า
                throw Exception(
                  'เซิร์ฟเวอร์ตอบกลับรหัส: ${response.statusCode}',
                );
              }
            }
            completedCount++;
            onProgress?.call(completedCount, pendingItems.length);
          } catch (e) {
            failedCount++;
            completedCount++;
            onProgress?.call(completedCount, pendingItems.length);
            print(
              "❌ [SYNC] ส่งคิว ${item['id']} ไม่ผ่าน: $e (เก็บไว้ส่งรอบหน้า)",
            );
          }
        }),
      );
    }

    if (failedCount > 0) {
      throw Exception('Sync failed for $failedCount item(s)');
    }
  }
}
