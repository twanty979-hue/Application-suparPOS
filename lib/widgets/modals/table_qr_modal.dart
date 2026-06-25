// lib/widgets/modals/table_qr_modal.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../api_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/printer_service.dart';

class TableQrModal extends StatefulWidget {
  final String tableLabel;
  final String tableId;
  final String brandId;
  final String authToken;
  final String qrMode;
  final List<String> initialTokens;

  const TableQrModal({
    super.key,
    required this.tableLabel,
    required this.tableId,
    required this.brandId,
    required this.authToken,
    required this.qrMode,
    required this.initialTokens,
  });

  static Future<void> show(
    BuildContext context,
    String tableLabel,
    String passcode,
    String brandId,
    String tableId, {
    List<String> accessTokens = const [],
    String qrMode = 'rotating',
    String authToken = '',
  }) {
    final tokens = accessTokens
        .where((token) => token.trim().isNotEmpty)
        .toList();
    final fallback = passcode.trim();

    return showDialog(
      context: context,
      barrierColor: Colors.black87.withValues(alpha: 0.7),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: TableQrModal(
          tableLabel: tableLabel,
          tableId: tableId.trim(),
          brandId: brandId.trim(),
          authToken: authToken,
          qrMode: qrMode,
          initialTokens: tokens.isNotEmpty
              ? tokens
              : [if (fallback.isNotEmpty) fallback],
        ),
      ),
    );
  }

  @override
  State<TableQrModal> createState() => _TableQrModalState();
}

class _TableQrModalState extends State<TableQrModal> {
  late List<String> _activeTokens;
  late String _mainToken;
  bool _multiMode = false;
  bool _isGenerating = false;
  int _printCount = 1;

  bool get _isStaticQr => widget.qrMode == 'static';
  String get _previewToken => _mainToken.isNotEmpty
      ? _mainToken
      : (_activeTokens.isNotEmpty ? _activeTokens.first : '');

  @override
  void initState() {
    super.initState();
    _activeTokens = _uniqueTokens(widget.initialTokens);
    _mainToken = _activeTokens.isNotEmpty ? _activeTokens.first : '';
  }

  List<String> _uniqueTokens(List<dynamic> values) {
    final seen = <String>{};
    final tokens = <String>[];
    for (final value in values) {
      final token = value.toString().trim();
      if (token.isEmpty || token.toLowerCase() == 'null') continue;
      if (seen.add(token)) tokens.add(token);
    }
    return tokens;
  }

  String _orderUrl([String? token]) {
    final cleanBrandId = widget.brandId.trim();
    final cleanTableId = widget.tableId.trim();
    final tokenPart = _isStaticQr ? '' : (token ?? _previewToken).trim();
    return 'https://pos-foodscan.com/shop/$cleanBrandId/table/$cleanTableId$tokenPart';
  }

  Future<void> _generateTokens() async {
    if (_isStaticQr || widget.authToken.trim().isEmpty) return;

    setState(() => _isGenerating = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/tables'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'action': 'generate_tokens',
          'id': widget.tableId,
          'label': widget.tableLabel,
          'count': _printCount,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['success'] != true) {
        throw Exception(data['error'] ?? 'Generate QR failed');
      }

      final tokens = _uniqueTokens(
        List<dynamic>.from(data['tokens'] ?? const []),
      );
      if (tokens.isEmpty) throw Exception('No tokens returned');

      setState(() {
        _activeTokens = tokens;
        _mainToken = tokens.first;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('สร้าง QR ไม่สำเร็จ: $e'),
          backgroundColor: AppColors.rose500,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _printTokens(List<String> tokens) async {
    final safeTokens = _uniqueTokens(tokens);
    if (safeTokens.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    var allOk = true;
    for (final token in safeTokens) {
      final ok = await PrinterService.printTableQr(
        brandId: widget.brandId,
        tableLabel: widget.tableLabel,
        passcode: _isStaticQr ? '' : token,
        orderUrl: _orderUrl(token),
      );
      allOk = allOk && ok;
      if (safeTokens.length > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          allOk
              ? 'พิมพ์ QR CODE สำเร็จ'
              : 'พิมพ์ QR บางใบไม่สำเร็จ กรุณาตรวจเครื่องพิมพ์',
        ),
        backgroundColor: allOk ? AppColors.emerald500 : Colors.redAccent,
      ),
    );
  }

  Widget _buildQrCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: QrImageView(
        data: _orderUrl(),
        version: QrVersions.auto,
        size: 200.0,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildPasscodeCard() {
    if (_isStaticQr) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'TABLE PASSCODE',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _previewToken.split('').join('  '),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildQrCard(),
        const SizedBox(height: 24),
        _buildPasscodeCard(),
        if (!_isStaticQr) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _multiMode = true),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
              label: Text('พิมพ์หลายใบ (${_activeTokens.length})'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _printTokens([_previewToken]),
            icon: const Icon(Icons.print, size: 16, color: Colors.white),
            label: const Text(
              'พิมพ์ใบนี้',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountButton(int count) {
    final active = _printCount == count;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _printCount = count),
        style: OutlinedButton.styleFrom(
          backgroundColor: active
              ? const Color(0xFF0F172A)
              : const Color(0xFFF1F5F9),
          foregroundColor: active ? Colors.white : const Color(0xFF64748B),
          side: BorderSide(
            color: active ? const Color(0xFF0F172A) : Colors.transparent,
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildMultiView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _multiMode = false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('กลับ'),
            ),
            const Spacer(),
            Text(
              'QR ทั้งหมด (${_activeTokens.length})',
              style: const TextStyle(
                color: AppColors.slate400,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ต้องการสร้างกี่ใบ',
                style: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildCountButton(1),
                  const SizedBox(width: 8),
                  _buildCountButton(4),
                  const SizedBox(width: 8),
                  _buildCountButton(5),
                  const SizedBox(width: 8),
                  _buildCountButton(10),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'จำนวนอื่น สูงสุด 50',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value) ?? _printCount;
                  setState(() => _printCount = parsed.clamp(1, 50));
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _generateTokens,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isGenerating
                        ? 'กำลังสร้าง...'
                        : 'สร้างชุดใหม่ $_printCount ใบ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          constraints: const BoxConstraints(maxHeight: 170),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: _activeTokens.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3.5,
            ),
            itemBuilder: (context, index) {
              final token = _activeTokens[index];
              final active = token == _previewToken;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() {
                  _mainToken = token;
                  _multiMode = false;
                }),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    token,
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.slate700,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _activeTokens.isEmpty
                ? null
                : () => _printTokens(_activeTokens),
            icon: const Icon(Icons.print, size: 16, color: Colors.white),
            label: Text(
              'พิมพ์ทั้งหมด (${_activeTokens.length})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald500,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    'โต๊ะ: ${widget.tableLabel}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _multiMode && !_isStaticQr
                  ? KeyedSubtree(
                      key: const ValueKey('multi'),
                      child: _buildMultiView(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('main'),
                      child: _buildMainView(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
