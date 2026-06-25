// lib/screens/db_inspector_screen.dart
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';

class DbInspectorScreen extends StatefulWidget {
  const DbInspectorScreen({super.key});

  @override
  State<DbInspectorScreen> createState() => _DbInspectorScreenState();
}

class _DbInspectorScreenState extends State<DbInspectorScreen> {
  List<String> _tables = [];
  String? _selectedTable;
  List<Map<String, dynamic>> _tableData = [];
  bool _isDataLoading = false;

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
      final tables = await _loadTableNames(db);
      final selectedTable = _resolveSelectedTable(tables);
      final data = selectedTable == null
          ? <Map<String, dynamic>>[]
          : await db.query(
              selectedTable,
              orderBy: await _orderByForTable(db, selectedTable),
            );

      if (!mounted) return;
      setState(() {
        _tables = tables;
        _selectedTable = selectedTable;
        _tableData = data;
      });
    } catch (e) {
      debugPrint('Error loading table [$_selectedTable]: $e');
    } finally {
      if (mounted) {
        setState(() => _isDataLoading = false);
      }
    }
  }

  Future<List<String>> _loadTableNames(Database db) async {
    final rows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name COLLATE NOCASE
    ''');

    return rows
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toList();
  }

  String? _resolveSelectedTable(List<String> tables) {
    if (_selectedTable != null && tables.contains(_selectedTable)) {
      return _selectedTable;
    }
    if (tables.contains('sync_queue')) return 'sync_queue';
    return tables.isEmpty ? null : tables.first;
  }

  Future<String?> _orderByForTable(Database db, String table) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final names = columns.map((column) => column['name']?.toString()).toSet();
    if (!names.contains('id')) return null;
    return table == 'sync_queue' ? 'id DESC' : 'id ASC';
  }

  @override
  Widget build(BuildContext context) {
    final columns = _tableData.isNotEmpty ? _tableData.first.keys.toList() : [];
    final selectedTable = _selectedTable ?? '-';

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const AppSidebar(activeMenu: 'db_inspector'),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Open menu',
          ),
        ),
        title: Text(
          'Local database: $selectedTable',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadTableData,
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Text(
                  'Table:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedTable,
                    dropdownColor: Colors.white,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    items: _tables
                        .map(
                          (table) => DropdownMenuItem(
                            value: table,
                            child: Text(
                              table,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _tables.isEmpty
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedTable = value);
                            _loadTableData();
                          },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isDataLoading
                ? const SuparPosLoading(fullScreen: false)
                : _tables.isEmpty
                ? const Center(
                    child: Text(
                      'No local database tables found',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : _tableData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.folder_open_rounded,
                          size: 48,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Table "$selectedTable" has no local rows',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : InteractiveViewer(
                    maxScale: 2.5,
                    minScale: 0.8,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      physics: const BouncingScrollPhysics(),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF1E293B),
                            ),
                            border: TableBorder.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            horizontalMargin: 16,
                            columnSpacing: 24,
                            columns: columns
                                .map(
                                  (column) => DataColumn(
                                    label: Text(
                                      column.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            rows: _tableData.map((row) {
                              return DataRow(
                                cells: columns.map((column) {
                                  final value = row[column];
                                  return DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        value == null ? '-' : value.toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF334155),
                                          fontWeight: FontWeight.w500,
                                        ),
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
