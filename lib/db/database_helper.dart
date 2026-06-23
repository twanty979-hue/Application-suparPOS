// lib/db/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<void> deleteLocalDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, 'foodscan_offline.db'));
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('foodscan_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // 🔥 1. อัปเกรดเวอร์ชันจาก 5 เป็น 6 เพื่อทริกเกอร์ onUpgrade
    return await openDatabase(
      path,
      version: 10,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. ตารางหมวดหมู่
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        brand_id TEXT NOT NULL,
        name TEXT,
        sort_order INTEGER
      )
    ''');

    // 2. ตารางสินค้า
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        category_id TEXT,
        brand_id TEXT NOT NULL,
        barcode TEXT,
        sku TEXT,
        name TEXT,
        price REAL,
        price_special REAL,
        price_jumbo REAL,
        image_url TEXT,
        local_image_path TEXT,
        is_available INTEGER DEFAULT 1,
        item_type TEXT
      )
    ''');

    // 3. ตารางส่วนลด
    await db.execute('''
      CREATE TABLE discounts (
        id TEXT PRIMARY KEY,
        brand_id TEXT NOT NULL,
        type TEXT,
        value REAL,
        start_date TEXT,
        end_date TEXT,
        apply_normal INTEGER,
        apply_special INTEGER,
        apply_jumbo INTEGER,
        apply_to TEXT
      )
    ''');

    // 4. ตารางจับคู่ส่วนลด-สินค้า
    await db.execute('''
      CREATE TABLE discount_products (
        discount_id TEXT,
        product_id TEXT,
        PRIMARY KEY (discount_id, product_id)
      )
    ''');

    // 5. ตารางออเดอร์
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        brand_id TEXT NOT NULL,
        table_label TEXT,
        table_id TEXT,
        table_access_token TEXT,
        status TEXT,
        total_price REAL,
        type TEXT,
        payment_id TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // 6. ตารางรายการอาหารในออเดอร์
    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT,
        product_name TEXT,
        quantity INTEGER,
        price REAL,
        original_price REAL,
        discount REAL,
        variant TEXT,
        note TEXT,
        promotion_snapshot TEXT,
        status TEXT,
        cancelled_at TEXT,
        cancelled_by TEXT,
        cancel_reason TEXT,
        created_at TEXT,
        updated_at TEXT -- 🔥 เพิ่มแล้ว สำหรับคนลงแอปใหม่
      )
    ''');

    // 7. ตารางประวัติการจ่ายเงิน (PaiOrders)
    await db.execute('''
      CREATE TABLE pai_orders (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        brand_id TEXT NOT NULL,
        total_amount REAL,
        received_amount REAL,
        change_amount REAL,
        payment_method TEXT,
        cashier_id TEXT,
        created_at TEXT
      )
    ''');

    // 8. ตารางคิวอัปเดตข้อมูลขึ้นคลาวด์
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        payload TEXT,  
        status TEXT DEFAULT 'pending'
      )
    ''');

    // 9. ตารางดราฟต์สต็อกสินค้า
    await db.execute('''
      CREATE TABLE stock_drafts (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        barcode TEXT,
        name TEXT,
        qty INTEGER
      )
    ''');

    await _createStockAdjustmentDraftsTable(db);
    await _createPrinterSettingsTable(db);
  }

  Future<void> ensureStockAdjustmentDraftsTable() async {
    final db = await database;
    await _createStockAdjustmentDraftsTable(db);
  }

  Future<void> ensurePrinterSettingsTable() async {
    final db = await database;
    await _createPrinterSettingsTable(db);
  }

  Future<void> ensureOrderTokenColumns() async {
    final db = await database;
    await _ensureOrderTokenColumns(db);
  }

  Future<void> _ensureOrderTokenColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(orders)');
    final names = columns.map((column) => column['name']?.toString()).toSet();
    if (!names.contains('table_id')) {
      await db.execute('ALTER TABLE orders ADD COLUMN table_id TEXT;');
    }
    if (!names.contains('table_access_token')) {
      await db.execute(
        'ALTER TABLE orders ADD COLUMN table_access_token TEXT;',
      );
    }
  }

  Future<void> _createStockAdjustmentDraftsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_adjustment_drafts (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        barcode TEXT,
        sku TEXT,
        name TEXT,
        image_url TEXT,
        qty INTEGER,
        type TEXT
      )
    ''');
  }

  Future<void> _createPrinterSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS printer_settings (
        brand_id TEXT PRIMARY KEY,
        ip TEXT,
        mac TEXT,
        copies INTEGER DEFAULT 1,
        updated_at TEXT
      )
    ''');
  }

  Future<Map<String, dynamic>?> getPrinterSettings(String brandId) async {
    await ensurePrinterSettingsTable();
    final db = await database;
    final rows = await db.query(
      'printer_settings',
      where: 'brand_id = ?',
      whereArgs: [brandId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> savePrinterSettings({
    required String brandId,
    String? ip,
    String? mac,
    int copies = 1,
  }) async {
    await ensurePrinterSettingsTable();
    final db = await database;
    await db.insert('printer_settings', {
      'brand_id': brandId,
      'ip': ip?.trim() ?? '',
      'mac': mac?.trim() ?? '',
      'copies': copies <= 1 ? 1 : 2,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 🔥 2. ท่าไม้ตาย Migration: ถ้าเคยลงแอป(V5)ไว้ ให้ ALTER TABLE เติมคอลัมน์ให้อัตโนมัติ
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 6) {
      try {
        await db.execute("ALTER TABLE order_items ADD COLUMN updated_at TEXT;");
        print(
          "✨ [SQLite Migration] อัปเกรด V5 -> V6: เติมคอลัมน์ updated_at สำเร็จ!",
        );
      } catch (e) {
        print("⚠️ [SQLite Migration Error]: $e");
      }
    }

    if (oldVersion < 7) {
      await _createStockAdjustmentDraftsTable(db);
    }

    if (oldVersion < 8) {
      await _createPrinterSettingsTable(db);
    }
    if (oldVersion < 9) {
      await _ensureOrderTokenColumns(db);
    }
    if (oldVersion < 10) {
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN local_image_path TEXT;',
        );
      } catch (_) {
        // Column already exists on databases created by a development build.
      }
    }
  }
}
