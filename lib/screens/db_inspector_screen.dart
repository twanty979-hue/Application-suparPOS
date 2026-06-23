// lib/screens/db_inspector_screen.dart
import 'package:flutter/material.dart';
import '../db/database_helper.dart';

class DbInspectorScreen extends StatefulWidget {
  const DbInspectorScreen({super.key});

  @override
  State<DbInspectorScreen> createState() => _DbInspectorScreenState();
}

class _DbInspectorScreenState extends State<DbInspectorScreen> {
  final List<String> _tables = [
    'sync_queue', 'orders', 'order_items', 'pai_orders',
    'categories', 'products', 'discounts', 'discount_products', 'stock_drafts'
  ];
  
  String _selectedTable = 'sync_queue';
  List<Map<String, dynamic>> _tableData = [];
  bool _isDataLoading = false; // รีเนมตัวแปรให้สื่อความหมายชัดเจนขึ้น

  @override
  void initState() {
    super.initState();
    _loadTableData();
  }

  Future<void> _loadTableData() async {
    if (!mounted) return;
    setState(() => _isDataLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      // เพิ่มความยืดหยุ่นในการดึงข้อมูล โดยถ้าเป็นตารางอื่นๆ ให้เรียงตาม id ด้วยเพื่อความง่ายต่อการตรวจทาน
      final data = await db.query(
        _selectedTable, 
        orderBy: _selectedTable == 'sync_queue' ? 'id DESC' : 'id ASC',
      );
      if (mounted) {
        setState(() => _tableData = data);
      }
    } catch (e) {
      print("❌ Error loading table [$_selectedTable]: $e");
    } finally {
      if (mounted) {
        setState(() => _isDataLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ดึงรายชื่อคอลัมน์จากแถวแรกมาทำเป็นหัวตาราง
    List<String> columns = _tableData.isNotEmpty ? _tableData.first.keys.toList() : [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('🗄️ ตารางในเครื่อง: $_selectedTable', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded), 
            onPressed: _loadTableData,
            tooltip: 'รีเฟรชข้อมูล',
          ),
        ],
      ),
      body: Column(
        children: [
          // แถบเลือกตาราง (Dropdown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
             border: Border(bottom: BorderSide(color: const Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Text('เปลี่ยนตาราง: ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedTable,
                    dropdownColor: Colors.white,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    items: _tables.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedTable = val);
                        _loadTableData();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // พื้นที่แสดงผลข้อมูล DataTable
          Expanded(
            child: _isDataLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _tableData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_open_rounded, size: 48, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 12),
                            Text('📬 ตาราง "$_selectedTable" ไม่มีข้อมูลในเครื่อง', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                          ],
                        ),
                      )
                    : InteractiveViewer(
                        maxScale: 2.5,
                        minScale: 0.8,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical, // 1. ครอบการ Scroll แนวตั้ง
                          physics: const BouncingScrollPhysics(),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal, // 2. ครอบการ Scroll แนวนอน
                            physics: const BouncingScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                                border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1, borderRadius: BorderRadius.circular(4)),
                                horizontalMargin: 16,
                                columnSpacing: 24,
                                columns: columns.map((colName) {
                                  return DataColumn(
                                    label: Text(
                                      colName.toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                rows: _tableData.map((row) {
                                  return DataRow(
                                    cells: columns.map((colName) {
                                      final val = row[colName];
                                      return DataCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 220), // จำกัดความกว้างของข้อความไม่ให้ตารางพัง
                                          child: Text(
                                            val == null ? '-' : val.toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}